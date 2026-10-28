--!strict
local Config = require("../src/shared/Config/WeatherAudio")
local T = require("../../../tools/test/T")
local WeatherAudio = require("../src/shared/Rules/WeatherAudio")

local describe, it, expect = T.describe, T.it, T.expect

-- Length of the uploaded weather.ogg, seconds (manifest.json).
local PACK_LENGTH = 328.0431

local TUNING: WeatherAudio.Tuning = {
	fullIntensity = 0.8,
	levelExponent = 1.5,
	heavyBlend = { from = 0.2, to = 0.8 },
	riseHalfLife = 1,
	fallHalfLife = 2,
	rainVolume = 1,
	roofVolume = 1,
	sprayVolume = 1,
	viewSeconds = 0.35,
	cockpitGain = 0.35,
	cockpitMidDb = -4,
	cockpitHighDb = -12,
	sprayFullKmh = 200,
	sprayExponent = 1.5,
	spraySpeed = { from = 0.85, to = 1.2 },
	sprayHalfLife = 0.1,
	thunderFrom = 0.6,
	thunderFirstGap = { from = 8, to = 20 },
	thunderGap = { from = 30, to = 75 },
	thunderVolume = { from = 0.6, to = 1.1 },
	thunderSpeed = { from = 0.82, to = 1.04 },
	thunderTakes = 4,
}

local function input(overrides: { [string]: any }?): WeatherAudio.Input
	local base: { [string]: any } =
		{ rainIntensity = 0, wetness = 0, speedKmh = 0, cockpit = false, driving = false }
	if overrides then
		for key, value in overrides do
			base[key] = value
		end
	end
	return base :: any
end

-- A random source that returns the given values in turn, then 0.5.
local function sequence(values: { number }): () -> number
	local index = 0
	return function(): number
		index += 1
		return values[index] or 0.5
	end
end

local function rainPower(mix: WeatherAudio.Mix): number
	return mix.rainLight ^ 2 + mix.rainHeavy ^ 2
end

describe("WeatherAudio", function()
	it("is silent without rain and full at the full intensity, rising along its curve", function()
		expect(WeatherAudio.level(TUNING, 0)).toBe(0)
		expect(WeatherAudio.level(TUNING, 0.8)).toBeNear(1, 1e-12)
		expect(WeatherAudio.level(TUNING, 1)).toBeNear(1, 1e-12)
		expect(WeatherAudio.level(TUNING, 0.2)).toBeNear(0.25 ^ 1.5, 1e-12)
		local previous = -1
		for intensity = 0, 1, 0.01 do
			local level = WeatherAudio.level(TUNING, intensity)
			expect(level >= previous).toBeTruthy()
			previous = level
		end
	end)

	it("hands the light loop over to the heavy one at equal power inside the blend only", function()
		for intensity = 0, 1, 0.01 do
			local light, heavy = WeatherAudio.shares(TUNING, intensity)
			expect(light ^ 2 + heavy ^ 2).toBeNear(1, 1e-12)
		end
		local light, heavy = WeatherAudio.shares(TUNING, 0.15)
		expect(light).toBe(1)
		expect(heavy).toBe(0)
		light, heavy = WeatherAudio.shares(TUNING, 0.85)
		expect(light).toBeNear(0, 1e-12)
		expect(heavy).toBe(1)
		light, heavy = WeatherAudio.shares(TUNING, 0.5)
		expect(light ^ 2).toBeNear(0.5, 1e-12)
		expect(heavy ^ 2).toBeNear(0.5, 1e-12)
	end)

	it("builds the rain gradually from silence when the intensity jumps, at any frame rate", function()
		local state = WeatherAudio.new(TUNING, sequence({}))
		local dt = 1 / 60
		local mix = WeatherAudio.step(state, input({ rainIntensity = 0.8 }), dt)
		expect(state.intensity).toBeNear(0.8 * WeatherAudio.blend(dt, TUNING.riseHalfLife), 1e-12)
		expect(rainPower(mix) < 1e-4).toBeTruthy()
		local previous = math.sqrt(rainPower(mix))
		for _ = 1, 60 * 12 do
			mix = WeatherAudio.step(state, input({ rainIntensity = 0.8 }), dt)
			local level = math.sqrt(rainPower(mix))
			-- Never a step: at most a few hundredths of the full level per frame, and only up.
			expect(level >= previous).toBeTruthy()
			expect(level - previous < 0.02).toBeTruthy()
			previous = level
		end
		expect(previous).toBeNear(1, 1e-3)
		-- Half the gap after one half-life, whatever the frame rate.
		local coarse = WeatherAudio.new(TUNING, sequence({}))
		local fine = WeatherAudio.new(TUNING, sequence({}))
		WeatherAudio.step(coarse, input({ rainIntensity = 0.8 }), 1)
		for _ = 1, 100 do
			WeatherAudio.step(fine, input({ rainIntensity = 0.8 }), 0.01)
		end
		expect(coarse.intensity).toBeNear(0.4, 1e-9)
		expect(fine.intensity).toBeNear(coarse.intensity, 1e-9)
	end)

	it("fades out more slowly than it builds", function()
		local state = WeatherAudio.new(TUNING, sequence({}))
		state.intensity = 0.8
		WeatherAudio.step(state, input({ rainIntensity = 0 }), TUNING.riseHalfLife)
		expect(state.intensity).toBeNear(0.8 * 0.5 ^ (TUNING.riseHalfLife / TUNING.fallHalfLife), 1e-9)
		expect(state.intensity > 0.4).toBeTruthy()
	end)

	it("muffles the outside and brings the roof up in the cockpit, over the view time", function()
		local state = WeatherAudio.new(TUNING, sequence({}))
		local mix = WeatherAudio.step(state, input(), 0.01)
		expect(mix.outside).toBe(1)
		expect(mix.roof).toBe(0)
		mix = WeatherAudio.step(state, input({ cockpit = true }), TUNING.viewSeconds / 2)
		expect(mix.outside).toBeNear(math.sqrt(TUNING.cockpitGain), 1e-9)
		expect(mix.roof).toBeNear(math.sqrt(0.5), 1e-9)
		expect(mix.highGain).toBeNear(-6, 1e-9)
		mix = WeatherAudio.step(state, input({ cockpit = true }), TUNING.viewSeconds / 2)
		expect(mix.outside).toBeNear(TUNING.cockpitGain, 1e-9)
		expect(mix.roof).toBeNear(1, 1e-9)
		expect(mix.midGain).toBeNear(TUNING.cockpitMidDb, 1e-9)
		expect(mix.highGain).toBeNear(TUNING.cockpitHighDb, 1e-9)
		mix = WeatherAudio.step(state, input({ cockpit = true }), 1)
		expect(mix.roof).toBeNear(1, 1e-9)
	end)

	it("starts in the view the camera is in, without fading", function()
		local state = WeatherAudio.new(TUNING, sequence({}))
		local mix = WeatherAudio.step(state, input({ cockpit = true }), 1 / 60)
		expect(mix.roof).toBe(1)
		expect(mix.outside).toBeNear(TUNING.cockpitGain, 1e-12)
	end)

	it("plays the roof only in the rain, with the same build as the rain outside", function()
		local state = WeatherAudio.new(TUNING, sequence({}))
		local mix = WeatherAudio.step(state, input({ cockpit = true }), 1)
		expect(mix.roofLight + mix.roofHeavy).toBe(0)
		state.intensity = 0.5
		mix = WeatherAudio.step(state, input({ cockpit = true, rainIntensity = 0.5 }), 1 / 60)
		expect(mix.roofLight).toBeNear(mix.rainLight, 1e-12)
		expect(mix.roofHeavy).toBeNear(mix.rainHeavy, 1e-12)
	end)

	it("sprays only while driving on a wet road, growing with speed", function()
		expect(WeatherAudio.spray(TUNING, 120, 0)).toBe(0)
		expect(WeatherAudio.spray(TUNING, 0, 1)).toBe(0)
		expect(WeatherAudio.spray(TUNING, 200, 1)).toBe(1)
		expect(WeatherAudio.spray(TUNING, 300, 1)).toBe(1)
		expect(WeatherAudio.spray(TUNING, -100, 0.5)).toBeNear(0.5 ^ 1.5 * 0.5, 1e-12)
		expect(WeatherAudio.spray(TUNING, 0 / 0, 1)).toBe(0)
		local state = WeatherAudio.new(TUNING, sequence({}))
		for _ = 1, 120 do
			WeatherAudio.step(state, input({ speedKmh = 200, wetness = 1 }), 1 / 60)
		end
		expect(state.mix.spray).toBe(0)
		local mix = WeatherAudio.step(state, input({ speedKmh = 200, wetness = 1, driving = true }), 1 / 60)
		-- Eased in: no step on getting in at speed.
		expect(mix.spray).toBeNear(WeatherAudio.blend(1 / 60, TUNING.sprayHalfLife), 1e-12)
		for _ = 1, 120 do
			mix = WeatherAudio.step(state, input({ speedKmh = 200, wetness = 1, driving = true }), 1 / 60)
		end
		expect(mix.spray).toBeNear(1, 1e-6)
		expect(mix.spraySpeed).toBeNear(TUNING.spraySpeed.to, 1e-12)
	end)

	it("treats a broken intensity as no rain", function()
		local state = WeatherAudio.new(TUNING, sequence({}))
		state.intensity = 0.5
		WeatherAudio.step(state, input({ rainIntensity = 0 / 0 }), 1)
		expect(state.intensity).toBeNear(0.5 * 0.5 ^ (1 / TUNING.fallHalfLife), 1e-12)
		WeatherAudio.step(state, input({ rainIntensity = math.huge }), 1)
		expect(state.intensity < 0.5).toBeTruthy()
	end)

	it("rolls no thunder in light rain", function()
		local state = WeatherAudio.new(TUNING, sequence({}))
		state.intensity = 0.55
		for _ = 1, 600 do
			expect(WeatherAudio.step(state, input({ rainIntensity = 0.55 }), 1).thunder == nil).toBeTruthy()
		end
		expect(state.thunderIn == nil).toBeTruthy()
	end)

	it("rolls thunder in heavy rain after the first gap, then after the later gaps", function()
		-- Rolls: first gap 0 (8 s), take 0.5 (3), volume 1 (1.1), speed 0 (0.82), next gap 1 (75 s).
		local state = WeatherAudio.new(TUNING, sequence({ 0, 0.5, 1, 0, 1 }))
		state.intensity = 0.8
		local heavy = input({ rainIntensity = 0.8 })
		expect(WeatherAudio.step(state, heavy, 0.5).thunder == nil).toBeTruthy()
		expect(state.thunderIn).toBe(8)
		local fired: WeatherAudio.Thunder? = nil
		local waited = 0
		while fired == nil and waited < 30 do
			fired = WeatherAudio.step(state, heavy, 0.5).thunder
			waited += 0.5
		end
		local first = fired :: WeatherAudio.Thunder
		expect(waited).toBe(8)
		expect(first.take).toBe(3)
		expect(first.volume).toBeNear(1.1, 1e-12)
		expect(first.speed).toBeNear(0.82, 1e-12)
		expect(state.thunderIn).toBe(75)
	end)

	it("never rolls the same take twice in a row, and every take comes up", function()
		local seed = 0
		local state = WeatherAudio.new(TUNING, function(): number
			seed = (seed * 16807 + 12345) % 2147483647
			return seed / 2147483647
		end)
		state.intensity = 0.8
		local seen: { [number]: boolean } = {}
		local last = 0
		for _ = 1, 4000 do
			state.thunderIn = 0
			local roll = WeatherAudio.step(state, input({ rainIntensity = 0.8 }), 0.1).thunder
			if roll then
				expect(roll.take ~= last).toBeTruthy()
				expect(roll.take >= 1 and roll.take <= TUNING.thunderTakes).toBeTruthy()
				expect(roll.speed >= TUNING.thunderSpeed.from and roll.speed <= TUNING.thunderSpeed.to).toBeTruthy()
				seen[roll.take] = true
				last = roll.take
			end
		end
		for take = 1, TUNING.thunderTakes do
			expect(seen[take]).toBeTruthy()
		end
	end)

	it("forgets a pending thunder when the rain eases off", function()
		local state = WeatherAudio.new(TUNING, sequence({}))
		state.intensity = 0.8
		WeatherAudio.step(state, input({ rainIntensity = 0.8 }), 0.1)
		expect(state.thunderIn ~= nil).toBeTruthy()
		state.intensity = 0.3
		WeatherAudio.step(state, input({ rainIntensity = 0.3 }), 0.1)
		expect(state.thunderIn == nil).toBeTruthy()
	end)
end)

describe("WeatherAudio config", function()
	it("points at an uploaded asset", function()
		expect(
			string.match(Config.SOUND_ID, "^rbxassetid://%d+$") ~= nil and Config.SOUND_ID ~= "rbxassetid://0"
		).toBeTruthy()
	end)

	it("keeps every region and guard inside the pack, in order and apart", function()
		local loops = Config.LOOPS
		local regions = { loops.rainLight, loops.rainHeavy, loops.roofLight, loops.roofHeavy, loops.spray }
		local previousEnd = 0
		for _, region in regions do
			expect(region.from - Config.GUARD >= previousEnd - 1e-6).toBeTruthy()
			expect(region.to > region.from).toBeTruthy()
			previousEnd = region.to + Config.GUARD
		end
		for _, region in Config.THUNDERS do
			expect(region.from >= previousEnd).toBeTruthy()
			expect(region.to > region.from).toBeTruthy()
			previousEnd = region.to
		end
		expect(previousEnd <= PACK_LENGTH).toBeTruthy()
	end)

	it("has a thunder take for every region and a blend inside the intensities the weather uses", function()
		local tuning = Config.TUNING
		expect(tuning.thunderTakes).toBe(#Config.THUNDERS)
		expect(tuning.heavyBlend.from >= 0 and tuning.heavyBlend.to <= tuning.fullIntensity).toBeTruthy()
		expect(tuning.thunderFrom > tuning.heavyBlend.from).toBeTruthy()
	end)
end)
