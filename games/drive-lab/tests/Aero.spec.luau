--!strict
local T = require("../../../tools/test/T")
local Aero = require("../src/shared/Vehicle/Aero")
local SVJ = require("../src/shared/Config/Cars/SVJ/Physics")
local World = require("../src/shared/Config/World")

local describe, it, expect = T.describe, T.it, T.expect

local config = SVJ.aero

local function closedAt(speed: number): Aero.AeroForces
	local forces = { drag = 0, downforceFront = 0, downforceRear = 0 }
	Aero.update(config, Aero.newState(), speed, 0, 0.01, forces)
	return forces
end

describe("Aero", function()
	it("drags with ½·ρ·CdA·v²", function()
		local forces = closedAt(50)
		expect(forces.drag).toBeNear(0.5 * config.airDensity * config.dragArea * 2500, 1e-9)
	end)

	it("makes about 350 kg of downforce at 300 km/h with the flaps closed (02 A8)", function()
		local forces = closedAt(300 / 3.6)
		local kilograms = (forces.downforceFront + forces.downforceRear) / World.GRAVITY_MPS2
		expect(kilograms).toBeNear(350, 10)
		expect(forces.downforceFront / (forces.downforceFront + forces.downforceRear)).toBeNear(
			config.frontBalance,
			1e-12
		)
	end)

	it("opens ALA only flat out, straight and fast enough", function()
		local fast = config.alaMinSpeed + 5
		expect(Aero.alaTarget(config, fast, 1, 0, 0)).toBe(1)
		expect(Aero.alaTarget(config, config.alaMinSpeed - 1, 1, 0, 0)).toBe(0)
		expect(Aero.alaTarget(config, fast, 0.5, 0, 0)).toBe(0)
		expect(Aero.alaTarget(config, fast, 1, 0.2, 0)).toBe(0)
		expect(Aero.alaTarget(config, fast, 1, 0, 5)).toBe(0)
	end)

	it("moves the flaps within 500 ms (02 A2), the same at any frame rate", function()
		local coarse, fine = Aero.newState(), Aero.newState()
		local forces = { drag = 0, downforceFront = 0, downforceRear = 0 }
		for _ = 1, 15 do
			Aero.update(config, coarse, 60, 1, 1 / 30, forces)
		end
		for _ = 1, 120 do
			Aero.update(config, fine, 60, 1, 1 / 240, forces)
		end
		expect(coarse.alaOpen > 0.95).toBeTruthy()
		expect(coarse.alaOpen).toBeNear(fine.alaOpen, 1e-9)
	end)

	it("cuts drag and rear downforce when open, leaving the front", function()
		local state = Aero.newState()
		state.alaOpen = 1
		local open = { drag = 0, downforceFront = 0, downforceRear = 0 }
		Aero.update(config, state, 80, 1, 0, open)
		local closed = closedAt(80)
		expect(open.drag / closed.drag).toBeNear(config.alaDragFactor, 1e-9)
		expect(open.downforceRear / closed.downforceRear).toBeNear(config.alaRearLiftFactor, 1e-9)
		expect(open.downforceFront).toBeNear(closed.downforceFront, 1e-9)
	end)
end)
