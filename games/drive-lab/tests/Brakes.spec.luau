--!strict
local T = require("../../../tools/test/T")
local Brakes = require("../src/shared/Vehicle/Brakes")
local SVJ = require("../src/shared/Config/Cars/SVJ/Physics")

local describe, it, expect = T.describe, T.it, T.expect

local brakes = Brakes.prepare(SVJ.brakes)
local config = SVJ.brakes

describe("Brakes", function()
	it("splits the full-pedal torque by the front share across the four wheels", function()
		local front = Brakes.torque(brakes, 1, 1, 0, 1, 0)
		local rear = Brakes.torque(brakes, 3, 1, 0, 1, 0)
		expect(front).toBeNear(config.maxTorque * config.frontShare / 2, 1e-9)
		expect(2 * front / (2 * front + 2 * rear)).toBeNear(config.frontShare, 1e-12)
	end)

	it("puts the handbrake on the rear wheels only, outside the ABS", function()
		expect(Brakes.torque(brakes, 1, 0, 1, 1, 0)).toBe(0)
		expect(Brakes.torque(brakes, 4, 0, 1, 0, 0)).toBe(config.handbrakeTorque)
	end)

	it("lets ABS scale the pedal and stability torque together", function()
		local full = Brakes.torque(brakes, 2, 0.5, 0, 1, 300)
		expect(Brakes.torque(brakes, 2, 0.5, 0, 0.4, 300)).toBeNear(0.4 * full, 1e-9)
	end)
end)
