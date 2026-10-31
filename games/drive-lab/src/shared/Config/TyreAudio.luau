--!strict
--[[
	Tyre squeal and skid (Controllers/TyreAudio, Rules/TyreAudio). Each pack is one uploaded file
	holding both loops as regions with a guard, as the road pack does, both loops at -20 LUFS.
	PACK picks the one that plays, so the owner can switch by ear without an upload. The slip and
	slide ranges come from the offline drift, lock-up and ABS measurements
	(docs/research/13_drifting.md §6); the packs, volumes, shaping and loudness numbers are the
	audio agent's.
]]
local CarAudio = require("./CarAudio")
local TyreAudio = require("../Rules/TyreAudio")
local TyreSmoke = require("./TyreSmoke")

export type Region = TyreAudio.Range

export type Pack = { soundId: string, loops: { squeal: Region, skid: Region } }

export type PackName = "Ac" | "Real"

export type Config = {
	PACK: PackName,
	PACKS: { [PackName]: Pack },
	-- Seconds of each loop's own audio written on both sides of it in the pack.
	GUARD: number,
	TUNING: TyreAudio.Tuning,
	-- Hz: the equaliser's mid band, the same split as the road pack's.
	MID_BAND: Region,
	-- A loop quieter than this is stopped.
	SILENT_VOLUME: number,
	SLIP_ATTRIBUTES: { string },
	SLIDE_ATTRIBUTES: { string },
	-- What the engine plays, as Controllers/CarAudio publishes it on the driven car.
	ENGINE_LEVEL_ATTRIBUTE: string,
	VIEW_ATTRIBUTE: string,
	COCKPIT_VIEW: string,
}

local FLAT: TyreAudio.Shaping = { gain = 0, low = 0, mid = 0, high = 0 }

local Config: Config = {
	PACK = "Ac",
	PACKS = {
		-- Assetto Corsa's tyre pair (Kunos), as the DR458's engine pack.
		Ac = {
			soundId = "rbxassetid://101810748485104",
			loops = { squeal = { from = 0.25, to = 3.621229 }, skid = { from = 4.121229, to = 7.391458 } },
		},
		-- CC0 recordings.
		Real = {
			soundId = "rbxassetid://94272123883693",
			loops = { squeal = { from = 0.25, to = 4.35 }, skid = { from = 4.85, to = 8.45 } },
		},
	},
	GUARD = 0.25,
	TUNING = {
		squeal = {
			volume = 0.45,
			-- ABS braking peaks at 1.5 to 1.9 times peak slip, so it only chirps.
			slip = { from = 0.8, to = 1.5 },
			slide = { from = 1, to = 4 },
			pitch = { from = 0.95, to = 1.10 },
			pitchSlide = { from = 1, to = 10 },
		},
		skid = {
			volume = 0.45,
			-- A drift runs the rear at 2.9 to 6.3 times its peak slip and 4.8 to 20 m/s.
			slip = { from = 1.5, to = 4 },
			slide = { from = 3, to = 12 },
			pitch = { from = 0.90, to = 1.05 },
			pitchSlide = { from = 3, to = 20 },
		},
		-- A lock reads 10 to 12.5, the handbrake's rear 11 to 15, wheelspin without TC 15 to 30.
		lockSlip = { from = 7, to = 10 },
		lockCut = 0.7,
		-- The smoke's wet range (Config/TyreSmoke).
		wet = { from = 0.05, to = 0.3 },
		-- The quietest engine loop as heard (the SVJ's idle through its outside shaping, -21.9 LUFS)
		-- against the tyre loops' -20.0.
		loudnessOffsetDb = -1.9,
		headroomDb = 3,
		attack = 0.03,
		release = 0.12,
		viewSeconds = 0.35,
		outside = { squeal = FLAT, skid = FLAT },
		-- An estimate, not yet heard.
		cockpit = {
			squeal = { gain = -5, low = 0, mid = -3, high = -10 },
			skid = { gain = -5, low = 0, mid = -3, high = -10 },
		},
	},
	MID_BAND = { from = 400, to = 4000 },
	SILENT_VOLUME = 0.001,
	SLIP_ATTRIBUTES = TyreSmoke.SLIP_ATTRIBUTES,
	SLIDE_ATTRIBUTES = TyreSmoke.SLIDE_ATTRIBUTES,
	ENGINE_LEVEL_ATTRIBUTE = CarAudio.ENGINE_LEVEL_ATTRIBUTE,
	VIEW_ATTRIBUTE = "DriveLabView",
	COCKPIT_VIEW = "Cockpit",
}

return table.freeze(Config)
