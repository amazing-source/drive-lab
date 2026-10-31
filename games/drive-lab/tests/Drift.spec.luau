--!strict
--[[
	The shared drift (Vehicle/Drift), unit by unit, then through the vehicle model on both cars with
	tools/DriftScenario. The bounds are docs/research/13_drifting.md §5.12's.
]]
local Config = require("../src/shared/Config/Drift")
local DR458 = require("../src/shared/Config/Cars/DR458/Physics")
local Drift = require("../src/shared/Vehicle/Drift")
local DriftScenario = require("../tools/DriftScenario")
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

-- A state stepped `frames` frames at `kmh` with the button and steering given.
local function stepped(frames: number, held: boolean, steer: number, kmh: number): Drift.DriftState
	local state = Drift.newState()
	for _ = 1, frames do
		Drift.update(profileOf(DR458), state, held, steer, kmh * KMH, 0, DT)
	end
	return state
end

describe("Drift gate and engagement", function()
	it("engages only with the button held, above 30 km/h, and steered past the gate", function()
		expect(stepped(5, true, 1, 80).wants).toBe(true)
		expect(stepped(5, false, 1, 80).wants).toBe(false)
		expect(stepped(5, true, 1, 29).wants).toBe(false)
		expect(stepped(5, true, 0.2, 80).wants).toBe(false)
		expect(stepped(5, true, -0.3, 80).direction).toBe(-1)
	end)

	it("rises to full in 0.25 s and falls to nothing in 0.5 s", function()
		local frames = math.round(Config.RISE_TIME / DT)
		expect(stepped(frames - 1, true, 1, 80).engagement < 1).toBe(true)
		local state = stepped(frames, true, 1, 80)
		expect(state.engagement).toBeNear(1, 1e-9)
		for _ = 1, math.round(Config.FALL_TIME / DT) - 1 do
			Drift.update(profileOf(DR458), state, false, 0, 80 * KMH, 0, DT)
		end
		expect(state.engagement > 0).toBe(true)
		Drift.update(profileOf(DR458), state, false, 0, 80 * KMH, 0, DT)
		expect(state.engagement).toBeNear(0, 1e-9)
	end)

	it("aims at 15° centred, the car's maximum at full lock, and nothing the other way", function()
		local profile = profileOf(DR458)
		local state = stepped(1, true, 1, 80)
		expect(Drift.target(profile, state, 0)).toBeNear(math.rad(15), 1e-12)
		expect(Drift.target(profile, state, 1)).toBeNear(profile.maxAngle, 1e-12)
		expect(Drift.target(profile, state, -0.5)).toBe(0)
		state.wants = false
		expect(Drift.target(profile, state, 1)).toBe(0)
	end)
end)

describe("Drift shares and assists", function()
	it(
		"leaves grip, torque, TC, the coupling and the steering exactly as they are while not engaged",
		function()
			local profile = profileOf(SVJ)
			local state = Drift.newState()
			local grip, torque = Drift.shares(profile, state, 20, -5, 0.001)
			expect(grip).toBe(1)
			expect(torque).toBe(1)
			expect(Drift.tcSlip(profile, state, 0.08)).toBe(0.08)
			expect(Drift.couplingCapacity(profile, state, 1234.5, 3000)).toBe(1234.5)
			expect(Drift.steer(SVJ, state, 0.37, 20, -5, 0.4)).toBe(0.37)
		end
	)

	it(
		"holds the rear at its hold share on target, frees it past the target, and fades the torque",
		function()
			local profile = profileOf(DR458)
			local state = stepped(30, true, 1, 80)
			local onTarget = math.tan(state.target) * 20
			state.substepSlip = state.target
			local grip, torque = Drift.shares(profile, state, 20, onTarget, 0.001)
			expect(grip).toBeNear(profile.holdShare, 1e-6)
			expect(torque).toBe(1)
			local far = math.tan(state.target + math.rad(15)) * 20
			state.substepSlip = state.target + math.rad(15)
			grip, torque = Drift.shares(profile, state, 20, far, 0.001)
			expect(grip).toBe(1)
			expect(torque).toBe(0)
			state.substepSlip = 0
			grip = Drift.shares(profile, state, 20, 0, 0.001)
			expect(grip).toBeNear(Config.FLOOR_SHARE, 1e-9)
		end
	)

	it("relaxes TC to the profile's slip and caps the coupling at its front share while engaged", function()
		local profile = profileOf(SVJ)
		local state = stepped(30, true, 1, 80)
		expect(Drift.tcSlip(profile, state, 0.08)).toBeNear(profile.tcSlip, 1e-12)
		expect(Drift.couplingCapacity(profile, state, 1200, 3000)).toBeNear(profile.frontShare * 3000, 1e-9)
	end)

	it("countersteers harder the further a right-hand drift is past its target", function()
		local state = stepped(30, true, 1, 80)
		state.frameSlip, state.frameRate = state.target, 0
		local onTarget = Drift.steer(SVJ, state, 1, 20, -math.tan(state.target) * 20, 0.6)
		state.frameSlip = state.target + math.rad(10)
		local over = Drift.steer(SVJ, state, 1, 20, -math.tan(state.frameSlip) * 20, 0.6)
		expect(over < onTarget).toBe(true)
	end)
end)

describe("Drift through the model", function()
	it("holds every drift near its target without a spin at 50, 80 and 130 km/h", function()
		for _, car in CARS do
			local maxAngle = profileOf(car).maxAngle
			for _, kmh in { 50, 80, 130 } do
				for _, steer in { 0.4, 1 } do
					for _, throttle in { 0.3, 1 } do
						local run = DriftScenario.run(car, { kmh = kmh, steer = steer, throttle = throttle })
						expect(run.entry < 1).toBe(true)
						expect(run.peak <= maxAngle + math.rad(8)).toBe(true)
						expect(math.abs(run.held - run.target) <= math.rad(4)).toBe(true)
						expect(run.snap <= math.rad(3)).toBe(true)
						expect(run.settle <= 1.5).toBe(true)
					end
				end
			end
		end
	end)

	it("drifts the same at 30, 60 and 120 FPS, with TC on and off", function()
		for _, car in CARS do
			for _, tc in { true, false } do
				local reference =
					DriftScenario.run(car, { kmh = 80, steer = 1, throttle = 1, tc = tc, fps = 120 })
				for _, fps in { 30, 60 } do
					local run =
						DriftScenario.run(car, { kmh = 80, steer = 1, throttle = 1, tc = tc, fps = fps })
					expect(math.abs(run.held - reference.held) <= math.rad(1.5)).toBe(true)
					expect(run.peak <= profileOf(car).maxAngle + math.rad(8)).toBe(true)
					expect(run.snap <= math.rad(3)).toBe(true)
				end
			end
		end
	end)

	it("exits the DR458's slow, light-throttle drift without sliding back the other way", function()
		for _, fps in { 30, 60, 120 } do
			local run = DriftScenario.run(DR458, { kmh = 50, steer = 1, throttle = 0.3, fps = fps })
			expect(run.snap <= math.rad(3)).toBe(true)
		end
	end)

	it("costs at most 12 km/h a second on a light throttle and at most 1 on full", function()
		for _, car in CARS do
			for _, kmh in { 50, 80, 130 } do
				expect(DriftScenario.run(car, { kmh = kmh, steer = 1, throttle = 0.3 }).lossPerSecond <= 12).toBe(
					true
				)
				expect(DriftScenario.run(car, { kmh = kmh, steer = 1, throttle = 1 }).lossPerSecond <= 1).toBe(
					true
				)
			end
		end
	end)

	it("keeps TC on, relaxed: the rear spins past the mode's slip but well under TC off", function()
		for _, car in CARS do
			local modeSlip = car.modes[car.modeOrder[1]].tcSlipRatio
			local on = DriftScenario.run(car, { kmh = 80, steer = 1, throttle = 1 })
			local off = DriftScenario.run(car, { kmh = 80, steer = 1, throttle = 1, tc = false })
			expect(on.rearSlipRatio > modeSlip + 0.1).toBe(true)
			expect(on.rearSlipRatio < profileOf(car).tcSlip + 0.05).toBe(true)
			expect(off.rearSlipRatio > on.rearSlipRatio + 0.05).toBe(true)
		end
	end)

	it(
		"sets ESC aside and caps the SVJ's front share at 10 % while drifting, then gives both back",
		function()
			local run = DriftScenario.run(SVJ, { kmh = 80, steer = 1, throttle = 1 })
			expect(run.escShare).toBe(0)
			expect(math.abs(run.frontShare) <= profileOf(SVJ).frontShare + 0.01).toBe(true)
			expect(run.frontShareAfter > 0.3).toBe(true)
		end
	)

	it("holds its gear through a drift in the automatic, as a driver would", function()
		for _, car in CARS do
			for _, kmh in { 50, 80, 130 } do
				local run =
					DriftScenario.run(car, { kmh = kmh, steer = 1, throttle = 1, gearboxMode = "auto" })
				expect(run.shifts).toBe(0)
				expect(run.peak <= profileOf(car).maxAngle + math.rad(8)).toBe(true)
			end
		end
	end)

	it("drifts the same way to the left, and on a keyboard", function()
		for _, car in CARS do
			local right = DriftScenario.run(car, { kmh = 80, steer = 1, throttle = 1 })
			local left = DriftScenario.run(car, { kmh = 80, steer = 1, throttle = 1, side = -1 })
			expect(left.held).toBeNear(right.held, math.rad(0.5))
			local keys =
				DriftScenario.run(car, { kmh = 80, steer = 1, throttle = 1, help = InputHelp.keyboard })
			expect(math.abs(keys.held - keys.target) <= math.rad(4)).toBe(true)
			expect(keys.peak <= profileOf(car).maxAngle + math.rad(8)).toBe(true)
		end
	end)
end)

describe("Drift button and handbrake", function()
	-- Final speed, heading and rear slip after `seconds` of `options` from `kmh` in 3rd.
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
