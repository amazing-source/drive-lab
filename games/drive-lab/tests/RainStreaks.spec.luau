--!strict
local RainStreaks = require("../src/shared/Rules/RainStreaks")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

-- rain_streaks_02 as measured on its PNG.
local ALONG, ACROSS = 0.631, 0.0266

local function drawn(fit: RainStreaks.Fit, along: number, across: number): (number, number)
	local quad = 2 * fit.size
	local stretch = RainStreaks.stretch(fit.squash)
	return along * quad * stretch, across * quad / stretch
end

describe("RainStreaks", function()
	it("draws a sprite's streak at the asked length and width, whichever way it squashes", function()
		for _, case in
			{
				{ 0.5, 0.004, ALONG, ACROSS },
				{ 0.117, 0.007, ALONG, ACROSS },
				{ 0.05, 0.03, ALONG, ACROSS },
				{ 0.3, 0.01, 0.615, 0.051 },
			}
		do
			local fit = RainStreaks.fit(case[1], case[2], case[3], case[4])
			local length, width = drawn(fit, case[3], case[4])
			expect(length).toBeNear(case[1], 1e-9)
			expect(width).toBeNear(case[2], 1e-9)
		end
		expect(RainStreaks.fit(0.5, 0.004, ALONG, ACROSS).squash > 0).toBe(true)
		expect(RainStreaks.fit(0.05, 0.03, ALONG, ACROSS).squash < 0).toBe(true)
	end)

	it("stretches as measured in Studio, the same way both sides of zero", function()
		expect(RainStreaks.stretch(0)).toBe(1)
		expect(RainStreaks.stretch(1)).toBeNear(1.97, 0.05)
		expect(RainStreaks.stretch(2)).toBeNear(2.9, 0.12)
		expect(RainStreaks.stretch(-0.5)).toBeNear(0.67, 0.01)
		for squash = -0.9, 3, 0.1 do
			expect(RainStreaks.squashFor(RainStreaks.stretch(squash))).toBeNear(squash, 1e-9)
		end
	end)

	it("makes a streak the drop's fall over the exposure, at most the clamp", function()
		expect(RainStreaks.length(7, 1 / 60, 0.5)).toBeNear(7 / 60, 1e-12)
		expect(RainStreaks.length(7, 1, 0.5)).toBe(0.5)
		expect(RainStreaks.length(0 / 0, 1 / 60, 0.5)).toBe(0)
		expect(RainStreaks.length(7, -1, 0.5)).toBe(0)
	end)

	it("measures half a quad along the motion, and draws nothing for nonsense", function()
		expect(RainStreaks.halfLength(1, 0)).toBe(1)
		expect(RainStreaks.halfLength(1, 1)).toBe(2)
		expect(RainStreaks.halfLength(1, -0.5)).toBeNear(2 / 3, 1e-12)
		for _, odd in { { 0.1, 0.01, 0, ACROSS }, { 0.1, 0.01, ALONG, 0 / 0 }, { 0, 0.01, ALONG, ACROSS } } do
			local fit = RainStreaks.fit(odd[1], odd[2], odd[3], odd[4])
			expect(fit.size).toBe(0)
			expect(fit.squash).toBe(0)
		end
		expect(RainStreaks.squashFor(0)).toBe(0)
		expect(RainStreaks.squashFor(0 / 0)).toBe(0)
	end)
end)
