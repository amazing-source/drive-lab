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

	A gearbox of kind "manual" is an H box with a clutch pedal (Vehicle/HBox, issue #209). Every
	shift follows a ShiftPlan, the automatic's included, and its gear engages when the lever reaches
	the gate. In "auto" and "manual" the automatic clutch works the pedal: the slip controller above
	at low speed, the plan's pedal during a shift, with the driver off the throttle from the clutch
	going down until it comes back up. In "manualClutch" the pedal is the player's, nothing cuts the
	throttle, a shift needs the pedal down, and the engine stalls under its stall speed while the
	clutch bites. A downshift that would over-rev is refused, as the ISR refuses it.
]]
local Engine = require("./Engine")
local HBox = require("./HBox")
local ShiftPlan = require("./ShiftPlan")
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
-- The H box's driver readies the hand and foot for the next upshift from this throttle, once the
-- engine is past this share of the mode's full-throttle upshift point.
local READY_THROTTLE = 0.9
local READY_RPM_SHARE = 0.8
-- The H box's phases as the ISR's: the clutch going down, the lever out of gear, the clutch coming up.
local PLAN_PHASES: { [ShiftPlan.Phase]: Phase } = {
	reach = "opening",
	clutchIn = "opening",
	leaveGate = "neutral",
	crossNeutral = "neutral",
	enterGate = "neutral",
	clutchOut = "closing",
	done = "engaged",
}

export type Phase = "engaged" | "opening" | "neutral" | "closing"
-- "manualClutch" is the H box's with the player's clutch; any other gearbox reads it as "manual".
export type GearboxMode = "auto" | "manual" | "manualClutch"

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
	-- The H box's plan, clutch pedal, stall and the driver's limbs; the ISR leaves it alone.
	hbox: HBox.State,
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
	-- The player's clutch pedal (0 up, 1 down), read in "manualClutch".
	clutchPedal: number,
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
		hbox = HBox.newState(),
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

-- The H box's mode: the player's clutch only on a car that offers it, "manual" otherwise.
local function boxMode(config: Types.GearboxConfig, context: Context): GearboxMode
	local manual = config.manual :: Types.ManualGearboxConfig
	if context.gearboxMode == "manualClutch" and not manual.playerClutch then
		return "manual"
	end
	return context.gearboxMode
end

local CLUTCH_UP: HBox.Refusal = "clutchUp"
local OVER_REV: HBox.Refusal = "overRev"

-- Whether the H box may go from `from` to `to`, and why not when the driver should hear of it:
-- reverse, neutral and first only near a standstill, as the ISR; a downshift that would over-rev
-- and a move with the player's clutch up are refused.
local function manualAllows(
	config: Types.GearboxConfig,
	engine: Types.EngineConfig,
	from: number,
	to: number,
	context: Context
): (boolean, HBox.Refusal?)
	local manual = config.manual :: Types.ManualGearboxConfig
	if to > #config.ratios or to < -1 then
		return false, nil
	end
	if math.min(from, to) <= 0 and context.groundSpeed >= config.selectorMaxSpeed then
		return false, nil
	end
	if boxMode(config, context) == "manualClutch" and context.clutchPedal < manual.bitePoint then
		return false, CLUTCH_UP
	end
	if to >= 1 and to < from then
		local lower = inputSpeed(config, to, context.outputSpeed)
		if lower >= (engine.limiterRpm - engine.limiterHysteresis) * RAD_PER_RPM then
			return false, OVER_REV
		end
	end
	return true, nil
end

-- The H box's shift to `to`, at the automatic's quick pace in "auto" and the human pace otherwise.
local function shiftManual(config: Types.GearboxConfig, state: GearboxState, to: number, mode: GearboxMode)
	if to > state.gear then
		state.sinceUpshift = 0
	end
	local manual = config.manual :: Types.ManualGearboxConfig
	local timing = if mode == "auto" then manual.autoTiming or manual.timing else manual.timing
	HBox.shift(manual, state.hbox, state.gear, to, timing)
end

-- The H box's E and Q: a step from the gear the lever is headed for, which retargets or queues a
-- running shift (Vehicle/HBox).
local function requestManual(
	config: Types.GearboxConfig,
	engine: Types.EngineConfig,
	state: GearboxState,
	up: boolean,
	context: Context
)
	local from = HBox.aimedGear(state.hbox, state.gear)
	local to = if up then from + 1 else from - 1
	local allowed: boolean, refusal: HBox.Refusal? = manualAllows(config, engine, from, to, context)
	state.hbox.refusal = refusal
	if allowed then
		shiftManual(config, state, to, boxMode(config, context))
	end
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
	if config.kind == "manual" then
		state.hbox.refusal = nil
		if up ~= down then
			requestManual(config, engine, state, up, context)
		end
		return
	end
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
	if config.kind == "manual" then
		shiftManual(config, state, gear, "auto")
		return true
	end
	state.gear, state.target = gear, gear
	return true
end

-- The gear the automatic shifts to now, if any.
local function autoTarget(
	config: Types.GearboxConfig,
	engine: Types.EngineConfig,
	state: GearboxState,
	context: Context
): number?
	local gear = state.gear
	if gear < 1 or context.holdGear then
		return nil
	end
	local mode = context.mode
	local rpm = inputSpeed(config, gear, context.outputSpeed) / RAD_PER_RPM
	if context.gearboxMode ~= "auto" then
		-- The ISR drops a gear rather than stall when the car slows in manual.
		if gear > 1 and rpm < engine.idleRpm then
			return gear - 1
		end
		return nil
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
			return gear - 1
		end
		return nil
	end
	local throttle = context.throttle
	-- Lifted in a mode that holds its gear, only the full-throttle point (near the limiter)
	-- still shifts up: the gear stays for the engine braking and the next corner.
	local up = if mode.holdOnLift and throttle < LIFTED
		then mode.upshiftRpm.full
		else mode.upshiftRpm.light + (mode.upshiftRpm.full - mode.upshiftRpm.light) * throttle
	local down = mode.downshiftRpm.light + (mode.downshiftRpm.full - mode.downshiftRpm.light) * throttle
	if gear < #ratios and rpm > up and rpm * ratios[gear + 1] / ratios[gear] > down then
		return gear + 1
	elseif
		gear > 1
		and rpm < down
		and rpm * ratios[gear - 1] / ratios[gear] < up * DOWNSHIFT_MARGIN
		and state.sinceUpshift >= config.upshiftHoldTime
	then
		return gear - 1
	end
	return nil
end

local function autoShift(
	config: Types.GearboxConfig,
	engine: Types.EngineConfig,
	state: GearboxState,
	context: Context
)
	local target = autoTarget(config, engine, state, context)
	if target then
		startShift(state, target, context.mode)
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

-- The automatic clutch: open while the brake holds a stopped car, slipping to a target engine speed
-- while the car gets moving, closed otherwise.
local function slipClutch(
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
end

local function updateClutch(
	config: Types.GearboxConfig,
	engine: Types.EngineConfig,
	state: GearboxState,
	context: Context,
	dt: number
)
	slipClutch(config, engine, state, context, dt)
	state.engagement = state.autoClutch * shiftFactor(config, state)
end

-- In manual, the gear the H box drops to once the car has slowed under idle in its gear, in one
-- shift: the highest that keeps the engine at idle, or first. As the ISR's manual, it drops rather
-- than lug or stall.
local function droppedGear(
	config: Types.GearboxConfig,
	engine: Types.EngineConfig,
	state: GearboxState,
	context: Context
): number?
	local gear = state.gear
	local idle = engine.idleRpm * RAD_PER_RPM
	if gear <= 1 or context.holdGear or inputSpeed(config, gear, context.outputSpeed) >= idle then
		return nil
	end
	for lower = gear - 1, 2, -1 do
		if inputSpeed(config, lower, context.outputSpeed) >= idle then
			return lower
		end
	end
	return 1
end

-- Runs the H box's plan: the gear engages at the gate, and a queued shift starts as the plan ends.
local function advancePlan(
	config: Types.GearboxConfig,
	engine: Types.EngineConfig,
	state: GearboxState,
	context: Context,
	dt: number
)
	local hbox = state.hbox
	local plan = hbox.plan
	if plan == nil then
		hbox.sincePlan += dt
		local mode: GearboxMode = boxMode(config, context)
		local target = if mode == "auto"
			then autoTarget(config, engine, state, context)
			elseif mode == "manual" then droppedGear(config, engine, state, context)
			else nil
		if target then
			shiftManual(config, state, target, mode)
		end
	else
		hbox.time += dt
		if hbox.time >= plan.gateIn then
			state.gear = plan.to
		end
		if hbox.time >= plan.clutchUp then
			hbox.plan, hbox.sincePlan = nil, 0
			local queued = hbox.queued
			hbox.queued = nil
			if queued then
				local allowed: boolean, refusal: HBox.Refusal? =
					manualAllows(config, engine, state.gear, queued, context)
				hbox.refusal = hbox.refusal or refusal
				if allowed then
					shiftManual(config, state, queued, boxMode(config, context))
				end
			end
		end
	end
	plan = hbox.plan
	if plan then
		state.target, state.upshift = plan.to, plan.to > plan.from
		state.phase = PLAN_PHASES[ShiftPlan.phase(plan, hbox.time)]
		state.phaseTime, state.duration = hbox.time, plan.clutchUp
	else
		state.target, state.phase, state.phaseTime = state.gear, "engaged", 0
	end
end

-- The H box's clutch: the player's pedal in "manualClutch", where a stopped car held on the brake
-- with the pedal down holds the launch speed as the automatic does; otherwise the automatic clutch,
-- opened further by the plan's pedal during a shift.
local function pedalClutch(
	config: Types.GearboxConfig,
	engine: Types.EngineConfig,
	state: GearboxState,
	context: Context,
	dt: number
)
	local manual = config.manual :: Types.ManualGearboxConfig
	local hbox = state.hbox
	if boxMode(config, context) == "manualClutch" then
		local pedal = context.clutchPedal
		hbox.pedal = pedal
		state.engagement = HBox.engagement(manual, pedal)
		state.autoClutch, state.launching = state.engagement, true
		state.holding = context.brake > HOLD_BRAKE
			and context.groundSpeed < config.selectorMaxSpeed
			and pedal >= manual.bitePoint
		return
	end
	slipClutch(config, engine, state, context, dt)
	local plan = hbox.plan
	local planPedal = if plan then ShiftPlan.clutch(plan, hbox.time) else 0
	state.engagement = state.autoClutch * HBox.engagement(manual, planPedal)
	hbox.pedal = math.max(planPedal, HBox.pedalFor(manual, state.autoClutch))
end

-- The H box's substep; returns as Gearbox.update does.
local function updateManual(
	config: Types.GearboxConfig,
	engine: Types.EngineConfig,
	state: GearboxState,
	context: Context,
	dt: number
): (boolean, number, number)
	local manual = config.manual :: Types.ManualGearboxConfig
	local hbox = state.hbox
	local mode = boxMode(config, context)
	local own = mode == "manualClutch"
	state.sinceUpshift += dt
	advancePlan(config, engine, state, context, dt)
	pedalClutch(config, engine, state, context, dt)
	if not own then
		hbox.stalled = false
	elseif
		state.engagement > 0
		and state.gear ~= 0
		and state.phase ~= "neutral"
		and context.engineSpeed < manual.stallRpm * RAD_PER_RPM
	then
		hbox.stalled = true
	end
	local ready = state.gear >= 1
		and state.gear < #config.ratios
		and context.throttle >= READY_THROTTLE
		and context.engineSpeed >= context.mode.upshiftRpm.full * READY_RPM_SHARE * RAD_PER_RPM
	HBox.moveLimbs(manual, hbox, ready, dt)
	local plan = hbox.plan
	if own or plan == nil then
		return false, 0, 1
	end
	local phase = ShiftPlan.phase(plan, hbox.time)
	if phase == "reach" then
		return false, 0, 1
	elseif phase == "clutchOut" then
		return false, 0, 1 - ShiftPlan.clutch(plan, hbox.time)
	elseif
		(manual.revMatch or mode == "auto")
		and plan.to >= 1
		and plan.to < plan.from
		and state.phase == "neutral"
	then
		local aim = inputSpeed(config, plan.to, context.outputSpeed)
		return false, math.clamp((aim - context.engineSpeed) / (aim * BLIP_BAND), 0, 1), 0
	end
	return true, 0, 1
end

-- Advances the gearbox one substep. Returns whether the engine's torque is cut, the throttle a
-- downshift blip asks for (0 when none), and the share of the driver's throttle that goes through
-- (the H box's driver feeding it back in as the clutch comes up; 1 otherwise).
function Gearbox.update(
	config: Types.GearboxConfig,
	engine: Types.EngineConfig,
	state: GearboxState,
	context: Context,
	dt: number
): (boolean, number, number)
	if config.kind == "manual" then
		return updateManual(config, engine, state, context, dt)
	end
	state.sinceUpshift += dt
	if Gearbox.isShifting(state) then
		advanceShift(config, state, dt)
	else
		autoShift(config, engine, state, context)
	end
	updateClutch(config, engine, state, context, dt)
	if not Gearbox.isShifting(state) then
		return false, 0, 1
	end
	if state.upshift then
		return state.phase == "opening" or state.phase == "neutral", 0, 1
	end
	if state.phase ~= "neutral" then
		return false, 0, 1
	end
	local aim = inputSpeed(config, state.target, context.outputSpeed)
	return false, math.clamp((aim - context.engineSpeed) / (aim * BLIP_BAND), 0, 1), 1
end

-- Whether the H box's automatic clutch is slipping to get the car moving. The engine is then held
-- at the top of the clutch's slip band over the launch speed, as a driver holds the revs while
-- letting the clutch out, and as TracKey's launch control holds them until the clutch is up.
function Gearbox.pullingAway(config: Types.GearboxConfig, state: GearboxState, context: Context): boolean
	return config.kind == "manual"
		and boxMode(config, context) ~= "manualClutch"
		and state.launching
		and state.gear ~= 0
end

-- Whether the H box's engine has stalled (only ever with the player's clutch).
function Gearbox.stalled(state: GearboxState): boolean
	return state.hbox.stalled
end

-- Clears a stall when the engine may start: in neutral or with the clutch pedal down, as a clutch
-- interlock asks. Returns whether it did.
function Gearbox.restart(config: Types.GearboxConfig, state: GearboxState, clutchPedal: number): boolean
	local manual = config.manual
	if not state.hbox.stalled or manual == nil then
		return false
	end
	if state.gear ~= 0 and clutchPedal < manual.bitePoint then
		return false
	end
	state.hbox.stalled = false
	return true
end

-- Torque the clutch can carry now (N·m).
function Gearbox.clutchCapacity(config: Types.GearboxConfig, state: GearboxState): number
	return config.clutchTorque * state.engagement
end

return table.freeze(Gearbox)
