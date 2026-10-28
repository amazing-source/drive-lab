--!strict
--[[
	What rain does to the camera (Rules/RainOptics, Rules/LensDrops): a brief contact blur and a
	very light far depth of field, both off in the cockpit, and water drops on the lens in the
	other views. Plain numbers and { r, g, b } colours so Lune can load it. The blur's ceiling
	and the depth of field's shape are the atmosphere brief's; the rest are art seeds tuned by
	eye in edit-mode captures (2026-10-28).
]]
local Atmosphere = require("./Atmosphere")
local LensDrops = require("../Rules/LensDrops")
local RainOptics = require("../Rules/RainOptics")
local Units = require("../Units")

export type Lens = {
	texture: string,
	-- The atlas is cells x cells images of cellSize pixels; the last row run down with a trail.
	cells: number,
	cellSize: number,
	color: Atmosphere.Rgb,
	-- Floor on a drop's image transparency: even a fresh drop lets most of the view through.
	transparency: number,
	drops: LensDrops.Tuning,
}

export type Optics = { BLUR: RainOptics.Blur, FOCUS: RainOptics.Focus, LENS: Lens }

local Optics: Optics = table.freeze({
	-- The brief's ceiling: 0 to 0.35 px, only as drops land, gone in a fraction of a second.
	BLUR = table.freeze({ max = 0.35, perDrop = 0.12, halfLife = 0.15 }),
	-- Rain's far blur, light, with a broad sharp range; the chase view focuses on the car. At
	-- speed the sharp range hugs the car and the road before it blurs (Config/MotionBlur).
	FOCUS = table.freeze({
		far = 0.12,
		radius = Units.metresToStuds(8),
		hood = Units.metresToStuds(25),
		onFoot = Units.metresToStuds(10),
		margin = Units.metresToStuds(2),
		nearMargin = Units.metresToStuds(0.3),
	}),
	LENS = table.freeze({
		texture = "rbxassetid://118920452521682",
		cells = 4,
		cellSize = 256,
		color = table.freeze({ r = 236, g = 240, b = 246 }),
		transparency = 0.45,
		drops = table.freeze({
			rate = 2.5,
			exponent = 1.15,
			speedGain = 0.8,
			clear = 0.45,
			edgeBias = 1.5,
			margin = 0.015,
			life = table.freeze({ 3, 7 }),
			fadeIn = 0.08,
			fadeOut = 0.8,
			slide = 0.006,
			drain = 0.06,
			drainAge = 3,
			size = table.freeze({ 0.05, 0.14 }),
		}),
	}),
})

return Optics
