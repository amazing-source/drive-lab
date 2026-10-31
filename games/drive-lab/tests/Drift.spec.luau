--!strict
--[[
	The arcade drift (Vehicle/Drift), unit by unit, then on both cars through tools/DriftTurn, driven
	on the keys. The bounds are the issue's targets (#195): about 90° of heading and travel within
	about 30 m at 80 km/h, and the heading held after the drift ends.
]]
local Config = require("../src/shared/Config/Drift")
local DR458 = require("../src/shared/Config/Cars/DR458/Physics")
local Drift = require("../src/shared/Vehicle/Drift")
local DriftTurn = require("../tools/DriftTurn")
local DriveSim = require("../tools/DriveSim")
local InputHelp = require("../src/shared/Config/InputHelp")
local SVJ = require("../src/shared/Config/Cars/SVJ/Physics")
local T = require("../../../tools/test/T")
local Types = require("../src/shared/Config/Cars/Types")

local describe, it, expect = T.describe, T.it, T.expect

local KMH = 1 / 3.6
local DT = 1 / 60
local CARS: { Types.CarConfig } = { SVJ, DR458 }

local function profileOf(car: Types.CarConfig): Types.DriftProfile
	return car.drift :: Types.DriftProfile
end

-- A state stepped `frames` frames at `kmh` straight ahead with the button and steering given.
local function stepped(frames: number, held: boolean, steer: number, kmh: number): Drift.DriftState
	local state = Drift.newState()
	for _ = 1, frames do
		Drift.update(profileOf(DR458), state, held, steer, kmh * KMH, 0, 0, DT)
	end
	return state
end

describe("Drift gate and engagement", function()
	it("engages only held, moving forward above 30 km/h, and steered past the gate", function()
		expect(stepped(5, true, 1, 80).wants).toBe(true)
		expect(stepped(5, false, 1, 80).wants).toBe(false)
		expect(stepped(5, true, 1, 29).wants).toBe(false)
		expect(stepped(5, true, 0.2, 80).wants).toBe(false)
		local reversing = Drift.newState()
		Drift.update(profileOf(DR458), reversing, true, 1, -12, 0, 0, DT)
		expect(reversing.wants).toBe(false)
	end)

	it("rises to full in its rise time and falls to nothing in its fall time", function()
		local frames = math.round(Config.RISE_TIME / DT)
		expect(stepped(frames - 1, true, 1, 80).engagement < 1).toBe(true)
		local state = stepped(frames, true, 1, 80)
		expect(state.engagement).toBeNear(1, 1e-9)
		for _ = 1, math.round(Config.FALL_TIME / DT) - 1 do
			Drift.update(profileOf(DR458), state, false, 0, 80 * KMH, 0, 0, DT)
		end
		expect(state.engagement > 0).toBe(true)
		Drift.update(profileOf(DR458), state, false, 0, 80 * KMH, 0, 0, DT)
		expect(state.engagement).toBeNear(0, 1e-9)
	end)
end)

describe("Drift law", function()
	it("asks the steering's share of the turn rate, capped by the turn's sideways acceleration", function()
		local profile = profileOf(SVJ)
		expect(Drift.turnRate(profile, 10)).toBe(math.min(profile.turnRate, profile.turnAccel / 10))
		expect(Drift.turnRate(profile, 40)).toBeNear(profile.turnAccel / 40, 1e-12)
		local state = Drift.newState()
		Drift.update(profile, state, true, -0.5, 30, 0, 0.7, DT)
		expect(state.yawTarget).toBeNear(-0.5 * Drift.turnRate(profile, 30), 1e-12)
		expect(state.target).toBeNear(0.5 * Drift.turnRate(profile, 30) / profile.alignRate, 1e-12)
	end)

	it("follows the player's own steering once released, and ends when the slip has closed", function()
		local profile = profileOf(SVJ)
		local state = Drift.newState()
		Drift.update(profile, state, true, 1, 25, -8, 0, DT)
		Drift.update(profile, state, false, 0, 25, -8, 0.25, DT)
		expect(state.exiting).toBe(true)
		expect(state.yawTarget).toBe(0.25)
		Drift.update(profile, state, false, 0, 25, -25 * math.tan(Config.EXIT_SLIP / 2), 0, DT)
		expect(state.exiting).toBe(false)
		expect(Drift.active(state)).toBe(true)
	end)

	it("does nothing while neither engaged nor ending", function()
		local profile = profileOf(SVJ)
		local state = Drift.newState()
		local forward, right, torque = Drift.forces(SVJ, profile, state, 25, -6, 0.8, 5000)
		expect(forward).toBe(0)
		expect(right).toBe(0)
		expect(torque).toBe(0)
		local front, rear = Drift.grip(profile, state)
		expect(front).toBe(1)
		expect(rear).toBe(1)
		expect(Drift.tcSlip(profile, state, 0.08)).toBe(0.08)
		expect(Drift.couplingCapacity(profile, state, 1234.5, 3000)).toBe(1234.5)
		expect(Drift.steer(SVJ, state, 0.37, 20, -5, 0.4)).toBe(0.37)
	end)

	it("turns the velocity onto the heading without changing its length, and scrubs speed apart", function()
		local profile = profileOf(DR458)
		local state = stepped(30, true, 1, 80)
		local forwardSpeed, rightSpeed = 20, -8
		local fx, fy = Drift.forces(DR458, profile, state, forwardSpeed, rightSpeed, 0, 0)
		local slip = math.atan2(rightSpeed, forwardSpeed)
		local turn = DR458.mass * profile.alignRate * slip
		local speed = math.sqrt(forwardSpeed ^ 2 + rightSpeed ^ 2)
		local scrub = DR458.mass * profile.scrub * math.abs(slip) / speed
		expect(fx).toBeNear(turn * rightSpeed - scrub * forwardSpeed, 1e-6)
		expect(fy).toBeNear(-turn * forwardSpeed - scrub * rightSpeed, 1e-6)
		expect(fy > 0).toBe(true)
		-- Without the scrub the force is square to the velocity, so it turns it without speeding or
		-- slowing it.
		local noScrub = table.clone(profile)
		noScrub.scrub = 0
		local tx, ty = Drift.forces(DR458, noScrub, state, forwardSpeed, rightSpeed, 0, 0)
		expect(math.abs(tx * forwardSpeed + ty * rightSpeed) < 1e-6 * math.abs(ty * forwardSpeed)).toBe(true)
		expect(math.abs(ty) > 1000).toBe(true)
	end)

	it("brings the yaw rate to its target whatever the tyres' own moment", function()
		local profile = profileOf(SVJ)
		local state = stepped(30, true, 1, 80)
		local _, _, freeTorque = Drift.forces(SVJ, profile, state, 22, -5, 0.5, 0)
		local _, _, againstTyres = Drift.forces(SVJ, profile, state, 22, -5, 0.5, 4000)
		expect(againstTyres).toBeNear(freeTorque - 4000, 1e-6)
		local gap = math.clamp((state.yawTarget - 0.5) / Config.YAW_TIME, -Config.YAW_ACCEL, Config.YAW_ACCEL)
		expect(freeTorque).toBeNear(SVJ.yawInertia * gap, 1e-6)
	end)

	it("keeps part of the front's sideways grip and of the rear's grip while engaged", function()
		local profile = profileOf(SVJ)
		local front, rear = Drift.grip(profile, stepped(30, true, 1, 80))
		expect(front).toBeNear(profile.frontGrip, 1e-12)
		expect(rear).toBeNear(profile.rearGrip, 1e-12)
		local state = stepped(30, true, 1, 80)
		expect(Drift.tcSlip(profile, state, 0.08)).toBeNear(profile.tcSlip, 1e-12)
		expect(Drift.couplingCapacity(profile, state, 1200, 3000)).toBeNear(profile.frontShare * 3000, 1e-9)
	end)
end)

describe("Drift on both cars, on the keys", function()
	it("turns heading and travel 90° within 35 m at 80 km/h, throttle off or on, and 30 m at 60", function()
		for _, car in CARS do
			for _, throttle in { 0, 1 } do
				local fast = DriftTurn.turn(car, 80, throttle)
				expect(fast.headingAt90 <= fast.travelAt90).toBe(true)
				expect(fast.travelAt90 <= 35).toBe(true)
				expect(DriftTurn.turn(car, 60, throttle).travelAt90 <= 30).toBe(true)
			end
		end
	end)

	it("keeps going where it points: the heading holds within 4° for 2 s after release", function()
		for _, car in CARS do
			for _, kmh in { 60, 80, 120 } do
				local run = DriftTurn.turn(car, kmh, 0)
				expect(run.headingDrift <= math.rad(4)).toBe(true)
				expect(math.abs(run.slipAfter) <= math.rad(2)).toBe(true)
			end
		end
	end)

	it("turns the same within 3 m and holds within 4° at 30, 60 and 120 FPS", function()
		for _, car in CARS do
			local reference = DriftTurn.turn(car, 80, 0, 60)
			for _, fps in { 30, 120 } do
				local run = DriftTurn.turn(car, 80, 0, fps)
				expect(math.abs(run.travelAt90 - reference.travelAt90) <= 3).toBe(true)
				expect(run.headingDrift <= math.rad(4)).toBe(true)
			end
		end
	end)

	it("adds at least 10° to a steered corner with a 0.3 s tap of Space", function()
		for _, car in CARS do
			local tapped, plain = DriftTurn.tap(car, 80)
			expect(tapped - plain >= math.rad(10)).toBe(true)
		end
	end)

	it("ends under braking or below the speed gate without swinging back or spinning", function()
		for _, car in CARS do
			for _, braking in { false, true } do
				local ending = DriftTurn.ending(car, 50, braking)
				expect(ending.endedAt < math.huge).toBe(true)
				expect(ending.headingBack <= math.rad(2)).toBe(true)
				expect(ending.spun).toBe(false)
			end
		end
	end)

	it("pulls at the centre of mass, so even a hard drift barely rolls the car", function()
		for _, car in CARS do
			local sim = DriveSim.new(car, InputHelp.keyboard)
			DriveSim.setSpeed(sim, 80 * KMH, DriftTurn.gearFor(car, 80))
			local roll = 0
			while sim.time < 2.5 do
				local held = sim.time >= 1
				DriveSim.frame(
					sim,
					DriveSim.input({
						steer = if held then 1 else 0,
						drift = held,
						handbrake = if held then 1 else 0,
						drivingMode = car.modeOrder[1],
						gearboxMode = "manual",
					}),
					DT
				)
				roll = math.max(roll, math.abs(sim.body.roll))
			end
			expect(roll < math.rad(3)).toBe(true)
		end
	end)

	it("carries a held drift through an S-bend: right, then left", function()
		for _, car in CARS do
			local sim = DriveSim.new(car, InputHelp.keyboard)
			DriveSim.setSpeed(sim, 80 * KMH, DriftTurn.gearFor(car, 80))
			local right, left = 0, 0
			while sim.time < 3 do
				DriveSim.frame(
					sim,
					DriveSim.input({
						throttle = 1,
						steer = if sim.time < 1.5 then 1 else -1,
						drift = true,
						handbrake = 1,
						drivingMode = car.modeOrder[1],
						gearboxMode = "manual",
					}),
					DT
				)
				local forward, side = DriveSim.localVelocity(sim.body)
				local slip = math.atan2(side, math.abs(forward))
				right, left = math.min(right, slip), math.max(left, slip)
			end
			expect(right < -math.rad(15)).toBe(true)
			expect(left > math.rad(15)).toBe(true)
		end
	end)
end)

describe("Drift button and handbrake", function()
	-- Final speed, heading and rear slip after 1 s of `options` from `kmh` in 3rd.
	local function after(
		car: Types.CarConfig,
		kmh: number,
		options: DriveSim.InputOptions
	): (number, number, number)
		local sim = DriveSim.new(car)
		DriveSim.setSpeed(sim, kmh * KMH, 3)
		options.drivingMode = car.modeOrder[1]
		local result
		while sim.time < 1 do
			result = DriveSim.frame(sim, DriveSim.input(options), DT)
		end
		return DriveSim.forwardSpeed(sim), sim.body.heading, result.wheels[3].slipRatio
	end

	it("is the plain handbrake below 30 km/h and with the wheel straight", function()
		for _, car in CARS do
			for _, case in { { kmh = 25, steer = 1 }, { kmh = 80, steer = 0 } } do
				local speed, heading = after(car, case.kmh, { handbrake = 1, steer = case.steer })
				local driftSpeed, driftHeading =
					after(car, case.kmh, { handbrake = 1, steer = case.steer, drift = true })
				expect(driftSpeed).toBe(speed)
				expect(driftHeading).toBe(heading)
			end
		end
	end)

	it("releases the handbrake once a drift engages, so the rear never locks", function()
		for _, car in CARS do
			local _, _, locked = after(car, 80, { handbrake = 1, steer = 1 })
			local _, _, drifting = after(car, 80, { handbrake = 1, steer = 1, drift = true })
			expect(locked < -0.9).toBe(true)
			expect(drifting > -0.5).toBe(true)
		end
	end)
end)
