--!strict
--[[
	The rain on the car: crowns splashing on its bodywork (bonnet, roof, engine cover), and spray
	off the rear tyres with a mist left hanging behind (Atmosphere/CarWater, Rules/CarWater).
	Plain numbers and { r, g, b } colours (0-255 sRGB) so Lune can load it. Art seeds tuned by
	eye in edit-mode captures (2026-10-28), not measurements. The paint itself is never
	darkened: a SurfaceAppearance's maps cannot change at run time.
]]
local Atmosphere = require("./Atmosphere")
local RulesCarWater = require("../Rules/CarWater")
local Units = require("../Units")

export type Splashes = {
	texture: string,
	-- Particle size (studs) and life (s), smallest and largest; the crown plays once.
	size: { number },
	lifetime: { number },
	transparency: number,
	color: Atmosphere.Rgb,
	-- Rays straight down over the car's top, columns across by rows along; each that meets
	-- painted bodywork (not glass, not a steep side) becomes a patch that splashes.
	columns: number,
	rows: number,
	-- A patch's height over the surface its ray met (studs).
	lift: number,
	rates: RulesCarWater.Splashes,
}

export type Puffs = {
	-- Particle size (studs), transparency and life (s), from emission to end.
	size: { number },
	transparency: { number },
	lifetime: { number },
}

export type Spray = {
	texture: string,
	color: Atmosphere.Rgb,
	rates: RulesCarWater.Spray,
	-- Water leaves the tyre thrown back at this share of the car's speed; with the car's whole
	-- velocity inherited, the rest stays with it, so the spray is left nearly still in the air.
	throwBack: number,
	-- Degrees above level the spray is thrown at, and its spread either way.
	rise: number,
	spread: number,
	-- Seconds for the spray to lose half its speed.
	drag: number,
	puffs: Puffs,
	-- The mist behind the car: bigger, fainter, longer, at this share of the spray's rate.
	mist: Puffs,
	mistShare: number,
}

export type CarWater = { SPLASHES: Splashes, SPRAY: Spray }

local CarWater: CarWater = table.freeze({
	SPLASHES = table.freeze({
		texture = "rbxassetid://105908704559116",
		size = table.freeze({ Units.metresToStuds(0.04), Units.metresToStuds(0.08) }),
		lifetime = table.freeze({ 0.08, 0.13 }),
		transparency = 0.5,
		color = table.freeze({ r = 182, g = 190, b = 202 }),
		columns = 2,
		rows = 5,
		lift = Units.metresToStuds(0.02),
		rates = table.freeze({ perArea = 14, exponent = 1.15, maxRate = 60 }),
	}),
	SPRAY = table.freeze({
		texture = "rbxassetid://120423533825678",
		color = table.freeze({ r = 196, g = 202, b = 210 }),
		-- Spray starts at a jog's pace on a wet road and is full by motorway speed.
		rates = table.freeze({ minSpeed = 25, fullSpeed = 160, wetFrom = 0.1, rate = 45 }),
		throwBack = 0.8,
		rise = 12,
		spread = 18,
		drag = 0.35,
		puffs = table.freeze({
			size = table.freeze({ Units.metresToStuds(0.5), Units.metresToStuds(3) }),
			transparency = table.freeze({ 0.7, 1 }),
			lifetime = table.freeze({ 0.6, 1.1 }),
		}),
		mist = table.freeze({
			size = table.freeze({ Units.metresToStuds(2), Units.metresToStuds(6) }),
			transparency = table.freeze({ 0.86, 1 }),
			lifetime = table.freeze({ 1.2, 2.2 }),
		}),
		mistShare = 0.35,
	}),
})

return CarWater
