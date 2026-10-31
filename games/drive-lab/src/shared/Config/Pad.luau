--!strict
--[[
	The all-asphalt test area (Track.LAYOUT "Pad"): one flat square of the road's asphalt round the
	parked cars, so the tyres only ever meet road, with painted lines to turn and drift around.
	Metres, in the first car spawn's frame: along its heading and to its right.
]]
local Pad = require("../Rules/Pad")

export type Stripe = {
	-- The underside's height above the road and the line's thickness.
	lift: number,
	thickness: number,
	-- Part flags: the wheels' rays and the car's body must pass through the paint.
	canCollide: boolean,
	canQuery: boolean,
	canTouch: boolean,
	castShadow: boolean,
}

export type Config = {
	AREA: Pad.Area,
	PAVING: Pad.Paving,
	MARKINGS: Pad.Markings,
	STRIPE: Stripe,
	-- RGB 0-255: the reference lines, and the line where the run-off starts.
	LINE_COLOR: { number },
	EDGE_COLOR: { number },
}

local Config: Config = table.freeze({
	-- 800 m square. Past the run-off the paving ends and the world with it.
	AREA = table.freeze({ behind = 100, ahead = 700, side = 400, runOff = 60 }),
	-- Tiles overlapping by more than a terrain voxel (0.75 m), so no seam leaves a groove.
	PAVING = table.freeze({ tile = 200, overlap = 2 }),
	MARKINGS = table.freeze({
		width = 0.3,
		chord = 3,
		-- Roblox caps a part at 2048 studs (382 m).
		longest = 300,
		circles = table.freeze({
			table.freeze({ diameter = 60, along = 420, across = 220 }),
			table.freeze({ diameter = 120, along = 420, across = -200 }),
		}),
		straight = table.freeze({ across = 12, from = 0, to = 600, every = 100, mark = 6 }),
	}),
	STRIPE = table.freeze({
		lift = 0.005,
		thickness = 0.01,
		canCollide = false,
		canQuery = false,
		canTouch = false,
		castShadow = false,
	}),
	LINE_COLOR = table.freeze({ 235, 235, 230 }),
	EDGE_COLOR = table.freeze({ 200, 50, 45 }),
})

return Config
