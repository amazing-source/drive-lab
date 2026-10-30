--!strict
--[[
	A car's sound: the shape of its pack (its entry's audio: the uploaded set, how the loops map
	to rpm, and the tuning of every event) and the view settings every car shares. Volumes are
	linear.
]]
local CarAudioEvents = require("../Rules/CarAudioEvents")
local EngineSound = require("../Rules/EngineSound")
local ExhaustPops = require("../Rules/ExhaustPops")

export type EngineLayer = {
	name: string,
	soundId: string,
	-- As EngineSound.Layer.
	rpm: number,
	load: EngineSound.Load,
	volume: number,
	crossoverRpm: number?,
}

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

-- One car's sound pack (its entry's audio).
export type Pack = {
	engineLayers: { EngineLayer },
	engineTuning: EngineSound.Tuning,
	engineVolume: number,
	limiter: { soundId: string, rpm: number, volume: number, onDuck: number, halfLife: number },
	far: { soundId: string, speed: number, volume: number, fromDistance: number, toDistance: number },
	eventsSoundId: string,
	startup: { region: Region, boostDb: number, handOver: number, abortRpm: number, abortHalfLife: number },
	gear: { region: Region, volume: number, upSpeed: number, downSpeed: number },
	shiftDip: { gain: number, downHalfLife: number, upHalfLife: number },
	pops: { regions: { Region }, volume: Region, speed: Region },
	popTriggers: ExhaustPops.Tuning,
	events: CarAudioEvents.Tuning,
	cockpit: ViewProfile,
	outside: ViewProfile,
	-- Studs: full volume within the minimum, silent past the maximum.
	rollOff: Region,
	farRollOff: Region,
	-- Metres from the chassis centre: forward is toward the nose, up is up.
	enginePosition: { forward: number, up: number },
	exhaustPosition: { forward: number, up: number },
}

export type CarAudio = {
	-- The camera's view attribute (Controllers/CarCamera) and its cockpit value, and how fast
	-- the mix follows a change of view.
	VIEW_ATTRIBUTE: string,
	COCKPIT_VIEW: string,
	VIEW_HALF_LIFE: number,
}

local CarAudio: CarAudio = table.freeze({
	VIEW_ATTRIBUTE = "DriveLabView",
	COCKPIT_VIEW = "Cockpit",
	VIEW_HALF_LIFE = 0.06,
})

return CarAudio
