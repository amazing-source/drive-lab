--!strict
local CarWater = require("../src/shared/Rules/CarWater")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local SPRAY: CarWater.Spray = { minSpeed = 20, fullSpeed = 140, wetFrom = 0.15, rate = 40 }
local SPLASHES: CarWater.Splashes = { perArea = 30, exponent = 1.15, maxRate = 100 }

describe("CarWater", function()
	it("throws no spray standing, slow, or on a dry road", function()
		expect(CarWater.spray(0, 1, SPRAY)).toBe(0)
		expect(CarWater.spray(19, 1, SPRAY)).toBe(0)
		expect(CarWater.spray(200, 0, SPRAY)).toBe(0)
		expect(CarWater.spray(200, 0.1, SPRAY)).toBe(0)
	end)

	it("grows spray with speed and wetness, to its rate at full speed on a soaked road", function()
		local previous = -1
		for speed = 0, 300, 5 do
			local rate = CarWater.spray(speed, 0.8, SPRAY)
			expect(rate >= previous).toBe(true)
			previous = rate
		end
		expect(CarWater.spray(140, 1, SPRAY)).toBeNear(40, 1e-9)
		expect(CarWater.spray(300, 1, SPRAY)).toBeNear(40, 1e-9)
		expect(CarWater.spray(80, 1, SPRAY)).toBeNear(20, 1e-9)
		expect(CarWater.spray(140, 0.575, SPRAY)).toBeNear(20, 1e-9)
		-- Reversing throws spray as driving forward does.
		expect(CarWater.spray(-80, 1, SPRAY)).toBeNear(CarWater.spray(80, 1, SPRAY), 1e-12)
	end)

	it("splashes the bodywork with the rain, none under a roof, never past the cap", function()
		expect(CarWater.splashes(0, 1, 2, SPLASHES)).toBe(0)
		expect(CarWater.splashes(1, 0, 2, SPLASHES)).toBe(0)
		expect(CarWater.splashes(1, 1, 2, SPLASHES)).toBeNear(60, 1e-9)
		expect(CarWater.splashes(1, 1, 50, SPLASHES)).toBe(100)
		expect(CarWater.splashes(0.5, 0.5, 2, SPLASHES)).toBeNear(30 * 2 * 0.5 ^ 1.15 * 0.5, 1e-9)
	end)

	it("reads nonsense as no water, never as an error", function()
		for _, odd in { 0 / 0, -math.huge } do
			expect(CarWater.spray(odd, 1, SPRAY)).toBe(0)
			expect(CarWater.spray(100, odd, SPRAY)).toBe(0)
			expect(CarWater.splashes(odd, 1, 2, SPLASHES)).toBe(0)
			expect(CarWater.splashes(1, 1, odd, SPLASHES)).toBe(0)
		end
		expect(CarWater.splashes(1, 1, math.huge, SPLASHES)).toBe(100)
		expect(CarWater.spray(math.huge, 1, SPRAY)).toBe(0)
	end)
end)
