--!strict
local Atmosphere = require("../src/shared/Config/Atmosphere")
local PresetBlend = require("../src/client/Atmosphere/PresetBlend")
local T = require("../../../tools/test/T")
local Wetness = require("../src/client/Atmosphere/Wetness")

local describe, it, expect = T.describe, T.it, T.expect
local CYCLIC = Atmosphere.CYCLIC

type Look = Atmosphere.Look

local function preset(name: Atmosphere.PresetName): Look
	for _, entry in Atmosphere.PRESETS do
		if entry.name == name then
			return entry.look
		end
	end
	error(`no preset {name}`)
end

-- Fails naming the first field that differs; colours compare channel by channel.
local function expectSame(actual: Look, expected: Look)
	for key, value in expected :: any do
		local got = (actual :: any)[key]
		if typeof(value) == "number" then
			if got ~= value then
				error(`{key}: expected {value}, got {got}`, 2)
			end
		else
			for _, channel in { "r", "g", "b" } do
				if got[channel] ~= value[channel] then
					error(`{key}.{channel}: expected {value[channel]}, got {got[channel]}`, 2)
				end
			end
		end
	end
end

describe("PresetBlend", function()
	it("starts exactly on the look it leaves and ends exactly on the one it heads for", function()
		local clear, rain = preset("ClearDay"), preset("Rain")
		expectSame(PresetBlend.mix(clear, rain, 0, CYCLIC), clear)
		expectSame(PresetBlend.mix(clear, rain, 1, CYCLIC), rain)
		local blend = PresetBlend.retarget(PresetBlend.settled(clear), rain, 20, CYCLIC)
		expectSame(PresetBlend.current(blend, CYCLIC), clear)
		for _ = 1, 20 * 60 + 5 do
			blend = PresetBlend.advance(blend, 1 / 60)
		end
		expectSame(PresetBlend.current(blend, CYCLIC), rain)
	end)

	it("eases in and out: half way at half time, still at both ends", function()
		local blend =
			PresetBlend.retarget(PresetBlend.settled(preset("ClearDay")), preset("Rain"), 20, CYCLIC)
		expect(PresetBlend.progress(PresetBlend.advance(blend, 10))).toBeNear(0.5, 1e-12)
		expect(PresetBlend.progress(PresetBlend.advance(blend, 0.2)) < 0.001).toBe(true)
		expect(PresetBlend.progress(PresetBlend.advance(blend, 19.8)) > 0.999).toBe(true)
	end)

	it("retargets from the look on screen, not from either end", function()
		local blend =
			PresetBlend.retarget(PresetBlend.settled(preset("ClearDay")), preset("Rain"), 20, CYCLIC)
		blend = PresetBlend.advance(blend, 7)
		local onScreen = PresetBlend.current(blend, CYCLIC)
		local turned = PresetBlend.retarget(blend, preset("NightRain"), 20, CYCLIC)
		expectSame(PresetBlend.current(turned, CYCLIC), onScreen)
		local moved = PresetBlend.current(PresetBlend.advance(turned, 1 / 60), CYCLIC)
		expect(math.abs(moved.brightness - onScreen.brightness) < 0.001).toBe(true)
	end)

	it("takes the clock the short way, through midnight", function()
		local late = table.clone(preset("NightRain"))
		local early = table.clone(late)
		late.clockTime, early.clockTime = 23, 1
		local halfway = PresetBlend.mix(late, early, 0.5, CYCLIC).clockTime
		expect(math.min(halfway, 24 - halfway)).toBeNear(0, 1e-9)
		for step = 0, 20 do
			local hour = PresetBlend.mix(late, early, step / 20, CYCLIC).clockTime
			expect(hour >= 23 - 1e-9 or hour <= 1 + 1e-9).toBe(true)
		end
		local day = PresetBlend.mix(preset("Rain"), preset("NightRain"), 0.5, CYCLIC).clockTime
		expect(day).toBeNear(17.75, 1e-9)
	end)

	it("never resets the road's wetness when a preset is chosen", function()
		local weather = PresetBlend.weather(preset("Rain"), 0.6)
		weather = PresetBlend.choose(weather, preset("ClearDay"), 20, CYCLIC)
		expect(weather.wetness).toBe(0.6)
		weather = PresetBlend.choose(weather, preset("NightRain"), 20, CYCLIC)
		expect(weather.wetness).toBe(0.6)
		-- Then it dries from there, one small step a frame.
		local blend, wetness = weather.blend, weather.wetness
		for _ = 1, 60 do
			blend = PresetBlend.advance(blend, 1 / 60)
			local nextWetness = Wetness.step(
				wetness,
				PresetBlend.current(blend, CYCLIC).rainIntensity,
				1 / 60,
				Atmosphere.WETNESS
			)
			expect(math.abs(nextWetness - wetness) < 0.001).toBe(true)
			wetness = nextWetness
		end
	end)

	it("has presets that all set the same fields, with transitions in the 10 to 30 s window", function()
		local fields = {}
		for key in Atmosphere.PRESETS[1].look :: any do
			fields[key] = true
		end
		for _, entry in Atmosphere.PRESETS do
			local count = 0
			for key in entry.look :: any do
				expect(fields[key]).toBe(true)
				count += 1
			end
			local expected = 0
			for _ in fields do
				expected += 1
			end
			expect(count).toBe(expected)
			expect(entry.look.rainIntensity >= 0 and entry.look.rainIntensity <= 1).toBe(true)
		end
		expect(Atmosphere.TRANSITION_SECONDS >= 10 and Atmosphere.TRANSITION_SECONDS <= 30).toBe(true)
	end)
end)
