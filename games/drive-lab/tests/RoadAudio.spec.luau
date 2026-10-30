--!strict
local CarAudio = require("../src/shared/Config/CarAudio")
local Config = require("../src/shared/Config/RoadAudio")
local EngineSound = require("../src/shared/Rules/EngineSound")
local RoadAudio = require("../src/shared/Rules/RoadAudio")
local SVJ = require("../src/shared/Config/Cars/SVJ/Physics")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

-- Length of the uploaded road_audio.ogg, seconds (manifest.json).
local PACK_LENGTH = 74.0
-- Loudness the loops are matched at: road_audio.ogg's, and the engine loops' (Config/CarAudio).
local PACK_LUFS = -20
local ENGINE_LUFS = -18

local FLAT: RoadAudio.Shaping = { gain = 0, low = 0, mid = 0, high = 0 }

local TUNING: RoadAudio.Tuning = {
	topKmh = 300,
	windVolume = 1,
	windExponent = 2,
	cutoffKmh = { from = 60, to = 300 },
	cutoffHz = { from = 500, to = 8000 },
	windSpeed = { from = 0.9, to = 1.1 },
	roadVolume = 1,
	roadExponent = 1.5,
	roadSpeed = { from = 0.9, to = 1.2 },
	speedHalfLife = 0.1,
	viewSeconds = 0.4,
	outside = { wind = FLAT, road = { gain = 0, low = -6, mid = 2, high = 4 } },
	cockpit = {
		wind = { gain = -12, low = 0, mid = -4, high = -12 },
		road = { gain = -2, low = 2, mid = -2, high = -8 },
	},
	surfaces = { Asphalt = FLAT, Grass = { gain = -6, low = 3, mid = -3, high = -9 } },
	otherSurface = { gain = 1, low = 0, mid = 0, high = 0 },
	surfaceHalfLife = 0.2,
}

local function input(overrides: { [string]: any }?): RoadAudio.Input
	local base: { [string]: any } = { speedKmh = 0, cockpit = false, driving = true, surface = "Asphalt" }
	if overrides then
		for key, value in overrides do
			base[key] = value
		end
	end
	return base :: any
end

-- A state already following `speedKmh` in the given view and on the given surface.
local function settled(speedKmh: number, cockpit: boolean, surface: string?): (RoadAudio.State, RoadAudio.Mix)
	local state = RoadAudio.new(TUNING)
	local scene: RoadAudio.Input =
		{ speedKmh = speedKmh, cockpit = cockpit, driving = true, surface = surface }
	local mix = RoadAudio.step(state, scene, 1 / 60)
	for _ = 1, 600 do
		mix = RoadAudio.step(state, scene, 1 / 60)
	end
	return state, mix
end

local function db(gain: number): number
	return 20 * math.log10(gain)
end

describe("RoadAudio", function()
	it(
		"is silent at a standstill and full at top speed, the wind on a square law, the roar on 1.5",
		function()
			expect(RoadAudio.wind(TUNING, 0)).toBe(0)
			expect(RoadAudio.road(TUNING, 0)).toBe(0)
			expect(RoadAudio.wind(TUNING, 300)).toBeNear(1, 1e-12)
			expect(RoadAudio.road(TUNING, 300)).toBeNear(1, 1e-12)
			expect(RoadAudio.wind(TUNING, 400)).toBeNear(1, 1e-12)
			-- A doubling of speed: 12 dB more wind, 9 dB more roar.
			expect(db(RoadAudio.wind(TUNING, 150) / RoadAudio.wind(TUNING, 75))).toBeNear(12.04, 0.01)
			expect(db(RoadAudio.road(TUNING, 150) / RoadAudio.road(TUNING, 75))).toBeNear(9.03, 0.01)
			local wind, road = -1, -1
			for kmh = 0, 300, 5 do
				expect(RoadAudio.wind(TUNING, kmh) >= wind).toBeTruthy()
				expect(RoadAudio.road(TUNING, kmh) >= road).toBeTruthy()
				wind, road = RoadAudio.wind(TUNING, kmh), RoadAudio.road(TUNING, kmh)
			end
		end
	)

	it("grows the wind faster than the roar, so the roar leads when slow", function()
		expect(RoadAudio.road(TUNING, 60) > 2 * RoadAudio.wind(TUNING, 60)).toBeTruthy()
		local previous = 0
		for kmh = 10, 300, 10 do
			local ratio = RoadAudio.wind(TUNING, kmh) / RoadAudio.road(TUNING, kmh)
			expect(ratio > previous).toBeTruthy()
			previous = ratio
		end
	end)

	it("opens the wind's low-pass in even octaves between its two speeds", function()
		expect(RoadAudio.cutoff(TUNING, 0)).toBeNear(500, 1e-9)
		expect(RoadAudio.cutoff(TUNING, 60)).toBeNear(500, 1e-9)
		expect(RoadAudio.cutoff(TUNING, 180)).toBeNear(2000, 1e-6)
		expect(RoadAudio.cutoff(TUNING, 300)).toBeNear(8000, 1e-6)
		expect(RoadAudio.cutoff(TUNING, 500)).toBeNear(8000, 1e-6)
		expect(RoadAudio.cutoff(TUNING, -180)).toBeNear(2000, 1e-6)
		local previous = 0
		for kmh = 0, 320, 4 do
			local cutoff = RoadAudio.cutoff(TUNING, kmh)
			expect(cutoff >= previous).toBeTruthy()
			previous = cutoff
		end
	end)

	it("fades in from silence on getting in at speed, at any frame rate", function()
		local state = RoadAudio.new(TUNING)
		local dt = 1 / 60
		local mix = RoadAudio.step(state, input({ speedKmh = 300 }), dt)
		expect(state.speed).toBeNear(300 * RoadAudio.blend(dt, TUNING.speedHalfLife), 1e-9)
		local previous = mix.wind
		for _ = 1, 120 do
			mix = RoadAudio.step(state, input({ speedKmh = 300 }), dt)
			expect(mix.wind >= previous).toBeTruthy()
			-- Never a step: at most a few hundredths of the full level per frame.
			expect(mix.wind - previous < 0.08).toBeTruthy()
			previous = mix.wind
		end
		expect(mix.wind).toBeNear(1, 1e-3)
		expect(mix.windCutoff).toBeNear(8000, 5)
		local coarse = RoadAudio.new(TUNING)
		local fine = RoadAudio.new(TUNING)
		RoadAudio.step(coarse, input({ speedKmh = 200 }), 0.1)
		for _ = 1, 10 do
			RoadAudio.step(fine, input({ speedKmh = 200 }), 0.01)
		end
		expect(coarse.speed).toBeNear(100, 1e-9)
		expect(fine.speed).toBeNear(coarse.speed, 1e-9)
	end)

	it("falls silent when the player stops driving", function()
		local state = settled(200, false, "Asphalt")
		local mix = RoadAudio.step(state, input({ speedKmh = 200, driving = false }), 1)
		expect(mix.wind < 1e-3 and mix.road < 0.01).toBeTruthy()
	end)

	it("treats a broken speed as a standstill and reverse as speed", function()
		local _, broken = settled(0 / 0, false, "Asphalt")
		expect(broken.wind).toBe(0)
		expect(broken.road).toBe(0)
		local _, infinite = settled(math.huge, false, "Asphalt")
		expect(infinite.wind).toBe(0)
		local _, reverse = settled(-60, false, "Asphalt")
		expect(reverse.road).toBeNear(RoadAudio.road(TUNING, 60), 1e-6)
	end)

	it("follows the speed with PlaybackSpeed from a standstill to top speed", function()
		local _, slow = settled(0, false, "Asphalt")
		expect(slow.windSpeed).toBeNear(0.9, 1e-9)
		expect(slow.roadSpeed).toBeNear(0.9, 1e-9)
		local _, fast = settled(300, false, "Asphalt")
		expect(fast.windSpeed).toBeNear(1.1, 1e-6)
		expect(fast.roadSpeed).toBeNear(1.2, 1e-6)
	end)

	it("muffles the wind more than the roar in the cockpit, over the view time", function()
		local state = settled(240, false, "Asphalt")
		local outside = table.clone(state.mix)
		local mix = RoadAudio.step(state, input({ speedKmh = 240, cockpit = true }), TUNING.viewSeconds / 2)
		expect(db(mix.wind / outside.wind)).toBeNear(-6, 1e-6)
		expect(mix.windEq.high).toBeNear(-6, 1e-9)
		mix = RoadAudio.step(state, input({ speedKmh = 240, cockpit = true }), TUNING.viewSeconds / 2)
		expect(db(mix.wind / outside.wind)).toBeNear(-12, 1e-6)
		expect(db(mix.road / outside.road)).toBeNear(-2, 1e-6)
		expect(mix.windEq.mid).toBeNear(-4, 1e-9)
		expect(mix.roadEq.low).toBeNear(2, 1e-9)
		expect(mix.roadEq.high).toBeNear(-8, 1e-9)
		expect(mix.road / mix.wind > outside.road / outside.wind).toBeTruthy()
	end)

	it("starts in the view the camera is in, without fading", function()
		local state = RoadAudio.new(TUNING)
		RoadAudio.step(state, input({ cockpit = true }), 1 / 60)
		expect(state.inside).toBe(1)
	end)

	it("shapes only the roar by the surface, easing into a change", function()
		local state, asphalt = settled(150, false, "Asphalt")
		local windOnAsphalt, roadOnAsphalt, lowOnAsphalt = asphalt.wind, asphalt.road, asphalt.roadEq.low
		local mix =
			RoadAudio.step(state, input({ speedKmh = 150, surface = "Grass" }), TUNING.surfaceHalfLife)
		expect(db(mix.road / roadOnAsphalt)).toBeNear(-3, 1e-6)
		expect(mix.wind).toBeNear(windOnAsphalt, 1e-9)
		local _, grass = settled(150, false, "Grass")
		expect(db(grass.road / roadOnAsphalt)).toBeNear(-6, 1e-3)
		expect(grass.roadEq.low).toBeNear(lowOnAsphalt + 3, 1e-3)
		expect(grass.roadEq.high).toBeNear(4 - 9, 1e-3)
		expect(grass.windEq.high).toBe(0)
	end)

	it("treats an unknown surface and no surface as the other surface", function()
		local _, asphalt = settled(150, false, "Asphalt")
		local _, unknown = settled(150, false, "Basalt")
		local _, airborne = settled(150, false, nil)
		expect(db(unknown.road / asphalt.road)).toBeNear(1, 1e-3)
		expect(airborne.road).toBeNear(unknown.road, 1e-9)
	end)

	it("starts on the surface it is on, without easing", function()
		local state = RoadAudio.new(TUNING)
		RoadAudio.step(state, input({ surface = "Grass" }), 1 / 60)
		expect(state.surface.gain).toBe(-6)
	end)
end)

-- The engine's quietest gear at `kmh` is the highest one it can turn in: its rpm, idle at least.
local function topGearRpm(kmh: number): number
	local ratios = SVJ.gearbox.ratios
	local radius = SVJ.rear.tyre.radius
	local wheel = kmh / 3.6 / radius
	return math.max(
		SVJ.engine.idleRpm,
		wheel * ratios[#ratios] * SVJ.driveline.rearReduction * 60 / (2 * math.pi)
	)
end

-- dB the speed sounds sit under the engine at `kmh`, by the loops' matched loudness; the
-- equalisers' band gains are left out.
local function margin(
	kmh: number,
	view: { wind: RoadAudio.Shaping, road: RoadAudio.Shaping },
	surface: RoadAudio.Shaping
): number
	local tuning = Config.TUNING
	local engine = ENGINE_LUFS
		+ db(CarAudio.ENGINE_VOLUME * EngineSound.loudness(CarAudio.ENGINE_TUNING, topGearRpm(kmh)))
	local wind = RoadAudio.wind(tuning, kmh) * 10 ^ (view.wind.gain / 20)
	local road = RoadAudio.road(tuning, kmh) * 10 ^ ((view.road.gain + surface.gain) / 20)
	local noise = PACK_LUFS + 10 * math.log10(wind ^ 2 + road ^ 2 + 1e-30)
	return engine - noise
end

describe("RoadAudio config", function()
	it("points at an uploaded asset", function()
		expect(
			string.match(Config.SOUND_ID, "^rbxassetid://%d+$") ~= nil and Config.SOUND_ID ~= "rbxassetid://0"
		).toBeTruthy()
	end)

	it("keeps both regions and their guards inside the pack, in order and apart", function()
		local previousEnd = 0
		for _, region in { Config.LOOPS.wind, Config.LOOPS.road } do
			expect(region.from - Config.GUARD >= previousEnd - 1e-6).toBeTruthy()
			expect(region.to > region.from).toBeTruthy()
			previousEnd = region.to + Config.GUARD
		end
		expect(previousEnd <= PACK_LENGTH + 1e-6).toBeTruthy()
	end)

	it("keeps the engine on top at every speed: 6 dB on asphalt, 3 dB on any surface", function()
		local tuning = Config.TUNING
		local loudest = tuning.otherSurface
		for _, surface in tuning.surfaces do
			if surface.gain > loudest.gain then
				loudest = surface
			end
		end
		for _, view in { tuning.outside, tuning.cockpit } do
			for kmh = 1, tuning.topKmh do
				expect(margin(kmh, view, tuning.surfaces.Asphalt) >= 6).toBeTruthy()
				expect(margin(kmh, view, loudest) >= 3).toBeTruthy()
			end
		end
	end)

	it("follows the SVJ's own top speed and plays the roar near as recorded at 90 km/h", function()
		local tuning = Config.TUNING
		expect(math.abs(tuning.topKmh - 350) <= 10).toBeTruthy()
		local speed = tuning.roadSpeed.from
			+ (tuning.roadSpeed.to - tuning.roadSpeed.from) * 90 / tuning.topKmh
		expect(speed).toBeNear(1, 0.02)
	end)
end)
