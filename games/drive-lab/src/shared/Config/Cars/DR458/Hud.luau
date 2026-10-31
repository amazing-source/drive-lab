--!strict
--[[
	The DR458's driving HUD (Config/HudDesign), from the owner's Ferrari-style design pack: a frame
	and a parts atlas cut by tools/assets/hud_pair_layers.py (docs/pipelines/DRIVING_HUD.md), boxes
	in the design's 2172 x 724 pixels. The gear and the speed are slanted Sarpanch Bold glyphs from
	the atlas, the drive mode upright Sarpanch Bold, the labels Michroma, as the binnacle.
]]
local HudDesign = require("../../HudDesign")

local function box(x0: number, y0: number, x1: number, y1: number): HudDesign.Box
	return table.freeze({ x0, y0, x1, y1 })
end

local function rgb(r: number, g: number, b: number)
	return table.freeze({ r = r, g = g, b = b })
end

local function part(rect: HudDesign.Box, at: HudDesign.Box): HudDesign.Part
	return table.freeze({ rect = rect, box = at })
end

local SEGMENT_TOP, SEGMENT_BOTTOM = 126, 226

local segments = {}
for index = 0, 9 do
	local left = 98 + 197 * index
	segments[index + 1] = box(left, SEGMENT_TOP, left + 181, SEGMENT_BOTTOM)
end

local Hud: HudDesign.Design = table.freeze({
	frameImage = "rbxassetid://110833890332396",
	partsImage = "rbxassetid://81481939805534",
	frameSize = table.freeze({ 2172, 724 }),
	partsSize = table.freeze({ 891, 635 }),
	segmentRect = box(452, 426, 181, 100),
	segments = table.freeze(segments),
	light = part(box(637, 426, 87, 64), box(2010, 614, 2097, 678)),
	modeIcon = part(box(330, 426, 118, 116), box(258, 389, 376, 505)),
	indicators = table.freeze({
		left = part(box(728, 426, 52, 62), box(43, 437, 95, 499)),
		right = part(box(784, 426, 52, 62), box(2077, 437, 2129, 499)),
	}),
	texts = table.freeze({
		mode = box(429, 392, 503, 500),
		tc = box(252, 571, 352, 614),
		tcLine = box(238, 642, 368, 646),
		abs = box(455, 571, 603, 615),
		absLine = box(449, 642, 611, 646),
		box = box(1064, 376, 1108, 415),
		-- Upright text, with no glyphs: the gear inside the hexagon at its lowest row, the speed's
		-- three digits clear of the hexagon and on the km/h baseline.
		gear = box(991, 439, 1181, 657),
		speed = box(1306, 473, 1720, 609),
	}),
	labelFace = table.freeze({
		family = "rbxasset://fonts/families/Michroma.json",
		weight = "Regular" :: "Regular",
		capHeight = 0.542,
		capOffset = 0.052,
	}),
	digitFace = table.freeze({
		family = "rbxasset://fonts/families/Sarpanch.json",
		weight = "Bold" :: "Bold",
		capHeight = 0.457,
		capOffset = 0.03,
	}),
	glyphs = table.freeze({
		rects = table.freeze({
			["0"] = box(0, 0, 175, 209),
			["1"] = box(179, 0, 175, 209),
			["2"] = box(358, 0, 175, 209),
			["3"] = box(537, 0, 175, 209),
			["4"] = box(716, 0, 175, 209),
			["5"] = box(0, 213, 175, 209),
			["6"] = box(179, 213, 175, 209),
			["7"] = box(358, 213, 175, 209),
			["8"] = box(537, 213, 175, 209),
			["9"] = box(716, 213, 175, 209),
			N = box(0, 426, 161, 209),
			R = box(165, 426, 161, 209),
		}),
		height = 205,
		pad = 2,
		advance = 139.99,
		-- The speed on the km/h baseline, its right edge the drawn digit's, its left reaching no
		-- nearer than 29 px to the hexagon's corner; the gear between the hexagon's inner edges at
		-- the drawn digit's lowest row.
		speed = box(1289, 404, 1740, 609),
		gear = box(991, 439, 1181, 657),
	}),
	colours = table.freeze({
		lit = rgb(243, 244, 242),
		text = rgb(243, 244, 242),
		redline = rgb(217, 47, 60),
		flash = rgb(61, 123, 255),
		-- The SVJ HUD's contrast against its panel (2.60 and 1.87), in the design's blue grey.
		ready = rgb(78, 85, 94),
		readyLine = rgb(58, 64, 70),
		unlit = rgb(53, 58, 64),
		lamp = rgb(0, 216, 55),
	}),
})

return Hud
