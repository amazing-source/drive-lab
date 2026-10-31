--!strict
local StreetLamps = require("../src/shared/Rules/StreetLamps")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local LAYOUT: StreetLamps.Layout = { spacing = 35, jitter = 0.4, skip = 0.15, start = 80 }

describe("StreetLamps", function()
	it("gives a chunk the same lamps whichever way the road is cut", function()
		local whole = StreetLamps.spots(0, 1800, 2026, LAYOUT)
		local pieces = {}
		for from = 0, 1200, 600 do
			for _, spot in StreetLamps.spots(from, from + 600, 2026, LAYOUT) do
				table.insert(pieces, spot)
			end
		end
		expect(#pieces).toBe(#whole)
		for index, spot in whole do
			expect(pieces[index].s).toBeNear(spot.s, 1e-9)
			expect(pieces[index].side).toBe(spot.side)
		end
	end)

	it("lines both sides at about the spacing, a few slots empty, none at the start", function()
		local spots = StreetLamps.spots(0, 35000, 2026, LAYOUT)
		local perSide = { [-1] = 0, [1] = 0 }
		for _, spot in spots do
			perSide[spot.side] += 1
			expect(spot.s >= LAYOUT.start).toBe(true)
		end
		-- 1000 slots a side over 35 km, 15 % empty.
		for _, count in perSide do
			expect(count > 800 and count < 900).toBe(true)
		end
	end)

	it("scatters the lamps instead of a regular row", function()
		local gaps = {}
		local last: number? = nil
		for _, spot in StreetLamps.spots(0, 3500, 2026, LAYOUT) do
			if spot.side == 1 then
				if last then
					table.insert(gaps, spot.s - last)
				end
				last = spot.s
			end
		end
		table.sort(gaps)
		expect(gaps[1] < 30).toBe(true)
		expect(gaps[#gaps] > 45).toBe(true)
	end)

	it("lights from dusk to dawn", function()
		expect(StreetLamps.isNight(21.5, 18, 6.5)).toBe(true)
		expect(StreetLamps.isNight(3, 18, 6.5)).toBe(true)
		expect(StreetLamps.isNight(14, 18, 6.5)).toBe(false)
		expect(StreetLamps.isNight(6.5, 18, 6.5)).toBe(false)
	end)

	it("spreads the lamps' switch-on over the window", function()
		local low, high = math.huge, -math.huge
		for x = 0, 2000, 37 do
			local delay = StreetLamps.delay(x, x * 3, 2.5)
			low, high = math.min(low, delay), math.max(high, delay)
		end
		expect(low >= 0 and high < 2.5).toBe(true)
		expect(high - low > 1.5).toBe(true)
	end)
end)

describe("StreetLamps keep-out zones", function()
	it("leaves no lamp in a zone and every lamp outside it", function()
		local zone = { from = 1000, to = 1600 }
		local all = StreetLamps.spots(0, 3000, 2026, LAYOUT)
		local kept = StreetLamps.spots(0, 3000, 2026, LAYOUT, { zone })
		local outside = 0
		for _, spot in all do
			if spot.s < zone.from or spot.s >= zone.to then
				outside += 1
			end
		end
		expect(#kept).toBe(outside)
		expect(#kept < #all).toBe(true)
		for _, spot in kept do
			expect(spot.s < zone.from or spot.s >= zone.to).toBe(true)
		end
	end)
end)
