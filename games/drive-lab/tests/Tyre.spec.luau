--!strict
local T = require("../../../tools/test/T")
local SVJ = require("../src/shared/Config/Cars/SVJ/Physics")
local Tyre = require("../src/shared/Vehicle/Tyre")

local describe, it, expect = T.describe, T.it, T.expect

local config = SVJ.front.tyre
local tyre = Tyre.prepare(config, 400)
local LOAD = config.referenceLoad

-- Largest pure-slip force along a fine sweep, and the slip it occurs at.
local function peakOf(slipAt: (number) -> number, limit: number): (number, number)
	local best, bestSlip = 0, 0
	for step = 1, 4000 do
		local slip = limit * step / 4000
		local force = slipAt(slip)
		if force > best then
			best, bestSlip = force, slip
		end
	end
	return best, bestSlip
end

describe("Tyre pure slip", function()
	it("peaks at the configured slip ratio with peakMuX times the load", function()
		local peak, slip = peakOf(function(s)
			return (Tyre.combined(tyre, s, 0, LOAD, 1))
		end, 0.5)
		expect(slip).toBeNear(config.slipRatioAtPeak, 0.001)
		expect(peak).toBeNear(config.peakMuX * LOAD, 1)
	end)

	it("peaks at the configured slip angle with peakMuY times the load", function()
		local peak, slip = peakOf(function(a)
			local _, fy = Tyre.combined(tyre, 0, a, LOAD, 1)
			return -fy
		end, 0.6)
		expect(slip).toBeNear(config.slipAngleAtPeak, 0.001)
		expect(peak).toBeNear(config.peakMuY * LOAD, 1)
	end)

	it("falls toward the sliding share of the peak at large slip", function()
		local far = Tyre.shape(tyre.x, 1000 * config.slipRatioAtPeak)
		expect(far).toBeNear(config.slidingRatioX, 0.01)
		local locked = Tyre.combined(tyre, -1, 0, LOAD, 1)
		expect(-locked < config.peakMuX * LOAD).toBeTruthy()
		expect(-locked > config.slidingRatioX * config.peakMuX * LOAD).toBeTruthy()
	end)

	it("grows peak force as load^loadSensitivity, so friction falls with load", function()
		local single = Tyre.peakForces(tyre, LOAD, 1)
		local double = Tyre.peakForces(tyre, 2 * LOAD, 1)
		expect(double / single).toBeNear(2 ^ config.loadSensitivity, 1e-9)
	end)

	it("scales every force with surface grip", function()
		local dry = Tyre.combined(tyre, 0.05, 0.02, LOAD, 1)
		local wet = Tyre.combined(tyre, 0.05, 0.02, LOAD, 0.6)
		expect(wet / dry).toBeNear(0.6, 1e-9)
	end)
end)

describe("Tyre combined slip", function()
	it("reproduces each pure-slip curve when the other slip is zero", function()
		for _, slip in { 0.02, 0.1, 0.3 } do
			local fx = Tyre.combined(tyre, slip, 0, LOAD, 1)
			expect(fx).toBeNear(config.peakMuX * LOAD * Tyre.shape(tyre.x, slip), 1e-6)
		end
	end)

	it("stays inside the friction ellipse", function()
		local peakX, peakY = Tyre.peakForces(tyre, LOAD, 1)
		for i = -10, 10 do
			for j = -10, 10 do
				local fx, fy = Tyre.combined(tyre, i * 0.05, j * 0.04, LOAD, 1)
				expect((fx / peakX) ^ 2 + (fy / peakY) ^ 2 <= 1 + 1e-9).toBeTruthy()
			end
		end
	end)

	it("gives up longitudinal force as lateral slip rises", function()
		local alone = Tyre.combined(tyre, 0.1, 0, LOAD, 1)
		local cornering = Tyre.combined(tyre, 0.1, 0.1, LOAD, 1)
		expect(cornering < 0.8 * alone).toBeTruthy()
	end)

	it("reports dFx/dκ as the local slope in the linear region and never below zero", function()
		for _, angle in { 0, 0.05 } do
			local h = 1e-6
			local before = Tyre.combined(tyre, 0.03 - h, angle, LOAD, 1)
			local after = Tyre.combined(tyre, 0.03 + h, angle, LOAD, 1)
			local _, _, slope = Tyre.combined(tyre, 0.03, angle, LOAD, 1)
			expect(slope).toBeNear((after - before) / (2 * h), 0.001 * slope)
		end
		local _, _, past = Tyre.combined(tyre, 0.5, 0, LOAD, 1)
		expect(past).toBe(0)
	end)
end)

describe("Tyre relaxation", function()
	it("is exact: one long step equals many short ones", function()
		local long = Tyre.relax(0.01, 0.4, 20, 0.3, 0.02)
		local short = 0.01
		for _ = 1, 20 do
			short = Tyre.relax(short, 0.4, 20, 0.3, 0.001)
		end
		expect(long).toBeNear(short, 1e-12)
	end)

	it("reaches 63 % of the steady deflection after rolling one relaxation length", function()
		local speed, length, slip = 20, 0.3, 0.4
		local deflection = Tyre.relax(0, slip, speed, length, length / speed)
		expect(deflection / (length * slip / speed)).toBeNear(1 - math.exp(-1), 1e-9)
	end)

	it("integrates the slip velocity at a standstill", function()
		expect((Tyre.relax(0.002, 0.1, 0, 0.3, 0.01))).toBeNear(0.003, 1e-12)
	end)
end)

describe("Tyre at walking pace", function()
	local simulation = SVJ.simulation

	it("produces no force when a parked wheel is not slipping", function()
		local state = Tyre.newState()
		Tyre.setLoad(tyre, state, LOAD, 1)
		for _ = 1, 1000 do
			Tyre.prepareSubstep(tyre, state, 0, 0, 0, simulation, 0.001)
			Tyre.finishSubstep(tyre, state, 0, 0, simulation, 0.001)
		end
		expect(state.forceX).toBe(0)
		expect(state.forceY).toBe(0)
	end)

	it("resists a slow sideways push with a force bounded by friction, and stays finite", function()
		local state = Tyre.newState()
		Tyre.setLoad(tyre, state, LOAD, 1)
		local _, peakY = Tyre.peakForces(tyre, LOAD, 1)
		for _ = 1, 2000 do
			Tyre.prepareSubstep(tyre, state, 0, 0.05, 0, simulation, 0.001)
		end
		expect(state.forceY < 0).toBeTruthy()
		expect(-state.forceY <= peakY + 1e-9).toBeTruthy()
		expect(state.forceY == state.forceY).toBeTruthy()
	end)

	it("lets a stopped, sliding patch store no more than the peak deflection", function()
		local state = Tyre.newState()
		Tyre.setLoad(tyre, state, LOAD, 1)
		for _ = 1, 5000 do
			Tyre.prepareSubstep(tyre, state, 0, 0.2, 0, simulation, 0.001)
		end
		expect(state.deflectionY <= tyre.relaxationY * 0.2 / simulation.slipSpeedFloor + 1e-12).toBeTruthy()
	end)

	it("carries nothing in the air and forgets its deflection", function()
		local state = Tyre.newState()
		state.deflectionX, state.deflectionY = 0.01, 0.01
		Tyre.setLoad(tyre, state, 0, 1)
		Tyre.prepareSubstep(tyre, state, 10, 1, 40, simulation, 0.001)
		expect(state.forceX).toBe(0)
		expect(state.deflectionY).toBe(0)
	end)

	it("resists rolling with a torque that grows with load and speed", function()
		local slow = Tyre.rollingResistanceTorque(tyre, LOAD, 0)
		expect(slow).toBeNear(LOAD * config.rollingResistance * config.radius, 1e-9)
		expect(Tyre.rollingResistanceTorque(tyre, LOAD, 50) > slow).toBeTruthy()
	end)
end)
