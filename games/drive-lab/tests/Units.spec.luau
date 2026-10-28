--!strict
local T = require("../../../tools/test/T")
local Units = require("../src/shared/Units")
local World = require("../src/shared/Config/World")

local describe, it, expect = T.describe, T.it, T.expect

describe("Units", function()
	it("makes a stud Roblox's 0.28 m divided by the world scale", function()
		expect(Units.METRES_PER_STUD).toBeNear(0.28 / Units.WORLD_SCALE, 1e-12)
		expect(Units.studsToMetres(Units.metresToStuds(1))).toBeNear(1, 1e-12)
	end)

	it("derives force and torque units from the stud and Roblox's mass unit", function()
		-- 1 mass unit * 1 stud/s^2 = 21.952 kg * (metres per stud) m/s^2.
		expect(Units.forceToNewtons(1)).toBeNear(21.952 * Units.METRES_PER_STUD, 1e-9)
		expect(Units.torqueToNewtonMetres(1)).toBeNear(21.952 * Units.METRES_PER_STUD ^ 2, 1e-9)
		expect(Units.newtonsToForce(Units.forceToNewtons(123.4))).toBeNear(123.4, 1e-9)
	end)
end)

describe("World", function()
	it("sets gravity to 9.81 m/s^2 expressed in studs", function()
		expect(Units.studsToMetres(World.GRAVITY)).toBeNear(9.81, 1e-9)
	end)
end)
