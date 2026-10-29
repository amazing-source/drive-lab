--!strict
local T = require("../../../tools/test/T")
local Electronics = require("../src/shared/Vehicle/Electronics")
local Geometry = require("../src/shared/Vehicle/Geometry")
local SVJ = require("../src/shared/Config/Cars/SVJ")
local World = require("../src/shared/Config/World")

local describe, it, expect = T.describe, T.it, T.expect

local config = SVJ.electronics
local STEP = 0.001

local function uniform(value: number): { number }
	return { value, value, value, value }
end

describe("ABS", function()
	it("releases a wheel braking past the release slip, then reapplies once it recovers", function()
		local state = Electronics.newState()
		local ground = uniform(20)
		local locked = { 20 * (1 - 0.3), 20, 20, 20 }
		for _ = 1, 20 do
			Electronics.updateAbs(config, state, true, true, locked, ground, STEP)
		end
		expect(state.absFactor[1] < 1).toBeTruthy()
		expect(state.absFactor[2]).toBe(1)
		expect(state.absActive).toBe(true)
		local released = state.absFactor[1]
		for _ = 1, 20 do
			Electronics.updateAbs(config, state, true, true, uniform(20), ground, STEP)
		end
		expect(state.absFactor[1] > released).toBeTruthy()
	end)

	it("holds pressure between the reapply and release slips", function()
		local state = Electronics.newState()
		local between = -(config.absReapplySlip + config.absReleaseSlip) / 2
		for _ = 1, 100 do
			Electronics.updateAbs(config, state, true, true, uniform(20 * (1 + between)), uniform(20), STEP)
		end
		expect(state.absFactor[1]).toBe(1)
	end)

	it("does nothing when off, when not braking, or below its minimum speed", function()
		type Case = { enabled: boolean, braking: boolean, speed: number }
		local cases: { Case } = {
			{ enabled = false, braking = true, speed = 20 },
			{ enabled = true, braking = false, speed = 20 },
			{ enabled = true, braking = true, speed = config.absMinSpeed * 0.5 },
		}
		for _, case in cases do
			local state = Electronics.newState()
			for _ = 1, 50 do
				Electronics.updateAbs(
					config,
					state,
					case.enabled,
					case.braking,
					uniform(0),
					uniform(case.speed),
					STEP
				)
			end
			expect(state.absFactor[1]).toBe(1)
		end
	end)
end)

describe("Traction control", function()
	local function slipFor(state: Electronics.ElectronicsState, mode: string, slip: number, steps: number)
		for _ = 1, steps do
			Electronics.updateTc(
				config,
				(SVJ.modes :: any)[mode].tcSlipRatio,
				state,
				true,
				1,
				uniform(20 * (1 + slip)),
				uniform(20),
				STEP
			)
		end
	end

	it("trims torque in proportion to slip past the mode's threshold", function()
		local state = Electronics.newState()
		local threshold = SVJ.modes.Corsa.tcSlipRatio
		slipFor(state, "Corsa", threshold + 0.02, 10)
		expect(state.tcFactor).toBeNear(1 - config.tcGain * 0.02, 1e-9)
		expect(state.tcActive).toBe(true)
	end)

	it("cuts outright past the cut factor, and recovers once slip is back", function()
		local state = Electronics.newState()
		slipFor(state, "Corsa", SVJ.modes.Corsa.tcSlipRatio * config.tcCutFactor * 1.1, 10)
		expect(state.tcFactor).toBe(0)
		slipFor(state, "Corsa", 0, math.ceil(config.tcRecoveryTime / STEP) + 20)
		expect(state.tcFactor).toBe(1)
	end)

	it("lets Corsa keep a slip that Strada trims", function()
		local slip = (SVJ.modes.Strada.tcSlipRatio + SVJ.modes.Corsa.tcSlipRatio) / 2
		local strada, corsa = Electronics.newState(), Electronics.newState()
		slipFor(strada, "Strada", slip, 20)
		slipFor(corsa, "Corsa", slip, 20)
		expect(strada.tcFactor < 1).toBeTruthy()
		expect(corsa.tcFactor).toBe(1)
	end)

	it("floors the speed so a stopped car may spin its wheels a little", function()
		local state = Electronics.newState()
		local allowed = SVJ.modes.Corsa.tcSlipRatio * config.tcSpeedFloor * 0.9
		for _ = 1, 20 do
			Electronics.updateTc(
				config,
				SVJ.modes.Corsa.tcSlipRatio,
				state,
				true,
				1,
				uniform(allowed),
				uniform(0),
				STEP
			)
		end
		expect(state.tcFactor).toBe(1)
	end)
end)

describe("Stability control", function()
	local function motion(yawRate: number, rightSpeed: number, steer: number): Electronics.Motion
		return {
			forwardSpeed = 25,
			rightSpeed = rightSpeed,
			yawRate = yawRate,
			frontSteer = steer,
			rearSteer = 0,
			grip = 1,
		}
	end

	local function decide(
		mode: string,
		m: Electronics.Motion,
		enabled: boolean?
	): Electronics.ElectronicsState
		local state = Electronics.newState()
		Electronics.updateEsc(SVJ, (SVJ.modes :: any)[mode], state, enabled ~= false, m, 1 / config.escRate)
		return state
	end

	it("caps its reference at what the tyres can hold, μ·g / v", function()
		local reference = Electronics.referenceYawRate(SVJ, motion(0, 0, 0.3))
		expect(reference).toBeNear(SVJ.front.tyre.peakMuY * World.GRAVITY_MPS2 / 25, 1e-9)
	end)

	it("brakes the outer front wheel and trims torque when a right turn oversteers", function()
		local steer = 0.02
		local reference = Electronics.referenceYawRate(SVJ, motion(0, 0, steer))
		local state = decide("Strada", motion(reference + 0.3, -2, steer))
		expect(state.escBrake[Geometry.FRONT_LEFT] > 0).toBeTruthy()
		expect(state.escBrake[Geometry.FRONT_RIGHT]).toBe(0)
		expect(state.escFactor < 1).toBeTruthy()
		expect(state.escActive).toBe(true)
	end)

	it("brakes the inner rear wheel when a right turn understeers", function()
		local steer = 0.03
		local reference = Electronics.referenceYawRate(SVJ, motion(0, 0, steer))
		local state = decide("Strada", motion(reference * 0.4, 0, steer))
		expect(state.escBrake[Geometry.REAR_RIGHT] > 0).toBeTruthy()
		expect(state.escBrake[Geometry.REAR_LEFT]).toBe(0)
	end)

	it("lets Corsa carry a yaw excess and a slide that Strada corrects", function()
		local steer = 0.02
		local reference = Electronics.referenceYawRate(SVJ, motion(0, 0, steer))
		local sliding = motion(reference + 0.12, -25 * math.tan(math.rad(6)), steer)
		expect(decide("Strada", sliding).escActive).toBe(true)
		expect(decide("Corsa", sliding).escActive).toBe(false)
	end)

	it("does nothing when switched off", function()
		local state = decide("Strada", motion(1.5, -8, 0.02), false)
		expect(state.escActive).toBe(false)
		expect(state.escFactor).toBe(1)
	end)
end)
