--!strict
--[[
	The weather's sound: the uploaded pack and the mix's tuning. The pack is one file made by
	tools/audio/cut_weather.py (manifest.json beside it, in drive-lab-assets/weather_audio/cut):
	every loop and thunder below is a region of it, in seconds. The loops are matched at -20 LUFS
	and the thunders at -20 LUFS on their loudest 3 s, so the volumes here are the balance.

	Sources, all CC0: light rain BigSoundBank 2719 (a soft stretch of a long storm), heavy rain
	BigSoundBank 1019, rain on a car roof recorded inside the car BigSoundBank 1293 (light) and
	1294 (heavy), distant thunder BigSoundBank 3181, 3182, 3184 and 2718; the spray is noise
	shaped to a wet pass-by (Freesound 462862). Mixkit's rain was rejected by Roblox's audio
	moderation, so none of it is here.
]]
local WeatherAudio = require("../Rules/WeatherAudio")

export type Region = WeatherAudio.Range

-- Gains in dB below 400 Hz, from 400 Hz to 4 kHz, and above 4 kHz.
export type Equaliser = { low: number, mid: number, high: number }

export type WeatherAudioConfig = {
	SOUND_ID: string,
	-- Seconds of each loop's own audio written on both sides of it in the pack, so a loop jump
	-- that lands a little off still plays the loop.
	GUARD: number,
	LOOPS: { rainLight: Region, rainHeavy: Region, roofLight: Region, roofHeavy: Region, spray: Region },
	THUNDERS: { Region },
	TUNING: WeatherAudio.Tuning,
	-- Fixed on each thunder, on top of the cockpit's muffling: far away the highs are gone.
	THUNDER_EQUALISER: Equaliser,
	-- A loop quieter than this is paused, so a clear sky costs no mixing.
	SILENT_VOLUME: number,
	RAIN_ATTRIBUTE: string,
	WETNESS_ATTRIBUTE: string,
	SPEED_ATTRIBUTE: string,
	VIEW_ATTRIBUTE: string,
	COCKPIT_VIEW: string,
	-- Metres from the chassis centre: forward is toward the nose, up is up.
	SPRAY_POSITION: { forward: number, up: number },
	-- Studs: full volume within the minimum, silent past the maximum.
	ROLL_OFF: Region,
}

local THUNDERS: { Region } = {
	{ from = 227.5, to = 253.5 },
	{ from = 254, to = 280 },
	{ from = 280.5, to = 306.5 },
	{ from = 307, to = 327.543063 },
}

local Config: WeatherAudioConfig = {
	SOUND_ID = "rbxassetid://99289996856306",
	GUARD = 0.25,
	LOOPS = {
		rainLight = { from = 0.25, to = 63.75 },
		rainHeavy = { from = 64.25, to = 114.75 },
		roofLight = { from = 115.25, to = 173.75 },
		roofHeavy = { from = 174.25, to = 214.25 },
		spray = { from = 214.75, to = 226.75 },
	},
	THUNDERS = THUNDERS,
	TUNING = {
		-- Night rain's 0.85 is the full downpour; Rain's 0.65 is about 3.5 dB under it.
		fullIntensity = 0.85,
		levelExponent = 1.5,
		heavyBlend = { from = 0.2, to = 0.85 },
		riseHalfLife = 1,
		fallHalfLife = 1.5,
		rainVolume = 0.6,
		roofVolume = 0.55,
		sprayVolume = 1,
		-- The handoff's cockpit mix: 0.35 of the outside, HighGain -12 dB, MidGain -4 dB, in 0.35 s.
		viewSeconds = 0.35,
		cockpitGain = 0.35,
		cockpitMidDb = -4,
		cockpitHighDb = -12,
		-- Tyre noise grows about 30 log10(speed) dB, so amplitude with speed ^ 1.5.
		sprayFullKmh = 180,
		sprayExponent = 1.5,
		spraySpeed = { from = 0.85, to = 1.2 },
		sprayHalfLife = 0.1,
		thunderFrom = 0.6,
		thunderFirstGap = { from = 8, to = 20 },
		thunderGap = { from = 30, to = 75 },
		thunderVolume = { from = 0.45, to = 0.9 },
		thunderSpeed = { from = 0.82, to = 1.04 },
		thunderTakes = #THUNDERS,
	},
	THUNDER_EQUALISER = { low = 2, mid = -8, high = -20 },
	SILENT_VOLUME = 0.001,
	RAIN_ATTRIBUTE = "RainIntensity",
	WETNESS_ATTRIBUTE = "Wetness",
	SPEED_ATTRIBUTE = "SpeedKmh",
	VIEW_ATTRIBUTE = "DriveLabView",
	COCKPIT_VIEW = "Cockpit",
	SPRAY_POSITION = { forward = 0, up = -0.4 },
	ROLL_OFF = { from = 30, to = 600 },
}

return table.freeze(Config)
