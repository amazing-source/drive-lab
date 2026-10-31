--!strict
--[[
	What the HUD of a car looks like, for Ui/HudView: the car's own design (Config/HudDesign) with
	its colours and fonts made into the engine's types once, or, for a car without one, the global
	HUD's values from Config/Hud as they are.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage.Shared.Config.Cars.Catalog)
local Cluster = require(ReplicatedStorage.Shared.Config.Cluster)
local Config = require(ReplicatedStorage.Shared.Config.Hud)
local HudDesign = require(ReplicatedStorage.Shared.Config.HudDesign)

local MONTSERRAT = "rbxasset://fonts/families/Montserrat.json"

local WEIGHTS: { [string]: Enum.FontWeight } = {
	Regular = Enum.FontWeight.Regular,
	Bold = Enum.FontWeight.Bold,
}

export type Box = { number }

export type Part = HudDesign.Part

export type Face = { font: Font, capHeight: number, capOffset: number }

export type Colours = {
	lit: Color3,
	text: Color3,
	redline: Color3,
	flash: Color3,
	ready: Color3,
	readyLine: Color3,
	unlit: Color3,
	lamp: Color3,
}

export type Look = {
	frameImage: string,
	partsImage: string,
	frameSize: Vector2,
	segments: { Box },
	-- Each segment's mask in the atlas.
	segmentRects: { Box },
	light: Part,
	modeIcon: Part?,
	-- Where the indicators are drawn; with masks, at all times and unlit while off, else as arrows
	-- shown only while they blink.
	indicators: { left: Box, right: Box, masks: { left: Box, right: Box }? }?,
	texts: {
		mode: Box,
		tc: Box,
		tcLine: Box,
		abs: Box,
		absLine: Box,
		box: Box,
		gear: Box,
		speed: Box,
	},
	label: Face,
	digits: Face,
	mode: Face,
	glyphs: HudDesign.Glyphs?,
	colours: Colours,
}

local function globalLook(): Look
	local parts, readouts = Config.PARTS, Config.READOUTS
	local segmentRects = {}
	for index in Config.SEGMENTS do
		segmentRects[index] = if index == 1
			then parts.first
			elseif index == #Config.SEGMENTS then parts.last
			else parts.middle
	end
	local label = {
		font = Font.new(MONTSERRAT, Enum.FontWeight.SemiBold),
		capHeight = Config.CAP_HEIGHT,
		capOffset = 0,
	}
	return {
		frameImage = Config.FRAME_IMAGE,
		partsImage = Config.PARTS_IMAGE,
		frameSize = Config.FRAME_SIZE,
		segments = Config.SEGMENTS,
		segmentRects = segmentRects,
		light = { rect = parts.light, box = readouts.light },
		modeIcon = nil,
		indicators = { left = readouts.indicatorLeft, right = readouts.indicatorRight, masks = nil },
		texts = {
			mode = readouts.mode,
			tc = readouts.tcText,
			tcLine = readouts.tcLine,
			abs = readouts.absText,
			absLine = readouts.absLine,
			box = readouts.box,
			gear = readouts.gear,
			speed = readouts.speed,
		},
		label = label,
		digits = {
			font = Font.new(MONTSERRAT, Enum.FontWeight.Heavy, Enum.FontStyle.Italic),
			capHeight = Config.CAP_HEIGHT,
			capOffset = 0,
		},
		mode = label,
		glyphs = nil,
		colours = {
			lit = Config.YELLOW,
			text = Config.WHITE,
			redline = Config.RED,
			flash = Config.BLUE,
			ready = Config.GREY,
			readyLine = Config.LINE_GREY,
			unlit = Config.OFF,
			lamp = Config.GREEN,
		},
	}
end

local function colour(rgb: Cluster.Rgb): Color3
	return Color3.fromRGB(rgb.r, rgb.g, rgb.b)
end

local function face(design: HudDesign.Face): Face
	return {
		font = Font.new(design.family, WEIGHTS[design.weight]),
		capHeight = design.capHeight,
		capOffset = design.capOffset,
	}
end

local function designLook(design: HudDesign.Design): Look
	local colours = design.colours
	local indicators = design.indicators
	local digits = face(design.digitFace)
	return {
		frameImage = design.frameImage,
		partsImage = design.partsImage,
		frameSize = Vector2.new(design.frameSize[1], design.frameSize[2]),
		segments = design.segments,
		segmentRects = table.create(#design.segments, design.segmentRect),
		light = design.light,
		modeIcon = design.modeIcon,
		indicators = if indicators
			then {
				left = indicators.left.box,
				right = indicators.right.box,
				masks = { left = indicators.left.rect, right = indicators.right.rect },
			}
			else nil,
		texts = design.texts,
		label = face(design.labelFace),
		digits = digits,
		mode = digits,
		glyphs = design.glyphs,
		colours = {
			lit = colour(colours.lit),
			text = colour(colours.text),
			redline = colour(colours.redline),
			flash = colour(colours.flash),
			ready = colour(colours.ready),
			readyLine = colour(colours.readyLine),
			unlit = colour(colours.unlit),
			lamp = colour(colours.lamp),
		},
	}
end

local HudLook = {}

local global: Look? = nil
local byDesign: { [HudDesign.Design]: Look } = {}

-- The look of the car `entry`'s HUD: its own design's, or the global HUD's. One look per design.
function HudLook.of(entry: Catalog.Entry): Look
	local design = entry.hud
	if design == nil then
		local look = global or globalLook()
		global = look
		return look
	end
	local look = byDesign[design] or designLook(design)
	byDesign[design] = look
	return look
end

return HudLook
