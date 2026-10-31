--!strict
--[[
	A scripted drift on tools/DriveSim, for the drift's specs and tools/drift.luau: straight at a
	speed for 1 s, then the drift button held for 3 s with the steering toward the turn and a
	throttle, then both released and the throttle holding the speed for 3 s more. It measures what
	the drift's balance is judged on: how fast it enters, the angle it holds and its peak, the speed
	it costs, and how cleanly it exits.
]]
local DriveSim = require("./DriveSim")
local InputHelp = require("../src/shared/Config/InputHelp")
local Model = require("../src/shared/Vehicle/Model")
local Types = require("../src/shared/Config/Cars/Types")

local KMH = 1 / 3.6
local PRESS, RELEASE, STOP = 1, 4, 7
-- Seconds the scripted pad takes to reach its steering; a keyboard's help ramps a full key itself.
local STEER_RAMP = 0.3

export type Options = {
	kmh: number,
	steer: number,
	throttle: number,
	-- 1 turns right, −1 left.
	side: number?,
	fps: number?,
	tc: boolean?,
	help: InputHelp.InputHelp?,
	gearboxMode: ("auto" | "manual")?,
	gear: number?,
}

export type Outcome = {
	-- Seconds from the press to 10° of body slip (math.huge if never).
	entry: number,
	-- Mean body slip (rad) over the last 1.5 s held, the peak while held, and the target there.
	held: number,
	peak: number,
	target: number,
	-- km/h lost per second while held (negative: gained).
	lossPerSecond: number,
	-- Most body slip (rad) the other way after the release; seconds from the release to under 3°.
	snap: number,
	settle: number,
	-- Over the last 1.5 s held: the mean share of the gearbox output sent forward, and the share of
	-- the time ESC acted. Over the last 1 s after the release: the mean forward share.
	frontShare: number,
	escShare: number,
	frontShareAfter: number,
	-- Mean rear slip ratio over the last 1.5 s held.
	rearSlipRatio: number,
	-- Shifts that begin while the drift is engaged (one already under way may finish).
	shifts: number,
}

local DriftScenario = {}

-- Body slip (rad), signed: positive when the velocity points right of the heading.
local function bodySlip(sim: DriveSim.Sim): number
	local forward, right = DriveSim.localVelocity(sim.body)
	return math.atan2(right, math.abs(forward))
end

local function speedOf(sim: DriveSim.Sim): number
	return math.sqrt(sim.body.vx * sim.body.vx + sim.body.vy * sim.body.vy)
end

-- The gear the car would hold at `kmh` (its highest at or above 4,000 rpm), so the run never
-- starts over the limiter.
local function gearFor(car: Types.CarConfig, kmh: number): number
	local wheel = kmh * KMH / car.rear.tyre.radius * car.driveline.rearReduction
	for gear = #car.gearbox.ratios, 1, -1 do
		if wheel * car.gearbox.ratios[gear] * 60 / (2 * math.pi) >= 4000 then
			return gear
		end
	end
	return 1
end

local function newOutcome(): Outcome
	return {
		entry = math.huge,
		held = 0,
		peak = 0,
		target = 0,
		lossPerSecond = 0,
		snap = 0,
		settle = math.huge,
		frontShare = 0,
		escShare = 0,
		frontShareAfter = 0,
		rearSlipRatio = 0,
		shifts = 0,
	}
end

function DriftScenario.run(car: Types.CarConfig, options: Options): Outcome
	local dt = 1 / (options.fps or 60)
	local side = options.side or 1
	local sim = DriveSim.new(car, options.help)
	DriveSim.setSpeed(sim, options.kmh * KMH, options.gear or gearFor(car, options.kmh))
	local mode = car.modeOrder[1]
	local outcome = newOutcome()
	local pressSpeed, releaseSpeed, heldFrames, afterFrames = 0, 0, 0, 0
	local wasShifting = false
	local ramp = if options.help then 0 else STEER_RAMP
	while sim.time < STOP do
		local t = sim.time
		local held = t >= PRESS and t < RELEASE
		local reach = if ramp > 0 then math.clamp((t - PRESS) / ramp, 0, 1) else 1
		local forward = DriveSim.forwardSpeed(sim)
		local hold = math.clamp(0.25 + 0.5 * (options.kmh * KMH - forward), 0, 1)
		local input = DriveSim.input({
			throttle = if held then options.throttle else hold,
			steer = if held then side * options.steer * reach else 0,
			drift = held,
			drivingMode = mode,
			gearboxMode = options.gearboxMode or "manual",
			tc = options.tc,
		})
		local result: Model.StepResult = DriveSim.frame(sim, input, dt)
		local slip = bodySlip(sim)
		if t < PRESS then
			pressSpeed = speedOf(sim)
		elseif held then
			if math.abs(slip) >= math.rad(10) and outcome.entry == math.huge then
				outcome.entry = sim.time - PRESS
			end
			outcome.peak = math.max(outcome.peak, math.abs(slip))
			releaseSpeed = speedOf(sim)
			local shifting = result.telemetry.shifting
			if result.telemetry.drift > 0 and shifting and not wasShifting then
				outcome.shifts += 1
			end
			wasShifting = shifting
			if t >= RELEASE - 1.5 then
				heldFrames += 1
				outcome.frontShare += result.telemetry.frontTorqueShare
				outcome.escShare += if result.telemetry.escActive then 1 else 0
				outcome.held += math.abs(slip)
				outcome.target += result.telemetry.driftTarget
				outcome.rearSlipRatio += (result.wheels[3].slipRatio + result.wheels[4].slipRatio) / 2
			end
		else
			-- A right-hand drift slides with the velocity left of the heading (negative slip).
			outcome.snap = math.max(outcome.snap, side * slip)
			if math.abs(slip) < math.rad(3) and outcome.settle == math.huge then
				outcome.settle = sim.time - RELEASE
			end
			if t >= STOP - 1 then
				afterFrames += 1
				outcome.frontShareAfter += result.telemetry.frontTorqueShare
			end
		end
	end
	local frames = math.max(heldFrames, 1)
	outcome.held /= frames
	outcome.target /= frames
	outcome.rearSlipRatio /= frames
	outcome.escShare /= frames
	outcome.frontShare /= frames
	outcome.frontShareAfter /= math.max(afterFrames, 1)
	outcome.lossPerSecond = (pressSpeed - releaseSpeed) / KMH / (RELEASE - PRESS)
	return outcome
end

return table.freeze(DriftScenario)
