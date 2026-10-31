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

-- A start-up recording uploaded on its own, for one that cannot be cut into the events file (an
-- upload by another creator). Seconds into it: the starter's first sound, played at the START
-- press; the starter's last; the engine catching; and the hand-over, from `handOver` to `to`,
-- in which it fades out while the engine loops fade in.
export type StartupSound = {
	id: string,
	-- Linear, over the idle loop's level at idle, as `boostDb` is for the region.
	volume: number,
	from: number,
	starterEnds: number,
	catchAt: number,
	handOver: number,
	to: number,
}

-- One car's sound pack (its entry's audio).
export type Pack = {
	engineLayers: { EngineLayer },
	engineTuning: EngineSound.Tuning,
	engineVolume: number,
	limiter: { soundId: string, rpm: number, volume: number, onDuck: number, halfLife: number },
	far: { soundId: string, speed: number, volume: number, fromDistance: number, toDistance: number },
	eventsSoundId: string,
	-- `sound`, when set, plays instead of the events file's region, which stays as its fallback
	-- should it fail to load: the two never play together.
	startup: {
		region: Region,
		boostDb: number,
		handOver: number,
		abortRpm: number,
		abortHalfLife: number,
		sound: StartupSound?,
	},
	gear: { region: Region, volume: number, upSpeed: number, downSpeed: number },
	shiftDip: { gain: number, downHalfLife: number, upHalfLife: number },
	-- The regions are cut from `soundId` when set (another car's uploaded events file), else from
	-- this pack's events file.
	pops: { regions: { Region }, volume: Region, speed: Region, soundId: string? },
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
	-- Published on the driven car: what its engine plays, as one linear amplitude, before the
	-- shift dip and the start-up (the tyres' ceiling reads it, Config/TyreAudio).
	ENGINE_LEVEL_ATTRIBUTE: string,
	-- The uploaded file a pack's pops are cut from.
	popsSoundId: (pack: Pack) -> string,
}

local CarAudio: CarAudio = table.freeze({
	VIEW_ATTRIBUTE = "DriveLabView",
	COCKPIT_VIEW = "Cockpit",
	VIEW_HALF_LIFE = 0.06,
	ENGINE_LEVEL_ATTRIBUTE = "EngineLevel",
	popsSoundId = function(pack: Pack): string
		return pack.pops.soundId or pack.eventsSoundId
	end,
})

return CarAudio
