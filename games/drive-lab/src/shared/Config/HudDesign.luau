--!strict
--[[
	A car's own driving HUD (its Contract entry's `hud`), as plain data so Lune loads it; a car
	without one shows Config/Hud's. Boxes are { x0, y0, x1, y1 } in the frame's pixels before its
	upload at 1024 wide; rects are { x, y, width, height } in the parts atlas, whose white masks the
	game tints. tools/assets/hud_pair_layers.py cuts a design into both and prints every box.
]]
local Cluster = require("./Cluster")
local Rules = require("../Rules/Hud")

export type Box = { number }

-- A mask in the atlas and where it is drawn, at the same size.
export type Part = { rect: Box, box: Box }

export type Face = {
	family: string,
	weight: "Regular" | "Bold",
	-- The capitals' height, and how far their middle sits below the middle of the label's box,
	-- as shares of the TextSize.
	capHeight: number,
	capOffset: number,
}

-- Slanted numerals drawn as sprites, for faces with no italic (Rules/Hud.Glyphs), and the speed's
-- and the gear's boxes, capitals to baseline, the speed's right edge at the top of its last digit.
export type Glyphs = Rules.Glyphs & {
	speed: Box,
	gear: Box,
}

export type Colours = {
	-- A lit rev segment below the redline, the drive mode, TC or ABS while it acts.
	lit: Cluster.Rgb,
	-- The gear, the speed, A or M, the mode pictogram.
	text: Cluster.Rgb,
	-- The red zone, and TC or ABS switched off.
	redline: Cluster.Rgb,
	-- The upshift flash and the high beam.
	flash: Cluster.Rgb,
	-- TC and ABS ready, text and line.
	ready: Cluster.Rgb,
	readyLine: Cluster.Rgb,
	-- The headlight tell-tale and the indicators while off.
	unlit: Cluster.Rgb,
	-- The dipped beam and the indicators while they blink.
	lamp: Cluster.Rgb,
}

export type Design = {
	frameImage: string,
	partsImage: string,
	frameSize: { number },
	partsSize: { number },
	-- Every rev segment is this one mask, drawn at each box.
	segmentRect: Box,
	segments: { Box },
	light: Part,
	modeIcon: Part?,
	-- Drawn at all times, unlit while off; without them the indicators show only while they blink.
	indicators: { left: Part, right: Part }?,
	-- Each live text's glyph outline: text is sized so its capitals fill the box's height.
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
	-- A or M, TC and ABS.
	labelFace: Face,
	-- The drive mode, and the gear and the speed when there are no glyphs.
	digitFace: Face,
	glyphs: Glyphs?,
	colours: Colours,
	-- Its width on screen, as a share of the global HUD's in the same view: the height follows
	-- from the frame's shape. 1 when left out.
	width: number?,
	-- How see-through the frame image is, panel and lettering alike, 0 to under 1; 0 when left out.
	frameTransparency: number?,
}

local HudDesign = {}

-- The rev bar: ten segments of a thousand rpm from 0, as on the global HUD.
HudDesign.SEGMENTS = 10

-- What the gear and the speed can show: Rules/Cluster.gearLabel and a whole number of km/h.
HudDesign.GLYPHS = "0123456789NR"
HudDesign.GEARS = "NR1234567"
HudDesign.SPEED_DIGITS = 3

local function inside(box: Box, size: { number }): boolean
	return 0 <= box[1]
		and box[1] < box[3]
		and box[3] <= size[1]
		and 0 <= box[2]
		and box[2] < box[4]
		and box[4] <= size[2]
end

local function inAtlas(rect: Box, size: { number }): boolean
	return rect[1] >= 0
		and rect[2] >= 0
		and rect[3] > 0
		and rect[4] > 0
		and rect[1] + rect[3] <= size[1]
		and rect[2] + rect[4] <= size[2]
end

local function uploaded(image: string): boolean
	return string.match(image, "^rbxassetid://[1-9]%d*$") ~= nil
end

local function channel(value: number): boolean
	return value >= 0 and value <= 255 and value % 1 == 0
end

local function checkPart(part: Part, name: string, design: Design)
	assert(inAtlas(part.rect, design.partsSize), `the HUD's {name} mask lies outside its atlas`)
	assert(inside(part.box, design.frameSize), `the HUD's {name} lies outside its frame`)
	assert(
		part.box[3] - part.box[1] == part.rect[3] and part.box[4] - part.box[2] == part.rect[4],
		`the HUD's {name} is drawn at another size than its mask`
	)
end

-- Every glyph is there, the digits share one width so the speed does not shift as it changes,
-- the speed's digits fit its box, and every gear fits the gear's.
local function checkGlyphs(glyphs: Glyphs, design: Design)
	local digitWidth = glyphs.rects["0"] and glyphs.rects["0"][3]
	for index = 1, #HudDesign.GLYPHS do
		local char = string.sub(HudDesign.GLYPHS, index, index)
		local rect = glyphs.rects[char]
		assert(rect, `the HUD has no glyph for {char}`)
		assert(inAtlas(rect, design.partsSize), `the HUD's glyph {char} lies outside its atlas`)
		assert(rect[4] == glyphs.height + 2 * glyphs.pad, `the HUD's glyph {char} is not its glyphs' height`)
		assert(
			string.match(char, "%a") or rect[3] == digitWidth,
			`the HUD's digit {char} is not as wide as the others`
		)
	end
	local speed, gear = glyphs.speed, glyphs.gear
	assert(inside(speed, design.frameSize), "the HUD's speed digits lie outside its frame")
	assert(inside(gear, design.frameSize), "the HUD's gear glyph lies outside its frame")
	local widest = string.rep("8", HudDesign.SPEED_DIGITS)
	assert(
		Rules.glyphRunLeft(widest, glyphs, speed, "Right") >= speed[1],
		`the HUD's speed box does not hold {HudDesign.SPEED_DIGITS} digits`
	)
	local pad = glyphs.pad * (gear[4] - gear[2]) / glyphs.height
	for index = 1, #HudDesign.GEARS do
		local char = string.sub(HudDesign.GEARS, index, index)
		local drawn = Rules.glyphBoxes(char, glyphs, gear, "Center")[1]
		assert(
			drawn[1] + pad >= gear[1] and drawn[3] - pad <= gear[3],
			`the HUD's gear {char} is wider than its box`
		)
	end
end

-- A car's HUD is drawn from uploaded images, has the rev bar's segments, and puts every box in
-- its frame and every mask in its atlas, drawn at the mask's own size.
function HudDesign.check(design: Design)
	assert(
		uploaded(design.frameImage) and uploaded(design.partsImage),
		"the HUD's images are not uploaded assets"
	)
	assert(
		#design.segments == HudDesign.SEGMENTS,
		`the HUD has {#design.segments} rev segments, not {HudDesign.SEGMENTS}`
	)
	assert(design.width == nil or design.width > 0, "the HUD's width is not a positive share")
	local transparency = design.frameTransparency
	assert(
		transparency == nil or (transparency >= 0 and transparency < 1),
		"the HUD's frame transparency is not 0 to under 1"
	)
	local segmentRect = design.segmentRect
	for index, box in design.segments do
		checkPart({ rect = segmentRect, box = box }, `rev segment {index}`, design)
	end
	checkPart(design.light, "headlight", design)
	if design.modeIcon then
		checkPart(design.modeIcon, "mode pictogram", design)
	end
	local indicators = design.indicators
	if indicators then
		checkPart(indicators.left, "left indicator", design)
		checkPart(indicators.right, "right indicator", design)
	end
	local texts = design.texts
	local boxes: { [string]: Box } = {
		mode = texts.mode,
		tc = texts.tc,
		tcLine = texts.tcLine,
		abs = texts.abs,
		absLine = texts.absLine,
		box = texts.box,
		gear = texts.gear,
		speed = texts.speed,
	}
	for name, box in boxes do
		assert(inside(box, design.frameSize), `the HUD's {name} lies outside its frame`)
	end
	local colours = design.colours
	local rgbs: { [string]: Cluster.Rgb } = {
		lit = colours.lit,
		text = colours.text,
		redline = colours.redline,
		flash = colours.flash,
		ready = colours.ready,
		readyLine = colours.readyLine,
		unlit = colours.unlit,
		lamp = colours.lamp,
	}
	for name, rgb in rgbs do
		assert(
			channel(rgb.r) and channel(rgb.g) and channel(rgb.b),
			`the HUD's {name} colour is not 0 to 255`
		)
	end
	for _, face in { design.labelFace, design.digitFace } do
		assert(face.capHeight > 0 and face.capHeight < 1, `the HUD's {face.family} capitals are not a share`)
	end
	if design.glyphs then
		checkGlyphs(design.glyphs, design)
	end
end

return table.freeze(HudDesign)
