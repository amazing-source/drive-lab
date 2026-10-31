--!strict
--[[
	Scripted keyboard drifts on tools/DriveSim, for the drift's specs and tools/drift_turn.luau:
	how sharply Space turns the car, what a tap of it adds to a steered corner, and how the drift
	ends after a release, under braking or below the drift's speed gate. Every run turns right on
	the keys. It reads only the body's motion and the drift's `wants`, so it measures any drift law.
]]
local DriveSim = require("./DriveSim")
local InputHelp = require("../src/shared/Config/InputHelp")
local Types = require("../src/shared/Config/Cars/Types")

local KMH = 1 / 3.6
local PRESS = 1
local HOLD_LIMIT = 4
local AFTER = 2
local TURN = math.rad(90)
local WITHIN = 30
-- Body slip is read only above this speed (m/s); a stopped car has no direction of travel.
local SLIP_SPEED = 5
local SPIN = math.rad(45)

export type Turn = {
	-- Metres from the press to 90° of heading and of travel (math.huge if never), and the heading
	-- and travel turned (rad) within 30 m.
	headingAt90: number,
	travelAt90: number,
	heading30: number,
	travel30: number,
	-- Seconds held, body slip (rad) at the release, the most the heading moves over the 2 s after
	-- (rad), the body slip left at the end, and the speed then (km/h).
	held: number,
	slipAtRelease: number,
	headingDrift: number,
	slipAfter: number,
	endKmh: number,
}

export type Ending = {
	-- Seconds from the press to the drift's end; over the 2 s after it, the most the heading swings
	-- back against the turn (the snap) and on with it (rad), the most body slip (rad), and a spin.
	endedAt: number,
	headingBack: number,
	headingOn: number,
	peakSlip: number,
	spun: boolean,
}

local DriftTurn = {}

-- The gear the car would hold at `kmh` (its highest at or above 4,000 rpm).
function DriftTurn.gearFor(car: Types.CarConfig, kmh: number): number
	local wheel = kmh * KMH / car.rear.tyre.radius * car.driveline.rearReduction
	for gear = #car.gearbox.ratios, 1, -1 do
		if wheel * car.gearbox.ratios[gear] * 60 / (2 * math.pi) >= 4000 then
			return gear
		end
	end
	return 1
end

local function newSim(car: Types.CarConfig, kmh: number): DriveSim.Sim
	local sim = DriveSim.new(car, InputHelp.keyboard)
	DriveSim.setSpeed(sim, kmh * KMH, DriftTurn.gearFor(car, kmh))
	return sim
end

local function travelAngle(sim: DriveSim.Sim): number
	return math.atan2(sim.body.vy, sim.body.vx)
end

local function wrap(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

local function speedOf(sim: DriveSim.Sim): number
	return math.sqrt(sim.body.vx * sim.body.vx + sim.body.vy * sim.body.vy)
end

local function slipOf(sim: DriveSim.Sim): number
	local forward, right = DriveSim.localVelocity(sim.body)
	return math.atan2(right, math.abs(forward))
end

local function keys(
	car: Types.CarConfig,
	throttle: number,
	brake: number,
	steer: number,
	space: boolean
): DriveSim.InputOptions
	return {
		throttle = throttle,
		brake = brake,
		steer = steer,
		drift = space,
		handbrake = if space then 1 else 0,
		drivingMode = car.modeOrder[1],
		gearboxMode = "manual",
	}
end

local function cruise(sim: DriveSim.Sim, kmh: number): number
	return math.clamp(0.3 + 0.6 * (kmh * KMH - DriveSim.forwardSpeed(sim)), 0, 1)
end

-- Straight at `kmh`, then Space and the right key held with `throttle` until the travel has turned
-- 90° or 4 s have passed, then both released with the throttle at 0.3.
function DriftTurn.turn(car: Types.CarConfig, kmh: number, throttle: number, fps: number?): Turn
	local dt = 1 / (fps or 60)
	local sim = newSim(car, kmh)
	local outcome: Turn = {
		headingAt90 = math.huge,
		travelAt90 = math.huge,
		heading30 = 0,
		travel30 = 0,
		held = 0,
		slipAtRelease = 0,
		headingDrift = 0,
		slipAfter = 0,
		endKmh = 0,
	}
	local heading0, travel0, distance, lastX, lastY = 0, 0, 0, 0, 0
	local releasedAt, releaseHeading = math.huge, 0
	while sim.time < PRESS + HOLD_LIMIT + AFTER do
		local t = sim.time
		local held = t >= PRESS and releasedAt == math.huge
		local pedal = if held then throttle elseif t < PRESS then cruise(sim, kmh) else 0.3
		DriveSim.frame(sim, DriveSim.input(keys(car, pedal, 0, if held then 1 else 0, held)), dt)
		local body = sim.body
		if t < PRESS then
			heading0, travel0, lastX, lastY = body.heading, travelAngle(sim), body.x, body.y
			continue
		end
		distance += math.sqrt((body.x - lastX) ^ 2 + (body.y - lastY) ^ 2)
		lastX, lastY = body.x, body.y
		local heading, travel = body.heading - heading0, wrap(travelAngle(sim) - travel0)
		if held then
			if heading >= TURN and outcome.headingAt90 == math.huge then
				outcome.headingAt90 = distance
			end
			if travel >= TURN and outcome.travelAt90 == math.huge then
				outcome.travelAt90 = distance
			end
			if distance <= WITHIN then
				outcome.heading30, outcome.travel30 = heading, travel
			end
			if travel >= TURN or t >= PRESS + HOLD_LIMIT or speedOf(sim) < 3 then
				releasedAt, releaseHeading = sim.time, body.heading
				outcome.held = sim.time - PRESS
				outcome.slipAtRelease = slipOf(sim)
			end
		elseif sim.time - releasedAt <= AFTER then
			outcome.headingDrift = math.max(outcome.headingDrift, math.abs(body.heading - releaseHeading))
		end
	end
	outcome.slipAfter = slipOf(sim)
	outcome.endKmh = DriveSim.forwardSpeed(sim) / KMH
	return outcome
end

-- The heading turned (rad) 1.5 s after the right key goes down at `kmh` with the throttle off: with
-- Space tapped for 0.3 s at the same moment, and without it.
function DriftTurn.tap(car: Types.CarConfig, kmh: number, fps: number?): (number, number)
	local dt = 1 / (fps or 60)
	local function run(tapped: boolean): number
		local sim = newSim(car, kmh)
		local heading0 = 0
		while sim.time < PRESS + 1.5 do
			local t = sim.time
			local space = tapped and t >= PRESS and t < PRESS + 0.3
			local steer = if t >= PRESS then 1 else 0
			local pedal = if t < PRESS then cruise(sim, kmh) else 0
			DriveSim.frame(sim, DriveSim.input(keys(car, pedal, 0, steer, space)), dt)
			if t < PRESS then
				heading0 = sim.body.heading
			end
		end
		return sim.body.heading - heading0
	end
	return run(true), run(false)
end

-- Space and the right key held at `kmh` with the throttle off; with `braking`, the brake joins them
-- 0.6 s later. Either way the car slows under the drift's speed gate with Space still held; the
-- drift's end is measured over the 2 s after it.
function DriftTurn.ending(car: Types.CarConfig, kmh: number, braking: boolean, fps: number?): Ending
	local dt = 1 / (fps or 60)
	local sim = newSim(car, kmh)
	local outcome: Ending =
		{ endedAt = math.huge, headingBack = 0, headingOn = 0, peakSlip = 0, spun = false }
	local wanted, endHeading = false, 0
	while sim.time < PRESS + 8 do
		local t = sim.time
		local pressed = t >= PRESS
		local brake = if braking and t >= PRESS + 0.6 then 1 else 0
		local pedal = if pressed then 0 else cruise(sim, kmh)
		DriveSim.frame(sim, DriveSim.input(keys(car, pedal, brake, if pressed then 1 else 0, pressed)), dt)
		local wants = sim.model.drift.wants
		if wanted and not wants and outcome.endedAt == math.huge then
			outcome.endedAt, endHeading = sim.time - PRESS, sim.body.heading
		end
		wanted = wanted or wants
		local since = sim.time - PRESS - outcome.endedAt
		if since >= 0 and since <= AFTER then
			local moved = sim.body.heading - endHeading
			outcome.headingBack = math.max(outcome.headingBack, -moved)
			outcome.headingOn = math.max(outcome.headingOn, moved)
			if speedOf(sim) > SLIP_SPEED then
				local slip = math.abs(slipOf(sim))
				outcome.peakSlip = math.max(outcome.peakSlip, slip)
				outcome.spun = outcome.spun or slip > SPIN
			end
		end
		if since > AFTER then
			break
		end
	end
	return outcome
end

return table.freeze(DriftTurn)
