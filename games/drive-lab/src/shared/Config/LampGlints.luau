--!strict
--[[
	The street lamps' night glints (Rules/LampGlints, drawn by Effects/LampGlints for
	Controllers/StreetLights): a faint horizontal flare on the nearest lit heads and, on a wet
	road, a streak of reflected light under them. Textures from the owner's ChatGPT pack
	(Horizontal_Lens_Flare_1024, Wet_Asphalt_Reflection_1024), cut by
	tools/assets/roadside_textures.py; RGB on black, drawn additive. Kept faint on purpose: an
	overdone flare reads cheap.
]]
local LampGlints = require("../Rules/LampGlints")

export type Config = {
	FLARE_IMAGE: string,
	REFLECTION_IMAGE: string,
	COLOUR: Color3,
	FLARE_BRIGHTNESS: number,
	REFLECTION_BRIGHTNESS: number,
	FLARES: number,
	REFLECTIONS: number,
	HEAD_HEIGHT: number,
	TOWARD_EYE: number,
	STREAK_LIFT: number,
	IN_VIEW: number,
	TUNING: LampGlints.Tuning,
}

local Config: Config = table.freeze({
	FLARE_IMAGE = "rbxassetid://135846361459595",
	REFLECTION_IMAGE = "rbxassetid://123714841724989",
	-- The lit candle-bulb's warm white, a little paler than its neon.
	COLOUR = Color3.fromRGB(255, 205, 150),
	FLARE_BRIGHTNESS = 1.5,
	REFLECTION_BRIGHTNESS = 1.2,
	-- How many of the nearest lit lamps in view get each.
	FLARES = 8,
	REFLECTIONS = 8,
	-- Metres above a lamp's base to its bulbs (tools/blender/street_lamp.py: 3.49 m).
	HEAD_HEIGHT = 3.49,
	-- The flare is drawn this much nearer the eye than the head, so the iron between the
	-- lanterns does not cut it.
	TOWARD_EYE = 0.6,
	-- The streak lies this far above the asphalt, clear of its surface.
	STREAK_LIFT = 0.03,
	-- Cosine of the widest angle off the view's centre a lamp may be at to count as in view.
	IN_VIEW = 0.2,
	TUNING = table.freeze({
		flareOpacity = 0.35,
		flareFadeFrom = 30,
		flareReach = 220,
		flareRain = 0.6,
		flareLength = 1.5,
		flareLengthPerMetre = 0.08,
		flareHeight = 0.25,
		flareHeightPerMetre = 0.025,
		reflectionOpacity = 0.55,
		reflectionFadeFrom = 40,
		reflectionReach = 180,
		dryBelow = 0.08,
		nearShare = 0.4,
		nearest = 2.5,
		edgeMargin = 0.3,
		shortest = 1.5,
		streakAngle = 0.05,
	}),
})

return Config
