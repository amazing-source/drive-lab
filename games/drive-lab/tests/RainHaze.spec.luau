--!strict
local RainHaze = require("../src/shared/Rules/RainHaze")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local TUNING: RainHaze.Tuning = {
	fullRate = 50,
	extinction50 = 3,
	exponent = 0.67,
	takeOver = 0.3,
	calibration = {
		{ density = 0.15, extinction = 0.3 },
		{ density = 0.22, extinction = 1.2 },
		{ density = 0.3, extinction = 4.2 },
		{ density = 0.45, extinction = 18 },
	},
}

describe("RainHaze", function()
	it("halves contrast in about 230 m in 50 mm/h rain", function()
		local extinction = RainHaze.extinction(RainHaze.rainRate(1, TUNING), TUNING)
		expect(extinction).toBeNear(3, 1e-12)
		expect(RainHaze.halfContrast(extinction)).toBeNear(231, 1)
	end)

	it("sees further in lighter rain, and without limit in none", function()
		local previous = -1
		for step = 0, 20 do
			local extinction = RainHaze.extinction(RainHaze.rainRate(step / 20, TUNING), TUNING)
			expect(extinction >= previous).toBe(true)
			previous = extinction
		end
		expect(RainHaze.halfContrast(0)).toBe(math.huge)
		expect(RainHaze.extinction(0 / 0, TUNING)).toBe(0)
	end)

	it("reads measured densities back exactly and holds the table's ends", function()
		for _, point in TUNING.calibration do
			expect(RainHaze.densityFor(point.extinction, TUNING.calibration)).toBeNear(point.density, 1e-12)
		end
		expect(RainHaze.densityFor(0, TUNING.calibration)).toBe(0.15)
		expect(RainHaze.densityFor(1000, TUNING.calibration)).toBe(0.45)
		expect(RainHaze.densityFor(0 / 0, TUNING.calibration)).toBe(0.15)
		local between = RainHaze.densityFor(3, TUNING.calibration)
		expect(between > 0.22 and between < 0.3).toBe(true)
	end)

	it("keeps the preset's density when dry and takes the rain's once it pours", function()
		expect(RainHaze.density(0.42, 0, TUNING)).toBe(0.42)
		local heavy = RainHaze.densityFor(3, TUNING.calibration)
		expect(RainHaze.density(0.42, 1, TUNING)).toBeNear(heavy, 1e-12)
		local light = RainHaze.density(0.42, 0.15, TUNING)
		expect(
			light < 0.42 and light > RainHaze.densityFor(RainHaze.extinction(7.5, TUNING), TUNING.calibration)
		).toBe(true)
	end)
end)
