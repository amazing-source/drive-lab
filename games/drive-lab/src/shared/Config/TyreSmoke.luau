--!strict
--[[
	Tyre smoke (Effects/TyreSmoke, Rules/TyreSmoke). Plain numbers and { r, g, b } colours so
	Lune can load it. The thresholds are set from the offline physics (tests/TyreSmoke.spec):
	ABS braking holds the combined slip at 1.0 to 1.4 (2.5 for an instant as the brakes bite),
	a launch on traction control at 0.4 to 0.6, while a handbrake lock reads 10 and wheelspin
	without traction control 15 to 30, the patch sliding at 10 to 19 m/s. Looks are art seeds,
	tuned by eye in edit-mode captures (2026-10-28).
]]
local RulesTyreSmoke = require("../Rules/TyreSmoke")
local Units = require("../Units")

export type Rgb = { r: number, g: number, b: number }

export type TyreSmoke = {
	-- The owner's four puffs (independent variants, one per particle), keyed by
	-- tools/assets/vfx_cells.py smoke mode.
	TEXTURE: string,
	-- The per-tyre attributes Driving publishes on the car, in Vehicle/Geometry's wheel order:
	-- combined slip over the slip of peak grip, and m/s the contact patch slides over the road.
	SLIP_ATTRIBUTES: { string },
	SLIDE_ATTRIBUTES: { string },
	THRESHOLDS: RulesTyreSmoke.Thresholds,
	THROW: RulesTyreSmoke.Throw,
	-- Studs at birth and at death (the puff grows as it spreads), and the random share either way.
	SIZE: { number },
	SIZE_SPREAD: number,
	LIFETIME: { number },
	-- Transparency at points through a particle's life: a quick fade in, a slow fade out.
	TRANSPARENCY: { { number } },
	COLOR: Rgb,
	-- Emission point over the road and behind the contact patch (m); aim above level and
	-- spread either way (degrees).
	LIFT: number,
	BACK: number,
	RISE: number,
	SPREAD: number,
	-- Speed lost per second (ParticleEmitter.Drag); rise from the heat (studs/s²).
	DRAG: number,
	BUOYANCY: number,
	-- Degrees either side of upright and of spin a second: the puffs are lit from above in the
	-- texture, so they stay near upright.
	ROTATION: number,
	ROT_SPEED: number,
	-- Studs the puffs are drawn toward the camera, so a puff low on the road is not cut by it
	-- (Roblox has no soft particles).
	Z_OFFSET: number,
}

local TyreSmoke: TyreSmoke = table.freeze({
	TEXTURE = "rbxassetid://124722630964850",
	SLIP_ATTRIBUTES = table.freeze({ "TyreSlipFL", "TyreSlipFR", "TyreSlipRL", "TyreSlipRR" }),
	SLIDE_ATTRIBUTES = table.freeze({ "TyreSlideFL", "TyreSlideFR", "TyreSlideRL", "TyreSlideRR" }),
	THRESHOLDS = table.freeze({
		slip = table.freeze({ from = 2.2, to = 4.5 }),
		slide = table.freeze({ from = 2, to = 10 }),
		-- CarWater's spray starts at 0.1.
		wet = table.freeze({ from = 0.05, to = 0.3 }),
		rate = 20,
		totalRate = 60,
		-- A thermal camera saw a tread go from 19 to 160 °C within 5 s of a burnout (S2000,
		-- 2016); a locked wheel heats one spot and smokes almost at once. Seeds, by eye.
		rise = 0.12,
		fall = 0.3,
	}),
	THROW = table.freeze({ share = 0.2, min = 0.3, max = 3.5 }),
	-- The owner found the puffs too big at 0.6 to 2.4 m (2026-10-29).
	SIZE = table.freeze({ Units.metresToStuds(0.4), Units.metresToStuds(1.4) }),
	SIZE_SPREAD = 0.25,
	LIFETIME = table.freeze({ 1.6, 3 }),
	TRANSPARENCY = table.freeze({
		table.freeze({ 0, 1 }),
		table.freeze({ 0.07, 0.56 }),
		table.freeze({ 0.45, 0.74 }),
		table.freeze({ 1, 1 }),
	}),
	-- Light grey, a touch cool, as Assetto Corsa's Custom Shaders Patch tints its tyre smoke.
	COLOR = table.freeze({ r = 212, g = 214, b = 218 }),
	LIFT = 0.3,
	BACK = 0.2,
	RISE = 15,
	SPREAD = 35,
	DRAG = 1.6,
	BUOYANCY = Units.metresToStuds(0.45),
	ROTATION = 25,
	ROT_SPEED = 14,
	-- 1.5 left the puffs' lower edges cut straight by the road in a side view (2026-10-28); a far
	-- tyre's smoke is still over 2 m behind the near flank.
	Z_OFFSET = 3,
})

return TyreSmoke
