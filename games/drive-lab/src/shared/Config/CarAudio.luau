--!strict
--[[
	The SVJ's sound: the uploaded set (made by tools/audio/cut_loops.py from the owner's Assetto
	Corsa mod bank, gbe_lamborghini_aventador_svj_f1; manifest.json beside the files), how the
	loops map to rpm, and the tuning of every event. Volumes are linear; the files are loudness-
	matched (loops at -18 LUFS, pops at -20 LUFS on their loudest 400 ms).
]]
local CarAudioEvents = require("../Rules/CarAudioEvents")
local EngineSound = require("../Rules/EngineSound")

export type EngineLayer = {
	name: string,
	soundId: string,
	-- As EngineSound.Layer.
	rpm: number,
	load: EngineSound.Load,
	volume: number,
	crossoverRpm: number?,
}

export type ByMode = { Strada: number, Sport: number, Corsa: number }

-- Seconds into the packed events file, or any other range.
export type Region = { from: number, to: number }

-- Gains in dB below 400 Hz, from 400 Hz to 4 kHz, and above 4 kHz.
export type Equaliser = { low: number, mid: number, high: number }

export type ViewProfile = {
	-- Shaping of the cabin-recorded engine loops and of the exterior-recorded one-shots.
	engine: Equaliser,
	events: Equaliser,
	-- Share of the far loop this view may use (it still needs distance).
	far: number,
}

export type CarAudio = {
	ENGINE_LAYERS: { EngineLayer },
	ENGINE_TUNING: EngineSound.Tuning,
	ENGINE_VOLUME: number,
	LIMITER: { soundId: string, rpm: number, volume: number, onDuck: number, halfLife: number },
	FAR: { soundId: string, speed: number, volume: number, fromDistance: number, toDistance: number },
	EVENTS_SOUND_ID: string,
	STARTUP: { region: Region, boostDb: number, handOver: number, abortRpm: number, abortHalfLife: number },
	GEAR: { region: Region, volume: number, upSpeed: number, downSpeed: number },
	SHIFT_DIP: { gain: number, downHalfLife: number, upHalfLife: number },
	POPS: {
		regions: { Region },
		chance: ByMode,
		upshiftChance: ByMode,
		trainSeconds: Region,
		gapSeconds: Region,
		minRpm: number,
		volume: Region,
		speed: Region,
	},
	EVENTS: CarAudioEvents.Tuning,
	VIEW_ATTRIBUTE: string,
	COCKPIT_VIEW: string,
	VIEW_HALF_LIFE: number,
	COCKPIT: ViewProfile,
	OUTSIDE: ViewProfile,
	-- Studs: full volume within the minimum, silent past the maximum.
	ROLL_OFF: Region,
	FAR_ROLL_OFF: Region,
	-- Metres from the chassis centre: forward is toward the nose, up is up.
	ENGINE_POSITION: { forward: number, up: number },
	EXHAUST_POSITION: { forward: number, up: number },
}

local CarAudio: CarAudio = {
	-- One on and one off take is all the bank holds: each is a single steady rpm (measured off
	-- the firing order; the mod's own auto-pitch plays them at x1 at 7,600 and 7,400). The idle
	-- is played at x1 at the car's 950 rpm idle, as the mod does; its firing line would put it
	-- at 1,547 rpm (or half that), which is the owner's to judge by ear.
	ENGINE_LAYERS = {
		{
			name = "Idle",
			soundId = "rbxassetid://123221049271080",
			rpm = 950,
			load = "Both",
			volume = 1,
			-- The idle hands over early: past about 1,550 rpm it would be pitched up by over 60 %.
			crossoverRpm = 1300,
		},
		{ name = "On", soundId = "rbxassetid://73085619329523", rpm = 7558, load = "On", volume = 1 },
		{ name = "Off", soundId = "rbxassetid://95100012663530", rpm = 7268, load = "Off", volume = 1 },
	},
	ENGINE_TUNING = {
		crossfadeOctaves = 0.5,
		minSpeed = 0.1,
		maxSpeed = 2.5,
		quietRpm = 1000,
		quietDb = -12,
		loudRpm = 8000,
		loudDb = 0,
		liftHalfLife = 0.025,
		pressHalfLife = 0.06,
		volumeHalfLife = 0.03,
		speedHalfLife = 0.012,
	},
	ENGINE_VOLUME = 1,
	-- The on loop raised to 8,700 rpm and gated at 17 Hz: it replaces the on loop's flapping
	-- between fuel cuts, which the frame rate would alias.
	LIMITER = {
		soundId = "rbxassetid://115677959152238",
		rpm = 8700,
		volume = 1,
		onDuck = 0.3,
		halfLife = 0.03,
	},
	-- A broadband distant roar; the mod plays it 2.5 semitones down.
	FAR = {
		soundId = "rbxassetid://96220967528313",
		speed = 0.866,
		volume = 0.7,
		fromDistance = 60,
		toDistance = 250,
	},
	EVENTS_SOUND_ID = "rbxassetid://104848480098013",
	-- The starter (its first 0.75 s), the flare, then the cold idle settling; its last 2 s fade
	-- out while the idle loop fades in. Played from the moment START is pressed (Rules/CarEntry).
	STARTUP = {
		region = { from = 0, to = 11 },
		-- The start-up was cut 5.4 dB quieter than the idle loop's gain to keep its flare in range.
		boostDb = 5.4,
		handOver = 9.0,
		abortRpm = 1400,
		abortHalfLife = 0.08,
	},
	-- The bank's up and down gear sounds are the same file.
	GEAR = { region = { from = 11.5, to = 11.6938 }, volume = 0.6, upSpeed = 1, downSpeed = 0.92 },
	SHIFT_DIP = { gain = 0.5, downHalfLife = 0.012, upHalfLife = 0.05 },
	POPS = {
		regions = {
			{ from = 12.1938, to = 12.828 },
			{ from = 13.328, to = 13.674 },
			{ from = 14.174, to = 14.5707 },
			{ from = 15.0707, to = 15.5495 },
			{ from = 16.0495, to = 16.3969 },
			{ from = 16.8969, to = 18.1001 },
		},
		-- Chance that a lift pops; the exhaust valve opens earlier in the sportier modes.
		chance = { Strada = 0.35, Sport = 0.8, Corsa = 1 },
		upshiftChance = { Strada = 0, Sport = 0.25, Corsa = 0.6 },
		trainSeconds = { from = 0.35, to = 1.1 },
		gapSeconds = { from = 0.06, to = 0.22 },
		-- A train stops once the overrun falls below this or the throttle opens.
		minRpm = 3500,
		-- Pops are cut 2 dB below the loops and need to stand out of them.
		volume = { from = 1, to = 1.8 },
		speed = { from = 0.92, to = 1.08 },
	},
	EVENTS = { liftFrom = 0.6, liftTo = 0.1, liftMinRpm = 5000, limiterHold = 0.15 },
	VIEW_ATTRIBUTE = "DriveLabView",
	COCKPIT_VIEW = "Cockpit",
	VIEW_HALF_LIFE = 0.06,
	-- The engine loops are cabin recordings: dry inside. Outside they lose the cabin's boom and
	-- get the exhaust's rasp back; the one-shots are exterior recordings, muffled inside.
	COCKPIT = { engine = { low = 0, mid = 0, high = 0 }, events = { low = 2, mid = -4, high = -14 }, far = 0 },
	OUTSIDE = { engine = { low = -5, mid = 1.5, high = 5 }, events = { low = 0, mid = 0, high = 0 }, far = 1 },
	ROLL_OFF = { from = 30, to = 600 },
	FAR_ROLL_OFF = { from = 60, to = 2000 },
	ENGINE_POSITION = { forward = -0.6, up = 0.3 },
	EXHAUST_POSITION = { forward = -2.2, up = 0.5 },
}

return table.freeze(CarAudio)
