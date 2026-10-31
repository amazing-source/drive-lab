--!strict
--[[
	The sound of speed: the uploaded pack and the mix's tuning. The pack is one file made by
	tools/audio/cut_road.py (manifest.json beside it, in drive-lab-assets/road_audio/cut): the wind
	and the roar are regions of it, in seconds, both matched at -20 LUFS, so the volumes here are
	the balance. The engine's loops are matched at -18 LUFS, so the engine's lead over the two is
	read off these volumes: tests/RoadAudio.spec.luau keeps it at 6 dB or more for every car, on
	and off throttle, in its highest gear (where the engine is quietest) up to its top speed.

	Sources, both CC0 BigSoundBank: the wind is 1450 (a storm in trees, June 2019), its gusts
	ridden down to a steady rush; the roar is 3097 (a petrol Citroen C3's cabin on a 90 km/h
	road), its one engine line at 69 Hz notched out. A first pack with Freesound 82267's wind was
	rejected by Roblox's audio moderation.
]]
local RoadAudio = require("../Rules/RoadAudio")

export type Region = RoadAudio.Range

export type RoadAudioConfig = {
	SOUND_ID: string,
	-- Seconds of each loop's own audio written on both sides of it in the pack, so a loop jump
	-- that lands a little off still plays the loop.
	GUARD: number,
	LOOPS: { wind: Region, road: Region },
	TUNING: RoadAudio.Tuning,
	-- Hz: the equaliser's mid band, the same split as the classic EqualizerSoundEffect.
	MID_BAND: Region,
	-- Q of the wind's low-pass; 0.707 is flat at its 12 dB per octave slope.
	CUTOFF_Q: number,
	-- A loop quieter than this is stopped, so standing still costs no mixing.
	SILENT_VOLUME: number,
	-- Seconds between the downward rays that read the surface under the car, and their length in
	-- metres from the chassis.
	SURFACE_INTERVAL: number,
	SURFACE_REACH: number,
	SPEED_ATTRIBUTE: string,
	VIEW_ATTRIBUTE: string,
	COCKPIT_VIEW: string,
}

local FLAT: RoadAudio.Shaping = { gain = 0, low = 0, mid = 0, high = 0 }

local Config: RoadAudioConfig = {
	SOUND_ID = "rbxassetid://134287878384634",
	GUARD = 0.25,
	LOOPS = {
		wind = { from = 0.25, to = 34.75 },
		road = { from = 35.25, to = 73.75 },
	},
	TUNING = {
		-- The SVJ's top speed (README: 354 km/h in the calibration).
		topKmh = 350,
		-- Real wind noise grows about 17-18 dB per doubling of speed and stays under the engine
		-- until near top speed. The game wants it heard from everyday speeds, so it grows slower
		-- (7 dB per doubling, flatter than the roar) and rises in pitch instead: its low-pass
		-- opens from a rumble to a hiss. Its level at top speed is held by the engine's 6 dB lead.
		windVolume = 0.37,
		windExponent = 1.2,
		cutoffKmh = { from = 30, to = 250 },
		cutoffHz = { from = 800, to = 8000 },
		windSpeed = { from = 0.9, to = 1.1 },
		-- Tyre noise grows about 30 log10(speed) dB, so amplitude with speed ^ 1.5 (the weather's
		-- spray uses the same law). The roar was recorded near 90 km/h, where its speed is 0.99.
		roadVolume = 0.32,
		roadExponent = 1.5,
		roadSpeed = { from = 0.9, to = 1.25 },
		speedHalfLife = 0.08,
		viewSeconds = 0.35,
		-- Outside, the cabin recording of the roar loses its boom and gains some bite. In the
		-- cockpit the wind loses its highs as the weather's rain does (mid -4 dB, high -12 dB) but
		-- keeps most of its level, so the cabin still hears it, while the roar comes up through the
		-- floor: almost its full level, its lows kept.
		outside = {
			wind = FLAT,
			road = { gain = 0, low = -6, mid = 2, high = 4 },
		},
		cockpit = {
			wind = { gain = -2, low = 0, mid = -4, high = -12 },
			road = { gain = -1, low = 2, mid = -2, high = -8 },
		},
		-- EST: a coarse surface roars louder and brighter, a soft one turns it to a dull rumble.
		-- Asphalt is the recording itself.
		surfaces = {
			Asphalt = FLAT,
			Concrete = { gain = 1, low = 0, mid = 1, high = 2 },
			Pavement = { gain = 2, low = 1, mid = 2, high = 3 },
			Brick = { gain = 3, low = 2, mid = 2, high = 3 },
			Cobblestone = { gain = 4, low = 4, mid = 2, high = 3 },
			Ground = { gain = -5, low = 3, mid = -3, high = -8 },
			Grass = { gain = -6, low = 3, mid = -3, high = -9 },
			LeafyGrass = { gain = -6, low = 3, mid = -3, high = -9 },
			Mud = { gain = -8, low = 3, mid = -4, high = -12 },
			Sand = { gain = -7, low = 2, mid = -3, high = -10 },
		},
		otherSurface = FLAT,
		surfaceHalfLife = 0.15,
	},
	MID_BAND = { from = 400, to = 4000 },
	CUTOFF_Q = 0.707,
	SILENT_VOLUME = 0.001,
	SURFACE_INTERVAL = 0.25,
	SURFACE_REACH = 3,
	SPEED_ATTRIBUTE = "SpeedKmh",
	VIEW_ATTRIBUTE = "DriveLabView",
	COCKPIT_VIEW = "Cockpit",
}

return table.freeze(Config)
