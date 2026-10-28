--!strict
local Atmosphere = require("../src/shared/Config/Atmosphere")
local T = require("../../../tools/test/T")
local Wetness = require("../src/client/Atmosphere/Wetness")

local describe, it, expect = T.describe, T.it, T.expect
local RATES = Atmosphere.WETNESS

-- Seconds of constant rain until the wetness first reaches `target`, stepping at 60 FPS.
local function secondsUntil(start: number, intensity: number, reached: (number) -> boolean): number
	local wetness, elapsed = start, 0
	while not reached(wetness) and elapsed < 5000 do
		wetness = Wetness.step(wetness, intensity, 1 / 60, RATES)
		elapsed += 1 / 60
	end
	return elapsed
end

describe("Wetness", function()
	it("stays between 0 and 1 whatever it is fed", function()
		local inputs = { -1, 0, 0.3, 1, 2, 0 / 0, math.huge, -math.huge }
		for _, wetness in inputs do
			for _, intensity in inputs do
				for _, dt in { -1, 0, 1 / 60, 5, 1e6, 0 / 0, math.huge } do
					local result = Wetness.step(wetness, intensity, dt, RATES)
					expect(result == result and result >= 0 and result <= 1).toBe(true)
				end
			end
		end
	end)

	it("does not move in zero time", function()
		expect(Wetness.step(0.42, 1, 0, RATES)).toBe(0.42)
		expect(Wetness.step(0.42, 0, 0, RATES)).toBe(0.42)
	end)

	it("wets gradually in rain and dries gradually after it, never jumping in a frame", function()
		local wetness = 0
		for _ = 1, 600 do
			local nextWetness = Wetness.step(wetness, 0.65, 1 / 60, RATES)
			expect(nextWetness > wetness).toBe(true)
			expect(nextWetness - wetness < 0.001).toBe(true)
			wetness = nextWetness
		end
		for _ = 1, 600 do
			local nextWetness = Wetness.step(wetness, 0, 1 / 60, RATES)
			expect(nextWetness < wetness).toBe(true)
			expect(wetness - nextWetness < 0.001).toBe(true)
			wetness = nextWetness
		end
	end)

	it("lands on the same wetness however the time is cut into frames", function()
		local whole = Wetness.step(0.1, 0.65, 120, RATES)
		local even, jittery = 0.1, 0.1
		for _ = 1, 7200 do
			even = Wetness.step(even, 0.65, 1 / 60, RATES)
		end
		local frames = { 1 / 144, 1 / 30, 1 / 60, 0.1, 1 / 240 }
		local elapsed, index = 0, 0
		while elapsed < 120 - 1e-9 do
			index = index % #frames + 1
			local dt = math.min(frames[index], 120 - elapsed)
			jittery = Wetness.step(jittery, 0.65, dt, RATES)
			elapsed += dt
		end
		expect(even).toBeNear(whole, 1e-9)
		expect(jittery).toBeNear(whole, 1e-9)
	end)

	it("settles where gain and loss balance", function()
		local gain, loss = 0.65 / RATES.wetSeconds, 0.35 / RATES.drySeconds
		expect(Wetness.step(0, 0.65, 1e5, RATES)).toBeNear(gain / (gain + loss), 1e-9)
	end)

	it("wets to 90 % in about 207 s of full rain and takes far longer to dry", function()
		local wetting = secondsUntil(0, 1, function(w)
			return w >= 0.9
		end)
		local drying = secondsUntil(1, 0, function(w)
			return w <= 0.1
		end)
		expect(wetting).toBeNear(207.2, 0.5)
		expect(drying).toBeNear(828.9, 0.5)
		expect(drying > 3 * wetting).toBe(true)
	end)

	it("changes material state only past a boundary by the hysteresis", function()
		local starts, h = { 0, 0.15, 0.35, 0.6, 0.85 }, 0.03
		expect(Wetness.stage(1, 0.17, starts, h)).toBe(1)
		expect(Wetness.stage(1, 0.19, starts, h)).toBe(2)
		expect(Wetness.stage(2, 0.13, starts, h)).toBe(2)
		expect(Wetness.stage(2, 0.11, starts, h)).toBe(1)
		expect(Wetness.stage(1, 1, starts, h)).toBe(5)
		expect(Wetness.stage(5, 0, starts, h)).toBe(1)
		local stage, changes = 1, 0
		for step = 0, 200 do
			local hovering = 0.15 + 0.025 * math.sin(step)
			local nextStage = Wetness.stage(stage, hovering, starts, h)
			if nextStage ~= stage then
				changes += 1
			end
			stage = nextStage
		end
		expect(changes).toBe(0)
	end)

	it("darkens from 1 dry to the soaked factor", function()
		expect(Wetness.darkening(0, 0.74, 0.6)).toBe(1)
		expect(Wetness.darkening(1, 0.74, 0.6)).toBeNear(0.74, 1e-12)
		expect(Wetness.darkening(0.5, 0.74, 0.6) < Wetness.darkening(0.25, 0.74, 0.6)).toBe(true)
	end)
end)
