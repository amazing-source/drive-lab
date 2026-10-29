--!strict
local Atmosphere = require("../src/shared/Config/Atmosphere")
local T = require("../../../tools/test/T")
local WeatherCycle = require("../src/shared/Rules/WeatherCycle")

local describe, it, expect = T.describe, T.it, T.expect

local function isPreset(name: string): boolean
	for _, preset in Atmosphere.PRESETS do
		if preset.name == name then
			return true
		end
	end
	return false
end

describe("Weather key", function()
	it("steps through the cycle and wraps round", function()
		local cycle = { "A", "B", "C" }
		expect(WeatherCycle.nextIndex(cycle, "A")).toBe(2)
		expect(WeatherCycle.nextIndex(cycle, "B")).toBe(3)
		expect(WeatherCycle.nextIndex(cycle, "C")).toBe(1)
	end)

	it("goes to the first from a preset outside the cycle", function()
		expect(WeatherCycle.nextIndex({ "A", "B" }, "Z")).toBe(1)
	end)

	it("offers a clear day, rain by day and rain at night, and starts on the clear day", function()
		local key = Atmosphere.WEATHER_KEY
		expect(table.concat(key.cycle, ",")).toBe("ClearDay,Rain,NightRain")
		expect(Atmosphere.START_PRESET).toBe("ClearDay")
		for _, name in key.cycle do
			expect(isPreset(name)).toBe(true)
		end
		expect(table.find(key.cycle, "Overcast")).toBe(nil)
	end)

	it("blends within the transition window the controller clamps to", function()
		local seconds = Atmosphere.WEATHER_KEY.seconds
		expect(seconds >= Atmosphere.TRANSITION_MIN and seconds <= Atmosphere.TRANSITION_MAX).toBe(true)
	end)
end)
