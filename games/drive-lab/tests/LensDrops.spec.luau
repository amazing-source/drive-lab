--!strict
local LensDrops = require("../src/shared/Rules/LensDrops")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local TUNING: LensDrops.Tuning = {
	rate = 3,
	exponent = 1.15,
	speedGain = 0.6,
	clear = 0.45,
	edgeBias = 1.5,
	margin = 0.02,
	life = { 3, 6 },
	fadeIn = 0.08,
	fadeOut = 0.6,
	slide = 0.01,
	drain = 0.08,
	drainAge = 3,
	size = { 0.03, 0.09 },
}

local seed = 2024
local function random(): number
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end

describe("LensDrops", function()
	it("lands none in the cockpit, in dry weather or under a roof", function()
		expect(LensDrops.rate(1, 1, "Cockpit", 0, TUNING)).toBe(0)
		expect(LensDrops.rate(0, 1, "Chase", 200, TUNING)).toBe(0)
		expect(LensDrops.rate(1, 0, "OnFoot", 0, TUNING)).toBe(0)
		expect(LensDrops.rate(0 / 0, 1, "Hood", 0, TUNING)).toBe(0)
	end)

	it("lands more with rain and with speed", function()
		expect(LensDrops.rate(1, 1, "Chase", 0, TUNING)).toBeNear(3, 1e-12)
		expect(LensDrops.rate(1, 1, "Chase", 100, TUNING)).toBeNear(3 * 1.6, 1e-12)
		expect(LensDrops.rate(1, 1, "Chase", -100, TUNING)).toBeNear(3 * 1.6, 1e-12)
		expect(LensDrops.rate(0.5, 1, "Hood", 0, TUNING) < LensDrops.rate(1, 1, "Hood", 0, TUNING)).toBe(true)
		expect(LensDrops.rate(1, 1, "Chase", 0 / 0, TUNING)).toBeNear(3, 1e-12)
	end)

	it("keeps the centre of the view clear and every drop on screen", function()
		local nearest, edgeward = math.huge, 0
		for _ = 1, 4000 do
			local x, y = LensDrops.place(random(), random(), TUNING)
			local radius = math.sqrt(((x - 0.5) / 0.5) ^ 2 + ((y - 0.5) / 0.5) ^ 2)
			nearest = math.min(nearest, radius)
			expect(x >= TUNING.margin - 1e-9 and x <= 1 - TUNING.margin + 1e-9).toBe(true)
			expect(y >= TUNING.margin - 1e-9 and y <= 1 - TUNING.margin + 1e-9).toBe(true)
			if radius > 0.8 then
				edgeward += 1
			end
		end
		expect(nearest >= TUNING.clear - 1e-9).toBe(true)
		-- Edge-biased: well over half land in the outer band.
		expect(edgeward > 2000).toBe(true)
	end)

	it("slides a drop down while wet, drains it faster once dry, and fades it in and out", function()
		local drop = LensDrops.new(0.25, 0.5, 0.5, 0, TUNING)
		expect(drop.life).toBe(3)
		expect(LensDrops.opacity(drop, TUNING)).toBe(0)
		local y = drop.y
		expect(LensDrops.step(drop, 0.04, true, TUNING)).toBe(true)
		expect(LensDrops.opacity(drop, TUNING)).toBeNear(0.5, 1e-9)
		expect(drop.y).toBeNear(y + 0.0004, 1e-12)
		local wetDrop, dryDrop =
			LensDrops.new(0.75, 0.2, 0.5, 1, TUNING), LensDrops.new(0.75, 0.2, 0.5, 1, TUNING)
		local wetSeconds, drySeconds = 0, 0
		while LensDrops.step(wetDrop, 0.1, true, TUNING) do
			wetSeconds += 0.1
		end
		while LensDrops.step(dryDrop, 0.1, false, TUNING) do
			drySeconds += 0.1
		end
		expect(drySeconds < wetSeconds / 2).toBe(true)
		local ending = LensDrops.new(0.5, 0.5, 0.5, 0, TUNING)
		ending.age = ending.life - 0.3
		expect(LensDrops.opacity(ending, TUNING)).toBeNear(0.5, 1e-9)
	end)

	it("never moves a drop backward in time", function()
		local drop = LensDrops.new(0.1, 0.9, 0, 0.5, TUNING)
		local age, y = drop.age, drop.y
		LensDrops.step(drop, -1, true, TUNING)
		LensDrops.step(drop, 0 / 0, false, TUNING)
		expect(drop.age).toBe(age)
		expect(drop.y).toBe(y)
	end)
end)
