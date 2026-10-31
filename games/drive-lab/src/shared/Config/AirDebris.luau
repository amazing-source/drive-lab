--!strict
--[[
	The air debris a fast car drives through (Effects/AirDebris, Rules/AirDebris), and the leaves
	and grit its wake lifts off the road: a few specks at a time, and at high speed faint streaks
	of air past the sides and the roof. Plain numbers and { r, g, b } colours so Lune can load
	it; sizes and distances in metres. Art seeds tuned by eye in edit-mode captures; the owner
	judges them.
]]
local RulesAirDebris = require("../Rules/AirDebris")

export type Rgb = { r: number, g: number, b: number }

export type Kind = {
	-- The owner's debris sheet cut by tools/assets/vfx_cells.py into a 2 x 2 of variants.
	texture: string,
	-- Metres across the sprite itself, smallest and largest.
	size: { number },
	-- Particles a cubic metre of air at the full speed share.
	density: number,
	color: Rgb,
	-- Through the middle of a particle's life.
	transparency: number,
	-- m/s of drift, any direction (water falls at it instead), and m/s² it falls.
	drift: number,
	fall: number,
	-- Degrees a second it may tumble.
	spin: number,
	-- Water: shown instead of the dry kinds on a wet road, and drawn along its motion past the
	-- camera (VelocityParallel) with its smear trailing.
	water: boolean,
}

export type Region = {
	-- Seconds ahead of the car the slabs begin and end: debris is placed there, then the car
	-- drives up to it.
	lead: { number },
	-- Metres of clear air kept beside and above the car's path, how far each side slab reaches
	-- out, and the height of the slabs' top over the road.
	margin: number,
	reach: number,
	height: number,
}

export type Wake = {
	-- Particles a second from each rear corner at the full speed share, on a dry road.
	rate: number,
	-- m/s thrown out and up, and the share of the car's velocity the wake drags them with.
	speed: { number },
	drag: number,
	inherit: number,
	lifetime: { number },
	-- Degrees outward from straight back, above level, and the spread either way.
	outward: number,
	rise: number,
	spread: number,
}

export type Streaks = {
	texture: string,
	shape: RulesAirDebris.Streak,
	speeds: RulesAirDebris.Speeds,
	-- Streaks a cubic metre of air at the full speed share, and the most a second from every
	-- slab together.
	density: number,
	maxRate: number,
	color: Rgb,
	-- Through the middle of a streak's life.
	transparency: number,
	-- m/s it drifts along the car's path: VelocityParallel lays a particle along its motion.
	drift: number,
	-- Share a streak's length must change by before the emitters are resized.
	resize: number,
}

export type AirDebris = {
	SPEEDS: RulesAirDebris.Speeds,
	-- Road wetness over which the dry kinds give way to water.
	WATER: { from: number, to: number },
	REGION: Region,
	LIFETIME: { number },
	-- Share of a particle's life spent fading in, and fading out.
	FADE: { number },
	-- Share of each sprite's cell the sprite fills (vfx_cells.py FILL).
	FILL: number,
	-- Degrees a water sprite is turned: VelocityParallel lays the texture's X along the motion,
	-- and vfx_cells.py draws the drop's bulb at +X with its smear toward -X.
	STREAK_ROTATION: number,
	-- Particles a second from every slab together, at most.
	MAX_RATE: number,
	KINDS: { [string]: Kind },
	-- Kinds the wake lifts.
	WAKE_KINDS: { string },
	WAKE: Wake,
	STREAKS: Streaks,
}

local AirDebris: AirDebris = table.freeze({
	SPEEDS = table.freeze({ from = 80, to = 280, exponent = 1.4 }),
	WATER = table.freeze({ from = 0.15, to = 0.45 }),
	REGION = table.freeze({ lead = table.freeze({ 0.25, 0.55 }), margin = 0.5, reach = 4, height = 2.2 }),
	LIFETIME = table.freeze({ 1.1, 1.35 }),
	FADE = table.freeze({ 0.2, 0.15 }),
	FILL = 0.86,
	STREAK_ROTATION = 0,
	MAX_RATE = 80,
	KINDS = table.freeze({
		dust = table.freeze({
			texture = "rbxassetid://130998233948691",
			size = table.freeze({ 0.025, 0.06 }),
			density = 0.025,
			color = table.freeze({ r = 214, g = 204, b = 186 }),
			transparency = 0.25,
			drift = 0.5,
			fall = 0,
			spin = 40,
			water = false,
		}),
		grit = table.freeze({
			texture = "rbxassetid://96904563444726",
			size = table.freeze({ 0.01, 0.025 }),
			density = 0.01,
			color = table.freeze({ r = 150, g = 142, b = 132 }),
			transparency = 0.1,
			drift = 0.3,
			fall = 3,
			spin = 200,
			water = false,
		}),
		leaf = table.freeze({
			texture = "rbxassetid://119631399708748",
			size = table.freeze({ 0.035, 0.07 }),
			density = 0.002,
			color = table.freeze({ r = 150, g = 128, b = 82 }),
			transparency = 0.05,
			drift = 0.8,
			fall = 0.6,
			spin = 260,
			water = false,
		}),
		drop = table.freeze({
			texture = "rbxassetid://81524213708974",
			size = table.freeze({ 0.015, 0.03 }),
			density = 0.03,
			color = table.freeze({ r = 214, g = 222, b = 232 }),
			transparency = 0.3,
			drift = 3,
			fall = 0,
			spin = 0,
			water = true,
		}),
	}),
	WAKE_KINDS = table.freeze({ "leaf", "grit" }),
	WAKE = table.freeze({
		rate = 1.5,
		speed = table.freeze({ 1.5, 4 }),
		drag = 1.5,
		inherit = 0.3,
		lifetime = table.freeze({ 1, 1.8 }),
		outward = 50,
		rise = 35,
		spread = 25,
	}),
	-- The rain pack's fine streak (Config/Atmosphere STREAK_FINE), already uploaded. A streak is
	-- the car's travel over a 1/30 s exposure, 2 m at 216 km/h; faint, lit by the scene so it
	-- never glows at night, and only from 150 km/h, where the wind is loud.
	STREAKS = table.freeze({
		texture = "rbxassetid://132075823485064",
		shape = table.freeze({
			along = 0.631,
			across = 0.0266,
			maxLength = 2.5,
			width = 0.006,
			exposure = 1 / 30,
		}),
		speeds = table.freeze({ from = 150, to = 300, exponent = 1.5 }),
		density = 0.01,
		maxRate = 30,
		color = table.freeze({ r = 236, g = 238, b = 242 }),
		transparency = 0.8,
		drift = 0.5,
		resize = 0.05,
	}),
})

return AirDebris
