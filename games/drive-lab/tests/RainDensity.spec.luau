--!strict
local Atmosphere = require("../src/shared/Config/Atmosphere")
local RainDensity = require("../src/client/Atmosphere/RainDensity")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect
local EXPONENT = Atmosphere.RAIN.rateExponent
local TIERS: { Atmosphere.Tier } = { "Low", "Medium", "High" }

local seed = 12345
local function random(): number
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648 * 4 - 1.5
end

describe("RainDensity", function()
	it("draws nothing when it is dry, or for nonsense intensities", function()
		for _, tier in TIERS do
			local budget = Atmosphere.BUDGETS[tier]
			for _, intensity in { 0, -0.5, -math.huge, 0 / 0 } do
				expect(RainDensity.blockRate(1, 100, 0.5, intensity, 1, EXPONENT, budget.cap)).toBe(0)
				expect(RainDensity.splashes(intensity, 1, budget, EXPONENT)).toBe(0)
				expect(RainDensity.ripples(intensity, 1, 1, 0.35, budget, EXPONENT)).toBe(0)
			end
			expect(RainDensity.blockRate(1, 100, 0.5, 1, 0, EXPONENT, budget.cap)).toBe(0)
			expect(RainDensity.splashes(1, 0, budget, EXPONENT)).toBe(0)
		end
	end)

	it("keeps a block's air at the asked density until the cap", function()
		-- 0.2 particles per cubic metre in 100 cubic metres, living 0.5 s: 40 a second keeps 20 alive.
		expect(RainDensity.blockRate(0.2, 100, 0.5, 1, 1, EXPONENT, 400)).toBeNear(40, 1e-9)
		expect(RainDensity.blockRate(0.2, 100, 0.5, 1, 1, EXPONENT, 400) * 0.5).toBeNear(0.2 * 100, 1e-9)
		expect(RainDensity.blockRate(0.2, 1000, 0.5, 1, 1, EXPONENT, 100)).toBe(100)
		expect(RainDensity.blockRate(0.2, 100, 0.5, 0.5, 0.5, EXPONENT, 400)).toBeNear(
			40 * 0.5 ^ EXPONENT * 0.5,
			1e-9
		)
		local previous = -1
		for step = 0, 100 do
			local rate = RainDensity.blockRate(0.2, 100, 0.5, step / 100, 1, EXPONENT, 400)
			expect(rate > previous).toBe(true)
			previous = rate
		end
		expect(RainDensity.blockRate(0.2, 100, 0 / 0, 1, 1, EXPONENT, 400)).toBe(0)
		expect(RainDensity.blockRate(0.2, 100, 0, 1, 1, EXPONENT, 400)).toBe(0)
	end)

	it("never lets a block or the whole rain pass a tier's ceilings", function()
		for _, tier in TIERS do
			local budget = Atmosphere.BUDGETS[tier]
			for _ = 1, 500 do
				local rate = RainDensity.blockRate(
					random() * 3,
					random() * 1e5,
					0.05 + math.abs(random()),
					random(),
					random(),
					EXPONENT,
					budget.cap
				)
				expect(rate >= 0 and rate <= budget.cap).toBe(true)
				local requested = math.abs(random()) * 2000
				expect(requested * RainDensity.within(requested, budget.live) <= budget.live + 1e-9).toBe(
					true
				)
				expect(RainDensity.splashes(random(), random(), budget, EXPONENT) <= budget.splashRate).toBe(
					true
				)
			end
			expect(RainDensity.within(budget.live / 2, budget.live)).toBe(1)
			expect(RainDensity.within(0, budget.live)).toBe(1)
			-- Low within the mobile cap of 100 per emitter per second, Medium (where Automatic
			-- starts) at most 150, High within the desktop cap of 400.
			local cap = if tier == "High" then 400 elseif tier == "Medium" then 150 else 100
			for _, rate in { budget.cap, budget.splashRate, budget.rippleRate } do
				expect(rate > 0 and rate <= cap).toBe(true)
			end
		end
		-- A higher tier never draws less.
		expect(Atmosphere.BUDGETS.Low.live < Atmosphere.BUDGETS.Medium.live).toBe(true)
		expect(Atmosphere.BUDGETS.Medium.live < Atmosphere.BUDGETS.High.live).toBe(true)
	end)

	it("keeps the rays within each tier's ceiling", function()
		local sampled, other = 0, 0
		for _, ring in Atmosphere.RAIN.rings do
			if ring.sampled then
				sampled += 4
			else
				other += 4
			end
		end
		for _, tier in TIERS do
			local budget = Atmosphere.BUDGETS[tier]
			local rays = RainDensity.raysPerSecond(budget, sampled, other, Atmosphere.RAIN.shelterInterval)
			expect(rays <= budget.rays).toBe(true)
		end
	end)

	it("ripples only on a road wet past the threshold, more the wetter it is", function()
		local budget = Atmosphere.BUDGETS.Medium
		expect(RainDensity.ripples(1, 1, 0.2, 0.35, budget, EXPONENT)).toBe(0)
		expect(RainDensity.ripples(1, 1, 0.35, 0.35, budget, EXPONENT)).toBe(0)
		expect(RainDensity.ripples(1, 1, 1, 0.35, budget, EXPONENT)).toBeNear(budget.rippleRate, 1e-9)
		local half = RainDensity.ripples(1, 1, 0.675, 0.35, budget, EXPONENT)
		expect(half).toBeNear(budget.rippleRate / 2, 1e-9)
		expect(RainDensity.ripples(1, 1, 0 / 0, 0.35, budget, EXPONENT)).toBe(0)
		expect(RainDensity.ripples(1, 1, 1, 1, budget, EXPONENT)).toBe(0)
	end)

	it("maps saved graphics levels to tiers, and Automatic or nonsense to the fallback", function()
		local levels, fallback = Atmosphere.QUALITY_LEVELS, Atmosphere.DEFAULT_TIER
		expect(RainDensity.tier(0, levels, fallback)).toBe("Medium")
		expect(RainDensity.tier(1, levels, fallback)).toBe("Low")
		expect(RainDensity.tier(3, levels, fallback)).toBe("Low")
		expect(RainDensity.tier(4, levels, fallback)).toBe("Medium")
		expect(RainDensity.tier(7, levels, fallback)).toBe("Medium")
		expect(RainDensity.tier(8, levels, fallback)).toBe("High")
		expect(RainDensity.tier(10, levels, fallback)).toBe("High")
		for _, odd in { -1, 11, 2.5, 0 / 0, math.huge } do
			expect(RainDensity.tier(odd, levels, fallback)).toBe("Medium")
		end
		expect(RainDensity.tier(0, levels, "Low")).toBe("Low")
	end)

	it("spreads sparse events evenly over frames and never bursts after a long one", function()
		local function count(frames: number, dt: number): number
			local carry, total = 0, 0
			for _ = 1, frames do
				local due
				due, carry = RainDensity.accumulate(carry, 8, dt, 4)
				total += due
			end
			return total
		end
		-- 1/64 s is exact in binary, so ten seconds give exactly 80; at 1/60 rounding may hold
		-- the last one back a frame.
		expect(count(640, 1 / 64)).toBe(80)
		expect(math.abs(count(600, 1 / 60) - 80) <= 1).toBe(true)
		local due, left = RainDensity.accumulate(0, 24, 2, 4)
		expect(due).toBe(4)
		expect(left).toBe(0)
		expect((RainDensity.accumulate(0.5, 0 / 0, 1 / 60, 4))).toBe(0)
	end)
end)
