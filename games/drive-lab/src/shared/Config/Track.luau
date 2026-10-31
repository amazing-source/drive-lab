--!strict
--[[
	The test road. Metres; the server converts with Units, so the road keeps real proportions
	whatever the world scale.
]]
local StreetLamps = require("../Rules/StreetLamps")

-- Pad: the all-asphalt square of Config/Pad, laid once. Straight: one endless straight. Bends: an
-- endless road of seeded straights and bends. Circuit: the closed lap of Config/Circuit, laid once.
export type Layout = "Pad" | "Straight" | "Bends" | "Circuit"

export type Track = {
	LAYOUT: Layout,
	SEED: number,
	ROAD_WIDTH: number,
	VERGE_WIDTH: number,
	GROUND_DEPTH: number,
	STEP: number,
	CHUNK_STEPS: number,
	LOOKAHEAD: number,
	KEEP_BEHIND: number,
	START_STRAIGHT: number,
	RAMP: number,
	MIN_RADIUS: number,
	WAVELENGTH: number,
	STRAIGHT_SHARE: number,
	START_PAD: number,
	DASH_EVERY: number,
	DASH_LENGTH: number,
	LINE_WIDTH: number,
	UPDATE_INTERVAL: number,
	LAMPS: StreetLamps.Layout,
	LAMP_SETBACK: number,
	LAMP_ASSET: string,
}

local Track: Track = table.freeze({
	LAYOUT = "Pad" :: Layout,
	-- Same seed, same road, so a run can be repeated.
	SEED = 2026,
	-- Two 3.5 m lanes and 2 m shoulders; grass beyond (lower grip, as off a real road).
	ROAD_WIDTH = 11,
	VERGE_WIDTH = 60,
	GROUND_DEPTH = 4,
	-- Path resolution and how much road one chunk adds.
	STEP = 6,
	CHUNK_STEPS = 100,
	-- The endless layouts lay road this far ahead of every player and clear it this far behind all
	-- of them. At the SVJ's top speed (98 m/s) the lookahead lasts 15 s.
	LOOKAHEAD = 1500,
	KEEP_BEHIND = 800,
	-- A straight start, long enough for a full-throttle run to 200 km/h, then curves ease in.
	START_STRAIGHT = 600,
	RAMP = 150,
	-- The tightest bend: 120 m radius, a fast-road corner rather than a hairpin.
	MIN_RADIUS = 120,
	-- Distance over which the bend pattern changes, and the share of it kept straight.
	WAVELENGTH = 700,
	STRAIGHT_SHARE = 0.4,
	-- Square of concrete under the spawn and the car, metres a side.
	START_PAD = 120,
	-- Centre-line dashes: one every DASH_EVERY steps.
	DASH_EVERY = 2,
	DASH_LENGTH = 4,
	LINE_WIDTH = 0.15,
	UPDATE_INTERVAL = 0.25,
	-- Victorian double lamps (tools/blender/street_lamp.py) both sides of the road, scattered:
	-- a slot every 35 m a side, each moved up to 40 % of that, one in seven left empty, the
	-- sides staggered. None in the first 80 m, where the car and the spawn stand.
	LAMPS = table.freeze({ spacing = 35, jitter = 0.4, skip = 0.15, start = 80 }),
	-- Metres from the road's edge to a lamp's centre, on the verge.
	LAMP_SETBACK = 2,
	-- The lamp model, kept in the place under ReplicatedStorage.DriveLabAssets.
	LAMP_ASSET = "StreetLamp",
})

return Track
