--!strict
--[[
	Weather and atmosphere: the four presets, how fast the road wets and dries, the rain's
	rings, splashes and budgets per quality tier, how far you see in rain, the wet road's
	material states, and the Studio panel.
	Plain numbers and { r, g, b } colours (0-255 sRGB) only, so Lune can load it; the client
	builds the Color3s. Values start from the atmosphere handoff (2026-10-27) and were tuned by
	eye in edit-mode captures; none is a measurement against a reference.
]]
local Units = require("../Units")
local WindshieldDrops = require("../Rules/WindshieldDrops")

export type Rgb = { r: number, g: number, b: number }
export type PresetName = "ClearDay" | "Overcast" | "Rain" | "NightRain"
export type Tier = "Low" | "Medium" | "High"

-- Everything a preset sets, blended field by field; clockTime blends round the clock.
export type Look = {
	rainIntensity: number,
	clockTime: number,
	brightness: number,
	exposureCompensation: number,
	ambient: Rgb,
	outdoorAmbient: Rgb,
	atmosphereDensity: number,
	atmosphereOffset: number,
	atmosphereHaze: number,
	atmosphereGlare: number,
	atmosphereColor: Rgb,
	atmosphereDecay: Rgb,
	cloudCover: number,
	cloudDensity: number,
	cloudColor: Rgb,
	contrast: number,
	saturation: number,
	tint: Rgb,
	bloomIntensity: number,
	sunRaysIntensity: number,
	-- The rain streaks' colour and how much of each layer's opacity shows. Streaks are lit by
	-- the scene, so this is their albedo: by day it holds a streak's lit brightness near the
	-- overcast sky's, so streaks show against darker ground and fade against the sky; by night
	-- it keeps the ones only the sky lights faint, while the headlights and lamps, far brighter,
	-- still light theirs.
	rainColor: Rgb,
	rainOpacity: number,
	-- How additive the streaks blend, 0 to 1 (ParticleEmitter.LightEmission). By day 0: a streak
	-- replaces what is behind it, so against a bright sky it is no brighter than the sky. By
	-- night 1: lit only by the sky's faint ambient, a normally blended streak drew darker than
	-- the glowing horizon behind it, a black scratch (seen in Studio, 2026-10-28); added, it
	-- can only brighten, so unlit drops vanish and the ones in a beam shine.
	rainEmission: number,
}

export type Preset = { name: PresetName, label: string, look: Look }

export type Budget = {
	-- Share of the rings' full densities this tier draws.
	share: number,
	-- The most particles per second one streak emitter may emit, and the most streaks alive
	-- at once over every ring: past it every ring's rate is scaled down together.
	cap: number,
	live: number,
	-- Splash boxes on the ground, a grid of splashColumns * splashRows, and splashes and
	-- ripples per second per box at full rain.
	splashColumns: number,
	splashRows: number,
	splashRate: number,
	rippleRate: number,
	-- Shelter rays per block of the rings that sample several, per refresh.
	shelterSamples: number,
	-- Ceiling on shelter and ground rays per second together.
	rays: number,
	-- The most water drops on the lens at once.
	lensDrops: number,
}

-- One sprite of the owner's rain pack (drive-lab-assets/chatgpt_rain_2026-10-28): its image,
-- and the share of its 512 px canvas its mark spans, measured on the PNG: along (where it is
-- above a fifth of its peak) and across (its area over its peak, an equivalent width). The
-- pack manifest's alpha >= 16 bounds are wider: they take in the faint shoulders.
export type Sprite = { image: string, along: number, across: number }

-- How one ring's streaks are drawn: the sprites (one emitter each per block, sharing the
-- block's rate), the streak's visible width (studs) with the random spread of a particle's size
-- either side (a share), and how see-through it is through its life and per particle.
export type Layer = {
	sprites: { { sprite: Sprite, share: number } },
	width: number,
	spread: number,
	transparency: number,
	transparencySpread: number,
}

-- One ring of rain round the camera's hole (Rules/RainRings).
export type Ring = {
	-- How deep the ring is, and how tall its column over the ground (studs).
	depth: number,
	height: number,
	-- Live particles per cubic metre at full rain on a tier whose share is 1.
	density: number,
	-- Whether its blocks take the tier's shelter samples rather than one.
	sampled: boolean,
	layer: Layer,
}

-- Rings spreading on wet, near-level ground from the splash boxes: flat, depth-tested, growing
-- from a third of their diameter to all of it while they fade.
export type Ripples = {
	sprites: { Sprite },
	-- Visible diameter (studs) and life (s), smallest and largest; peak opacity.
	diameter: { number },
	lifetime: { number },
	opacity: number,
	-- None below this road wetness; all of them on a soaked road.
	wetFrom: number,
	-- Ground steeper than this, or not one of these materials, gets none.
	maxSlope: number,
	materials: { string },
}

export type Splash = {
	texture: string,
	-- Particle size (studs) and life (s), smallest and largest; the crown plays once over a life.
	size: { number },
	lifetime: { number },
	transparency: number,
	color: Rgb,
	-- Side of one splash box (studs), and in the car views how far ahead of the car's front
	-- the boxes start, where the bonnet no longer hides the road.
	cell: number,
	ahead: number,
	-- The box's height over the ground, so a crown stands on the road rather than in it.
	lift: number,
	-- Steeper ground than this takes no splash.
	maxSlope: number,
	-- A box's ground ray starts this far over the camera, above any car roof near it.
	probeHeight: number,
}

export type Stage = {
	variant: string,
	-- Wetness from which this state shows.
	from: number,
	color: string,
	normal: string,
	roughness: string,
}

export type WetRoad = {
	soaked: { [string]: number },
	darkenExponent: number,
	colourStep: number,
	material: string,
	studsPerTile: number,
	variantColor: Rgb,
	hysteresis: number,
	stages: { Stage },
}

export type Rain = {
	fallSpeed: number,
	lean: number,
	windHeading: number,
	exposure: number,
	maxLength: number,
	rateExponent: number,
	inletSeconds: number,
	fadeIn: number,
	fadeOut: number,
	cameraHole: number,
	carMargin: number,
	behindSpeed: number,
	behindShare: number,
	ahead: number,
	rings: { Ring },
	ripples: Ripples,
	groundFallback: number,
	leadSeconds: number,
	velocityHalfLife: number,
	teleportDistance: number,
	shelterReach: number,
	shelterInterval: number,
	splash: Splash,
}

-- The atmosphere's density in rain follows the rain's real visibility (Rules/RainHaze).
export type Haze = {
	fullRate: number,
	extinction50: number,
	exponent: number,
	takeOver: number,
	calibration: { { density: number, extinction: number } },
}

-- One sprite of the pack drawn on the windscreen: its image, the share of its square canvas
-- that shows across, the visible widths a drop takes (metres), smallest and largest, and the
-- height of the drop's centre on its canvas (0.5 for a bead; a trail's drop sits low).
export type GlassSprite = { image: string, across: number, width: { number }, bead: number }

-- Water on the windscreen in the cockpit view (Atmosphere/Windshield, Rules/WindshieldDrops).
export type Windshield = {
	bead: GlassSprite,
	-- A drop with its trail.
	trail: GlassSprite,
	-- Peak opacity, how much the scene's light shades the drops, canvas pixels per stud, metres
	-- the drops sit inside the glass, and seconds a wiper's pass takes to fade one.
	opacity: number,
	lightInfluence: number,
	pixelsPerStud: number,
	inset: number,
	wipeSeconds: number,
	drops: WindshieldDrops.Tuning,
}

export type Atmosphere = {
	PRESETS: { Preset },
	START_PRESET: PresetName,
	START_WETNESS: number,
	WEATHER_KEY: { cycle: { PresetName }, seconds: number, labelSeconds: number },
	TRANSITION_SECONDS: number,
	TRANSITION_MIN: number,
	TRANSITION_MAX: number,
	CYCLIC: { [string]: number },
	WETNESS: { wetSeconds: number, drySeconds: number },
	PUBLISH_STEP: number,
	LIGHTING: {
		environmentDiffuseScale: number,
		environmentSpecularScale: number,
		globalShadows: boolean,
		bloomThreshold: number,
		bloomSize: number,
		sunRaysSpread: number,
		colorCorrectionBrightness: number,
	},
	WET_ROAD: WetRoad,
	RAIN: Rain,
	HAZE: Haze,
	WINDSHIELD: Windshield,
	QUALITY_LEVELS: { low: number, medium: number },
	DEFAULT_TIER: Tier,
	BUDGETS: { [Tier]: Budget },
	DEV_PANEL: boolean,
	OVERRIDE_STEPS: { number },
	PANEL_REFRESH: number,
}

local function rgb(r: number, g: number, b: number): Rgb
	return table.freeze({ r = r, g = g, b = b })
end

-- The atmosphere's colour stays neutral in the day presets, so a blend between them only moves
-- its density. The handoff's 199, 211, 222 read blue against this place's clear-sky skybox; the
-- overcast presets also lean on haze, full cloud and desaturation to grey that sky out, since a
-- skybox cannot be blended (one sky for every preset, as the handoff asks). By night that light
-- grey glowed as a pale blue band all along the horizon; NIGHT_AIR lets the distance fade into
-- the dark instead (edit-mode captures, 2026-10-28).
local AIR = rgb(196, 200, 204)
local NIGHT_AIR = rgb(64, 68, 78)

local PRESETS: { Preset } = {
	{
		name = "ClearDay",
		label = "Clear day",
		look = {
			rainIntensity = 0,
			clockTime = 14,
			brightness = 2.4,
			exposureCompensation = 0.1,
			ambient = rgb(0, 0, 0),
			outdoorAmbient = rgb(70, 74, 80),
			atmosphereDensity = 0.25,
			atmosphereOffset = 0.1,
			atmosphereHaze = 0.8,
			atmosphereGlare = 0.06,
			atmosphereColor = AIR,
			atmosphereDecay = rgb(106, 112, 125),
			cloudCover = 0.45,
			cloudDensity = 0.45,
			cloudColor = rgb(255, 255, 255),
			contrast = 0.04,
			saturation = -0.02,
			tint = rgb(255, 253, 249),
			bloomIntensity = 0.05,
			sunRaysIntensity = 0.015,
			rainColor = rgb(132, 138, 148),
			rainOpacity = 1,
			rainEmission = 0,
		},
	},
	{
		name = "Overcast",
		label = "Overcast",
		look = {
			rainIntensity = 0,
			clockTime = 14,
			brightness = 2,
			exposureCompensation = 0.3,
			ambient = rgb(0, 0, 0),
			outdoorAmbient = rgb(90, 92, 96),
			atmosphereDensity = 0.42,
			atmosphereOffset = 0.1,
			atmosphereHaze = 2.4,
			atmosphereGlare = 0,
			atmosphereColor = AIR,
			atmosphereDecay = rgb(128, 132, 138),
			cloudCover = 1,
			cloudDensity = 0.9,
			cloudColor = rgb(220, 222, 225),
			contrast = 0.05,
			saturation = -0.25,
			tint = rgb(250, 252, 255),
			bloomIntensity = 0.04,
			sunRaysIntensity = 0,
			rainColor = rgb(132, 138, 148),
			rainOpacity = 1,
			rainEmission = 0,
		},
	},
	{
		name = "Rain",
		label = "Rain",
		look = {
			rainIntensity = 0.65,
			clockTime = 14,
			brightness = 1.6,
			exposureCompensation = 0.25,
			ambient = rgb(0, 0, 0),
			outdoorAmbient = rgb(80, 82, 88),
			atmosphereDensity = 0.48,
			atmosphereOffset = 0.1,
			atmosphereHaze = 2.8,
			atmosphereGlare = 0,
			atmosphereColor = AIR,
			atmosphereDecay = rgb(112, 116, 124),
			cloudCover = 1,
			cloudDensity = 0.95,
			cloudColor = rgb(172, 176, 182),
			contrast = 0.06,
			saturation = -0.3,
			tint = rgb(244, 248, 255),
			bloomIntensity = 0.08,
			sunRaysIntensity = 0,
			rainColor = rgb(132, 138, 148),
			rainOpacity = 1,
			rainEmission = 0,
		},
	},
	{
		name = "NightRain",
		label = "Night rain",
		look = {
			rainIntensity = 0.85,
			clockTime = 21.5,
			brightness = 0.6,
			exposureCompensation = 0.6,
			ambient = rgb(0, 0, 0),
			outdoorAmbient = rgb(62, 68, 86),
			atmosphereDensity = 0.32,
			atmosphereOffset = 0.1,
			atmosphereHaze = 1.5,
			atmosphereGlare = 0,
			atmosphereColor = NIGHT_AIR,
			atmosphereDecay = rgb(40, 44, 56),
			cloudCover = 1,
			cloudDensity = 0.8,
			cloudColor = rgb(60, 64, 72),
			contrast = 0.08,
			saturation = -0.06,
			tint = rgb(229, 237, 255),
			bloomIntensity = 0.12,
			sunRaysIntensity = 0,
			rainColor = rgb(70, 74, 82),
			rainOpacity = 1,
			rainEmission = 1,
		},
	},
}

local function stage(name: string, from: number, color: number, normal: number, roughness: number): Stage
	return table.freeze({
		variant = `DriveLabAsphalt{name}`,
		from = from,
		color = `rbxassetid://{color}`,
		normal = `rbxassetid://{normal}`,
		roughness = `rbxassetid://{roughness}`,
	})
end

-- Ceilings per tier. Every streak emitter is capped at `cap` particles a second and all of them
-- together at `live` streaks alive at once, whatever the rings ask for. The brief's starting
-- ceilings (70 / 140 / 240 live) left the rain unreadable: about a quarter of the rings is in a
-- forward view, and at 140 the rain read as a few scattered dashes (edit-mode captures,
-- 2026-10-28). Measured at Medium with 1000 live, chase view, NightRain, edit mode: render CPU
-- +0.35 ms over dry (stage A +0.66 ms in the same harness); GPU time not measured. High is for
-- desktops (400 per emitter). Rays: the near ring's blocks take shelterSamples each, others one.
local BUDGETS: { [Tier]: Budget } = table.freeze({
	Low = table.freeze({
		share = 0.5,
		cap = 100,
		live = 400,
		splashColumns = 2,
		splashRows = 1,
		splashRate = 60,
		rippleRate = 20,
		shelterSamples = 1,
		rays = 60,
		lensDrops = 6,
	}),
	Medium = table.freeze({
		share = 1,
		cap = 150,
		live = 1000,
		splashColumns = 2,
		splashRows = 2,
		splashRate = 100,
		rippleRate = 35,
		shelterSamples = 2,
		rays = 80,
		lensDrops = 12,
	}),
	High = table.freeze({
		share = 1.6,
		cap = 400,
		live = 2000,
		splashColumns = 3,
		splashRows = 2,
		splashRate = 100,
		rippleRate = 40,
		shelterSamples = 3,
		rays = 140,
		lensDrops = 20,
	}),
})

-- The owner's rain pack (drive-lab-assets/chatgpt_rain_2026-10-28), uploaded 2026-10-28; the
-- image ids and decal ids are in image_ids.json beside it. Separate variants, never flipbooks.
local STREAK_FINE: Sprite =
	table.freeze({ image = "rbxassetid://132075823485064", along = 0.631, across = 0.0266 })
local STREAK_SOFT: Sprite =
	table.freeze({ image = "rbxassetid://98809319796409", along = 0.615, across = 0.051 })
local RIPPLE_A: Sprite = table.freeze({ image = "rbxassetid://70432373652095", along = 0.65, across = 0.65 })
local RIPPLE_B: Sprite = table.freeze({ image = "rbxassetid://80995121905887", along = 0.67, across = 0.67 })

local START_PRESET: PresetName = "ClearDay"
local DEFAULT_TIER: Tier = "Medium"

local Atmosphere: Atmosphere = table.freeze({
	PRESETS = table.freeze(PRESETS),
	-- The preset the client starts in, and the road's wetness then.
	START_PRESET = START_PRESET,
	START_WETNESS = 0,
	-- The player's weather key (Config/Controls.WEATHER) steps through these, each blended in
	-- over `seconds`, its name shown for `labelSeconds`. Overcast stays a developer-panel preset:
	-- the owner wants a clear day, rain by day and rain by night, without the overcast haze.
	WEATHER_KEY = table.freeze({
		cycle = table.freeze({ "ClearDay", "Rain", "NightRain" } :: { PresetName }),
		seconds = 10,
		labelSeconds = 2.5,
	}),
	-- Seconds from one preset to the next, smoothstepped. The handoff's window is 10 to 30 s; a
	-- request outside it is clamped.
	TRANSITION_SECONDS = 20,
	TRANSITION_MIN = 10,
	TRANSITION_MAX = 30,
	-- Blended round the 24-hour clock, the short way (23:00 to 01:00 passes midnight).
	CYCLIC = table.freeze({ clockTime = 24 }),

	-- dW/dt = I/WET_SECONDS * (1 - W) - (1 - I)/DRY_SECONDS * W: in full rain a dry road is 90 %
	-- wet after about 207 s; after rain stops, 90 % of the water is gone after about 829 s.
	WETNESS = table.freeze({ wetSeconds = 90, drySeconds = 360 }),
	-- Workspace attributes are rewritten only when they move this much, so the grip reader and
	-- attribute listeners are not woken every frame for a value that creeps.
	PUBLISH_STEP = 0.001,

	-- Lighting held constant by every preset (the handoff's seeds). LightingStyle Realistic and
	-- PrioritizeLightingQuality are place settings: the client only checks them.
	LIGHTING = table.freeze({
		environmentDiffuseScale = 1,
		environmentSpecularScale = 1,
		globalShadows = true,
		bloomThreshold = 1.2,
		bloomSize = 18,
		sunRaysSpread = 0.1,
		colorCorrectionBrightness = 0,
	}),

	-- The wet road. Terrain's colour per material darkens continuously toward its soaked factor
	-- (porous surfaces darken as water fills them: asphalt most, grass least). The asphalt also
	-- steps through authored MaterialVariant states for roughness and pooled water, built from one
	-- CC0 photoscan (Poly Haven asphalt_pit_lane, 2 m tile) so a step never shifts the pattern.
	WET_ROAD = table.freeze({
		soaked = table.freeze({ Asphalt = 0.74, Concrete = 0.8, Grass = 0.88 }),
		-- Below 1, damp darkens quickly and then levels off, as a surface's pores fill first.
		darkenExponent = 0.6,
		-- Terrain is recoloured only when wetness moved this much: a recolour is not free.
		colourStep = 0.004,
		material = "Asphalt",
		-- The states are MaterialVariants named by `variant`. Their maps can only be set by a
		-- plugin, so they are authored into the place's MaterialService in Studio from the ids
		-- below at this tile size (the scan's own 2 m); the client only switches between them.
		studsPerTile = Units.metresToStuds(2),
		-- The asphalt's dry tint once the states show. Terrain colour multiplies a variant's
		-- colour map, so near white keeps the scan's own albedo; slightly cool to sit in the
		-- overcast palette.
		variantColor = rgb(232, 236, 240),
		-- A state change needs wetness this far past the boundary, so it never flickers.
		hysteresis = 0.03,
		-- Three states, not five: on this Studio build each override switch draws the road as flat
		-- colour for 1.5 to 4 s while terrain rebuilds the material (edit-mode captures,
		-- 2026-10-27), so every state costs one flash on the way up and one on the way down. The
		-- other two authored sets (Wet: 83882163913603 / 94182010554618 / 107118125148729;
		-- Soaked: 80890331811627 / 83966969363751 / 134495843305077) are uploaded and unused.
		stages = table.freeze({
			stage("Dry", 0, 127208347570049, 129022494795172, 81081446190615),
			stage("Damp", 0.15, 127208347570049, 129022494795172, 84647480964564),
			stage("Wetter", 0.5, 113873775285728, 120645058405252, 75943263889119),
		}),
	}),

	-- The rain: two rings of streaks round the camera, out to about 10 m, and beyond them only
	-- the Atmosphere's haze (Rules/RainHaze), which is how distant rain reads (Garg and Nayar,
	-- "When does a camera see rain?", 2005: past a few metres single drops fall below what a
	-- camera resolves and only scatter, like fog). Real heavy rain holds hundreds of drops per
	-- cubic metre; the rings draw a fraction of a streak per cubic metre, most of them near.
	-- Thin streaks, wider than a real drop (1 to 5 mm) only where a pixel needs it. Lit by the
	-- scene and never glowing, with the look's rainColor as their albedo: at night they show
	-- in the light cones.
	RAIN = table.freeze({
		-- 7 m/s is near a heavy drop's terminal speed (6.3 m/s at 2 mm, 8.9 at 4 mm).
		fallSpeed = Units.metresToStuds(7),
		-- A light, constant lean from the wind (radians from vertical), and the way it blows
		-- (world yaw, radians from +Z toward +X). The same in every view, whatever the car does.
		lean = math.rad(4),
		windHeading = math.rad(30),
		-- A streak is the drop's fall over this exposure (s), at most maxLength (Rules/RainStreaks).
		exposure = 1 / 25,
		maxLength = Units.metresToStuds(0.5),
		-- Rate falls faster than intensity at the light end: RainRate = rate * I^1.15.
		rateExponent = 1.15,
		-- Streaks enter a ring's column through an inlet this many seconds of fall deep at its top
		-- and live until they reach the road (Rules/RainRings.column): a particle whose centre went
		-- under the ground would take the ground's lighting and draw dark (seen in Studio,
		-- 2026-10-28).
		inletSeconds = 0.08,
		-- A streak fades in over this first share of its life and out over this last share.
		fadeIn = 0.08,
		fadeOut = 0.15,
		-- On foot and in the chase view the rings start this far round the camera, where a drop is
		-- too close to be in focus; in the cockpit and hood views they start this far clear of the
		-- car's box. Either way the hole also reaches ahead as far as the camera travels in a
		-- streak's life, so none crosses the lens or the cabin (Rules/RainRings.hole).
		cameraHole = Units.metresToStuds(1.8),
		carMargin = Units.metresToStuds(0.4),
		-- In the car views the blocks behind the camera keep this share of their rate when still
		-- and fade out by this forward speed: the views look ahead, so the budget goes there.
		behindShare = 0.3,
		behindSpeed = Units.metresToStuds(15),
		-- In the car views the outer ring reaches this much further ahead, through the
		-- headlights' beams (60 studs, about 11 m, Roblox's longest).
		ahead = Units.metresToStuds(6),
		-- Nearest first; each ring starts where the one before it ends (or where the hole reaches,
		-- if further at speed). The near ring mixes in the pack's softer streak.
		rings = table.freeze({
			table.freeze({
				depth = Units.metresToStuds(2.5),
				height = Units.metresToStuds(4.5),
				density = 2,
				sampled = true,
				layer = table.freeze({
					sprites = table.freeze({
						table.freeze({ sprite = STREAK_FINE, share = 0.75 }),
						table.freeze({ sprite = STREAK_SOFT, share = 0.25 }),
					}),
					width = Units.metresToStuds(0.009),
					spread = 0.25,
					transparency = 0.35,
					transparencySpread = 0.2,
				}),
			}),
			table.freeze({
				depth = Units.metresToStuds(6),
				height = Units.metresToStuds(7),
				density = 0.5,
				sampled = false,
				layer = table.freeze({
					sprites = table.freeze({
						table.freeze({ sprite = STREAK_FINE, share = 0.85 }),
						table.freeze({ sprite = STREAK_SOFT, share = 0.15 }),
					}),
					width = Units.metresToStuds(0.006),
					spread = 0.25,
					transparency = 0.45,
					transparencySpread = 0.2,
				}),
			}),
		}),
		-- Only on a wet road. Larger and stronger than the brief's seeds (0.06 to 0.25 m, peak
		-- opacity 0.04 to 0.15): at those, the pack's thin ring lines were a tenth of a pixel from
		-- 2 m and nothing showed (edit-mode captures, 2026-10-28); 0.3 to 0.5 m at 0.5 first read.
		ripples = table.freeze({
			sprites = table.freeze({ RIPPLE_A, RIPPLE_B }),
			diameter = table.freeze({ Units.metresToStuds(0.15), Units.metresToStuds(0.4) }),
			lifetime = table.freeze({ 0.35, 0.75 }),
			opacity = 0.45,
			wetFrom = 0.35,
			maxSlope = math.rad(10),
			materials = table.freeze({ "Asphalt", "Concrete", "Pavement", "Slate", "Basalt" }),
		}),
		-- The ground under the camera is assumed this far below it when no ray finds it.
		groundFallback = Units.metresToStuds(1.7),
		-- The splash boxes move ahead of a moving camera by this many seconds of travel; a jump
		-- larger than teleportDistance in one frame resets the velocity estimate (respawn, camera
		-- swap).
		leadSeconds = 0.25,
		velocityHalfLife = 0.1,
		teleportDistance = Units.metresToStuds(20),
		-- Shelter: rays straight up from each block's sample points; anything within reach
		-- shelters that point. Refreshed this often (s), with rays down for the ground.
		shelterReach = Units.metresToStuds(40),
		shelterInterval = 0.3,
		-- Splashes: upright crowns played once from flat boxes just over the road ahead of
		-- the camera, a box's rate 0 under a roof. A crown's base sits on the particle's centre
		-- line, so the particle is twice the crown's height.
		splash = table.freeze({
			texture = "rbxassetid://105908704559116",
			size = table.freeze({ Units.metresToStuds(0.14), Units.metresToStuds(0.26) }),
			lifetime = table.freeze({ 0.12, 0.2 }),
			transparency = 0.4,
			color = rgb(178, 186, 198),
			cell = Units.metresToStuds(5),
			ahead = Units.metresToStuds(3),
			lift = Units.metresToStuds(0.05),
			maxSlope = math.rad(35),
			probeHeight = Units.metresToStuds(7),
		}),
	}),

	-- Rain visibility (Rules/RainHaze). 50 mm/h is very heavy rain; extinction about 3 per km
	-- there (contrast halves in about 230 m). The calibration is Atmosphere density against
	-- the extinction measured from black and white panels at 25 to 800 m, Offset 0.1, Haze 0,
	-- 2026-10-28; Haze 2.8 moved it by under 10 %, so the presets' haze still greys the sky.
	HAZE = table.freeze({
		fullRate = 50,
		extinction50 = 3,
		exponent = 0.67,
		takeOver = 0.3,
		calibration = table.freeze({
			table.freeze({ density = 0.15, extinction = 0.3 }),
			table.freeze({ density = 0.22, extinction = 1.2 }),
			table.freeze({ density = 0.3, extinction = 4.2 }),
			table.freeze({ density = 0.45, extinction = 18 }),
		}),
	}),

	-- Drops on the windscreen, from the pack's glass sprites: beads (glass_droplets_01) and the
	-- odd drop with its trail (_03). The brief's seeds: faint (ImageTransparency 0.85 to 0.95),
	-- most beads 4 to 12 px at 1080p, which from the eye about 0.7 m from the glass (some
	-- 1100 px per metre) is 4 to 11 mm. Drops slide down when slow; past about 46 km/h the air
	-- pulls them up the glass, as on a real windscreen (0.05 = 0.0003 * v^2 at 12.9 m/s).
	WINDSHIELD = table.freeze({
		bead = table.freeze({
			image = "rbxassetid://124603768450732",
			across = 0.375,
			width = table.freeze({ 0.004, 0.011 }),
			bead = 0.5,
		}),
		trail = table.freeze({
			image = "rbxassetid://106846008218344",
			across = 0.197,
			width = table.freeze({ 0.004, 0.007 }),
			bead = 0.68,
		}),
		opacity = 0.12,
		lightInfluence = 0.6,
		pixelsPerStud = 300,
		inset = 0.01,
		wipeSeconds = 0.15,
		drops = table.freeze({
			rate = 6,
			doubleAt = 60,
			maxRate = 30,
			exponent = 1.15,
			sliding = 0.3,
			cling = table.freeze({ 0.3, 1.5 }),
			gravity = 0.05,
			airflow = 0.0003,
			maxSlide = 0.25,
			life = table.freeze({ 2, 5 }),
			fadeOut = 0.3,
		}),
	}),

	-- Quality tiers from the player's saved graphics level: 1-3 Low, 4-7 Medium, 8-10 High.
	-- Automatic (0) is not a level, so it starts at Medium (auto-downgrade comes later).
	QUALITY_LEVELS = table.freeze({ low = 3, medium = 7 }),
	DEFAULT_TIER = DEFAULT_TIER,
	BUDGETS = BUDGETS,

	-- The Studio-only developer panel (never shown outside Studio, whatever this says), and the
	-- wetness values its capture override steps through.
	DEV_PANEL = true,
	OVERRIDE_STEPS = table.freeze({ 0.2, 0.5, 0.8 }),
	PANEL_REFRESH = 0.2,
})

return Atmosphere
