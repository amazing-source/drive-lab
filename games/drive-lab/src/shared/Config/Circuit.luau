--!strict
--[[
	The test circuit (Track.LAYOUT "Circuit"): a closed lap for judging the cars' handling, the
	river it crosses twice and its bridges. Metres and degrees, turns positive to the right; the
	lap runs clockwise from the start line. Rules/Circuit lays the segments, Rules/Bridges the
	crossings, the server's Circuit the ground, the river and the decks.
]]
local Circuit = require("../Rules/Circuit")
local Roadside = require("./Roadside")
local Track = require("./Track")

export type River = {
	offset: number,
	width: number,
	-- Metres below the road: the water's surface and the channel's bed.
	surface: number,
	bed: number,
	-- Metres of ground kept under the banks either side of the channel.
	bank: number,
}

-- The fields Rules/Bridges reads (Bridges.Layout), then the deck's depth and the parapet's height
-- above the road (metres), and how far the deck must rest on full-depth road at each bank.
export type Bridge = {
	margin: number,
	kerb: number,
	approach: number,
	clearance: number,
	bankClearance: number,
	parapetWidth: number,
	minimumAngle: number,
	thickness: number,
	parapetHeight: number,
	bearing: number,
}

export type Config = {
	-- Metres right of the first car spawn the start line runs, so the parked cars and the spawn
	-- stand on the start pad beside the main straight.
	OFFSET: number,
	SEGMENTS: { Circuit.Segment },
	-- Every arc's radius lies in this range, and road parts this far round the lap from each
	-- other keep at least CLEARANCE between their centre lines.
	RADII: { min: number, max: number },
	CLEARANCE: number,
	NEIGHBOURS: number,
	-- The grass field reaches this far past the centre line all round, laid in square tiles.
	FIELD_MARGIN: number,
	FIELD_TILE: number,
	RIVER: River,
	BRIDGE: Bridge,
}

local PARAPET_WIDTH = 0.5

local SEGMENTS: { Circuit.Segment } = {
	-- The main straight's second half: a full-throttle run to over 200 km/h, then hard braking.
	{ kind = "Straight", length = Track.START_STRAIGHT },
	-- Hairpin, about 60 km/h.
	{ kind = "Arc", radius = 25, turn = 180 },
	{ kind = "Straight", length = 150 },
	{ kind = "Arc", radius = 60, turn = -90 },
	-- Crosses the river.
	{ kind = "Straight", length = 400 },
	{ kind = "Arc", radius = 120, turn = 90 },
	{ kind = "Straight", length = 320 },
	-- Fast sweeper, about 190 km/h.
	{ kind = "Arc", radius = 250, turn = 90 },
	-- The back straight, across the river again.
	{ kind = "Closing", minimum = 150 },
	-- Chicane: weight thrown from one side to the other.
	{ kind = "Arc", radius = 50, turn = 30 },
	{ kind = "Arc", radius = 50, turn = -30 },
	{ kind = "Arc", radius = 80, turn = 90 },
	-- The main straight's first half, through the start line.
	{ kind = "Closing", minimum = 150 },
}

local Config: Config = table.freeze({
	OFFSET = 20,
	SEGMENTS = table.freeze(SEGMENTS),
	RADII = table.freeze({ min = 25, max = 300 }),
	CLEARANCE = 40,
	NEIGHBOURS = 150,
	FIELD_MARGIN = 100,
	FIELD_TILE = 200,
	RIVER = table.freeze({
		offset = 255,
		width = 24,
		surface = 3,
		bed = 5,
		bank = 3,
	}),
	BRIDGE = table.freeze({
		margin = 10,
		-- The parapet's face continues the approach guardrail's.
		kerb = Roadside.GUARDRAIL_SETBACK + PARAPET_WIDTH,
		approach = 24,
		clearance = Roadside.DELINEATOR_CLEARANCE,
		bankClearance = 1,
		parapetWidth = PARAPET_WIDTH,
		minimumAngle = 75,
		thickness = 1.5,
		parapetHeight = 0.9,
		bearing = 2,
	}),
})

return Config
