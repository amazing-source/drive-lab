--!strict
--[[
	The ISR: a seven-speed single-clutch box with an automated clutch (01 §2.3, 02 T1/T8).
	A shift cuts torque, opens the clutch, sits in neutral, selects the new ratio and closes the
	clutch again; the slip while it closes drags the engine to its new speed, which is the
	single-clutch kick. Downshifts blip the throttle toward the new speed during neutral.
	Times and shift points come from the drive mode.

	The automatic clutch is a slip controller while the car gets moving: it sets the clutch's
	capacity to hold the engine at a target speed (creep at a closed throttle, the launch speed
	at full) until the gearbox input reaches that speed, then stays closed until the input
	falls back under the creep speed. Holding the brake at a standstill keeps it open, which is
	also how launch control holds the engine.
]]
local Engine = require("./Engine")
local Types = require("../Config/Cars/Types")

local RAD_PER_RPM = Engine.RAD_PER_RPM
-- Brake pedal above which a stopped car's clutch is held open.
local HOLD_BRAKE = 0.1
-- An auto downshift must land this far under the upshift point, so it cannot hunt.
local DOWNSHIFT_MARGIN = 0.97
-- Brake pedal above which the automatic shifts for braking: down through the gears, never up.
local BRAKING = 0.1
-- Throttle below this counts as lifted.
local LIFTED = 0.1
-- Engine-speed error (share of the blip target) over which the blip goes from closed to open.
local BLIP_BAND = 0.1

export type Phase = "engaged" | "opening" | "neutral" | "closing"
export type GearboxMode = "auto" | "manual"

export type GearboxState = {
	-- Selected ratio: −1 reverse, 0 neutral, 1 to top. During a shift it stays the old gear
	-- until neutral ends.
	gear: number,
	target: number,
	phase: Phase,
	phaseTime: number,
	duration: number,
	upshift: boolean,
	autoClutch: number,
	engagement: number,
	holding: boolean,
	launching: boolean,
	-- Seconds since the last upshift began.
	sinceUpshift: number,
}

-- What the gearbox needs to know each substep. Speeds in rad/s except `groundSpeed` (m/s).
export type Context = {
	engineSpeed: number,
	-- Gearbox output speed.
	outputSpeed: number,
	-- Engine torque at the current throttle, before the clutch.
	engineTorque: number,
	groundSpeed: number,
	throttle: number,
	brake: number,
	mode: Types.ModeConfig,
	gearboxMode: GearboxMode,
	-- The automatic keeps its gear (a launch whose car does not shift up by itself).
	holdGear: boolean,
}

local Gearbox = {}

function Gearbox.newState(): GearboxState
	return {
		gear = 1,
		target = 1,
		phase = "engaged",
		phaseTime = 0,
		duration = 0,
		upshift = true,
		autoClutch = 0,
		engagement = 0,
		holding = false,
		launching = true,
		sinceUpshift = math.huge,
	}
end

-- Signed ratio from engine to gearbox output for `gear`; reverse turns the output backwards.
function Gearbox.ratio(config: Types.GearboxConfig, gear: number): number
	if gear > 0 then
		return config.ratios[gear]
	elseif gear < 0 then
		return -config.reverseRatio
	end
	return 0
end

-- Share of the driver's throttle reverse lets through at `forwardSpeed` (m/s, negative going
-- backwards): all of it until the last `reverseCutBand` before the top speed, none from there.
function Gearbox.reverseCut(config: Types.GearboxConfig, gear: number, forwardSpeed: number): number
	if gear >= 0 then
		return 1
	end
	return math.clamp((config.reverseMaxSpeed + forwardSpeed) / config.reverseCutBand, 0, 1)
end

function Gearbox.isShifting(state: GearboxState): boolean
	return state.phase ~= "engaged"
end

local function startShift(state: GearboxState, target: number, mode: Types.ModeConfig)
	state.upshift = target > state.gear
	if state.upshift then
		state.sinceUpshift = 0
	end
	state.target = target
	state.phase = "opening"
	state.phaseTime = 0
	state.duration = if state.upshift then mode.upshiftTime else mode.downshiftTime
end

-- Engine speed the gearbox input would turn at in `gear`.
local function inputSpeed(config: Types.GearboxConfig, gear: number, outputSpeed: number): number
	return math.abs(Gearbox.ratio(config, gear) * outputSpeed)
end

-- Paddle presses (edges). Between reverse, neutral and first the selector moves only near a
-- standstill; a downshift that would over-rev is refused, as the ISR refuses it.
function Gearbox.request(
	config: Types.GearboxConfig,
	engine: Types.EngineConfig,
	state: GearboxState,
	up: boolean,
	down: boolean,
	context: Context
)
	if Gearbox.isShifting(state) or up == down then
		return
	end
	local slow = context.groundSpeed < config.selectorMaxSpeed
	local gear = state.gear
	if up then
		if gear <= 0 then
			if slow then
				state.gear, state.target = gear + 1, gear + 1
			end
		elseif gear < #config.ratios then
			startShift(state, gear + 1, context.mode)
		end
		return
	end
	if gear > 1 then
		local lower = inputSpeed(config, gear - 1, context.outputSpeed)
		if lower < (engine.limiterRpm - engine.limiterHysteresis) * RAD_PER_RPM then
			startShift(state, gear - 1, context.mode)
		end
	elseif gear >= 0 and slow then
		state.gear, state.target = gear - 1, gear - 1
	end
end

-- Moves the selector straight to `gear` (reverse, or first from reverse) near a standstill, with
-- no shift; refused during one. Returns whether it moved.
function Gearbox.select(
	config: Types.GearboxConfig,
	state: GearboxState,
	gear: number,
	groundSpeed: number
): boolean
	if Gearbox.isShifting(state) or groundSpeed >= config.selectorMaxSpeed then
		return false
	end
	state.gear, state.target = gear, gear
	return true
end

local function autoShift(
	config: Types.GearboxConfig,
	engine: Types.EngineConfig,
	state: GearboxState,
	context: Context
)
	local gear = state.gear
	if gear < 1 or context.holdGear then
		return
	end
	local mode = context.mode
	local rpm = inputSpeed(config, gear, context.outputSpeed) / RAD_PER_RPM
	if context.gearboxMode == "manual" then
		-- The ISR drops a gear rather than stall when the car slows in manual.
		if gear > 1 and rpm < engine.idleRpm then
			startShift(state, gear - 1, mode)
		end
		return
	end
	local ratios = config.ratios
	if context.brake > BRAKING then
		-- Down through the gears while braking, each landing below the limiter: engine braking
		-- and the right gear for the exit, as the ISR does. No upshifts until the brake is off.
		local target = mode.downshiftRpm.light
			+ (mode.brakeDownshiftRpm - mode.downshiftRpm.light) * context.brake
		local ceiling = engine.limiterRpm - engine.limiterHysteresis
		if
			gear > 1
			and rpm < target
			and rpm * ratios[gear - 1] / ratios[gear] < ceiling * DOWNSHIFT_MARGIN
		then
			startShift(state, gear - 1, mode)
		end
		return
	end
	local throttle = context.throttle
	-- Lifted in a mode that holds its gear, only the full-throttle point (near the limiter)
	-- still shifts up: the gear stays for the engine braking and the next corner.
	local up = if mode.holdOnLift and throttle < LIFTED
		then mode.upshiftRpm.full
		else mode.upshiftRpm.light + (mode.upshiftRpm.full - mode.upshiftRpm.light) * throttle
	local down = mode.downshiftRpm.light + (mode.downshiftRpm.full - mode.downshiftRpm.light) * throttle
	if gear < #ratios and rpm > up and rpm * ratios[gear + 1] / ratios[gear] > down then
		startShift(state, gear + 1, mode)
	elseif
		gear > 1
		and rpm < down
		and rpm * ratios[gear - 1] / ratios[gear] < up * DOWNSHIFT_MARGIN
		and state.sinceUpshift >= config.upshiftHoldTime
	then
		startShift(state, gear - 1, mode)
	end
end

-- Share of the automatic clutch's engagement the shift allows.
local function shiftFactor(config: Types.GearboxConfig, state: GearboxState): number
	local openTime = state.duration * config.shiftOpenShare
	local neutralEnd = openTime + state.duration * config.shiftNeutralShare
	if state.phase == "opening" then
		return 1 - state.phaseTime / openTime
	elseif state.phase == "neutral" then
		return 0
	elseif state.phase == "closing" then
		return math.clamp((state.phaseTime - neutralEnd) / (state.duration - neutralEnd), 0, 1)
	end
	return 1
end

local function advanceShift(config: Types.GearboxConfig, state: GearboxState, dt: number)
	state.phaseTime += dt
	local openTime = state.duration * config.shiftOpenShare
	local neutralEnd = openTime + state.duration * config.shiftNeutralShare
	if state.phase == "opening" and state.phaseTime >= openTime then
		state.phase = "neutral"
	end
	if state.phase == "neutral" and state.phaseTime >= neutralEnd then
		state.phase = "closing"
		state.gear = state.target
	end
	if state.phase == "closing" and state.phaseTime >= state.duration then
		state.phase = "engaged"
	end
end

local function updateClutch(
	config: Types.GearboxConfig,
	engine: Types.EngineConfig,
	state: GearboxState,
	context: Context,
	dt: number
)
	state.holding = context.brake > HOLD_BRAKE and context.groundSpeed < config.selectorMaxSpeed
	local input = inputSpeed(config, state.gear, context.outputSpeed)
	if input < config.clutchCreepRpm * RAD_PER_RPM * (1 - config.clutchSlipBand) then
		state.launching = true
	end
	local target = 0
	if state.gear ~= 0 and not state.holding then
		if state.launching then
			local aimRpm = config.clutchCreepRpm
				+ (engine.launchRpm - config.clutchCreepRpm) * context.throttle
			local aim = aimRpm * RAD_PER_RPM
			local band = aim * config.clutchSlipBand
			local slipping = context.engineTorque / config.clutchTorque + (context.engineSpeed - aim) / band
			local closing = (input - (aim - band)) / band
			target = math.clamp(math.max(slipping, closing), 0, 1)
			state.launching = closing < 1
		else
			target = 1
		end
	end
	if target < state.autoClutch then
		state.autoClutch = target
	else
		state.autoClutch = math.min(target, state.autoClutch + dt / config.clutchCloseTime)
	end
	state.engagement = state.autoClutch * shiftFactor(config, state)
end

-- Advances the gearbox one substep. Returns whether the engine's torque is cut and the
-- throttle a downshift blip asks for (0 when none).
function Gearbox.update(
	config: Types.GearboxConfig,
	engine: Types.EngineConfig,
	state: GearboxState,
	context: Context,
	dt: number
): (boolean, number)
	state.sinceUpshift += dt
	if Gearbox.isShifting(state) then
		advanceShift(config, state, dt)
	else
		autoShift(config, engine, state, context)
	end
	updateClutch(config, engine, state, context, dt)
	if not Gearbox.isShifting(state) then
		return false, 0
	end
	if state.upshift then
		return state.phase == "opening" or state.phase == "neutral", 0
	end
	if state.phase ~= "neutral" then
		return false, 0
	end
	local aim = inputSpeed(config, state.target, context.outputSpeed)
	return false, math.clamp((aim - context.engineSpeed) / (aim * BLIP_BAND), 0, 1)
end

-- Torque the clutch can carry now (N·m).
function Gearbox.clutchCapacity(config: Types.GearboxConfig, state: GearboxState): number
	return config.clutchTorque * state.engagement
end

return table.freeze(Gearbox)
