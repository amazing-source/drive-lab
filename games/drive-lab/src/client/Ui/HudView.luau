--!strict
--[[
	The driving HUD drawn from a look (Ui/HudLook): the frame image with the live parts over it at
	the look's boxes, sized with the frame. `build` makes it once per look, `place` puts it on the
	screen, `show` draws a set of readouts. Controllers/Hud works the readouts out from the car.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config.Hud)
local DriverAssists = require(ReplicatedStorage.Shared.Rules.DriverAssists)
local HudLook = require(script.Parent.HudLook)
local Rules = require(ReplicatedStorage.Shared.Rules.Hud)

local SOLID = NumberSequence.new(0)

export type Light = "Off" | "Dipped" | "High"

export type Readouts = {
	rpm: number,
	redline: number,
	-- The lit segments and the gear flash for the upshift (Rules/Hud.shiftFlash).
	flash: boolean,
	manual: boolean,
	gear: string,
	speed: string,
	mode: string,
	tc: DriverAssists.Telltale,
	abs: DriverAssists.Telltale,
	light: Light,
	left: boolean,
	right: boolean,
}

type Box = HudLook.Box

type Text = { label: TextLabel, scale: UIScale, box: Box, face: HudLook.Face, x: number, y: number }

type Segment = { image: ImageLabel, gradient: UIGradient, zone: ColorSequence }

-- The gear or the speed: a text, or glyph sprites laid out again each time it changes.
type Numeral = {
	label: TextLabel?,
	holder: GuiObject,
	images: { ImageLabel },
	box: Box,
	align: Rules.Align,
	shown: string,
}

export type View = {
	look: HudLook.Look,
	gui: ScreenGui,
	frame: ImageLabel,
	segments: { Segment },
	mode: TextLabel,
	tc: TextLabel,
	tcLine: Frame,
	abs: TextLabel,
	absLine: Frame,
	box: TextLabel,
	gear: Numeral,
	gearPop: UIScale,
	speed: Numeral,
	light: ImageLabel,
	-- The indicators: masks drawn at all times, unlit while off, or arrows shown while they blink.
	lamps: { left: ImageLabel, right: ImageLabel }?,
	arrows: { left: TextLabel, right: TextLabel }?,
	flashColour: ColorSequence,
	flashing: boolean,
	-- The redline the segments' zones were drawn for: the driven car's.
	redline: number,
	lastGear: string,
}

local function share(look: HudLook.Look, x: number, y: number): UDim2
	return UDim2.fromScale(x / look.frameSize.X, y / look.frameSize.Y)
end

local function place(look: HudLook.Look, item: GuiObject, box: Box)
	item.Position = share(look, box[1], box[2])
	item.Size = share(look, box[3] - box[1], box[4] - box[2])
end

local function part(look: HudLook.Look, parent: Instance, rect: Box, box: Box): ImageLabel
	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.Image = look.partsImage
	image.ImageRectOffset = Vector2.new(rect[1], rect[2])
	image.ImageRectSize = Vector2.new(rect[3], rect[4])
	place(look, image, box)
	image.Parent = parent
	return image
end

local function bar(look: HudLook.Look, parent: Instance, box: Box): Frame
	local line = Instance.new("Frame")
	line.BorderSizePixel = 0
	place(look, line, box)
	line.Parent = parent
	return line
end

-- A tell-tale's text and line: grey while ready, lit while it acts, red while switched off.
local function paint(colours: HudLook.Colours, label: TextLabel, line: Frame, state: DriverAssists.Telltale)
	label.TextColor3 = if state == "Acting"
		then colours.lit
		elseif state == "Off" then colours.redline
		else colours.ready
	line.BackgroundColor3 = if state == "Acting"
		then colours.lit
		elseif state == "Off" then colours.redline
		else colours.readyLine
end

-- The segment's colour along its length: lit, then red from where the redline falls in it.
local function zone(colours: HudLook.Colours, redline: number, index: number): ColorSequence
	local red = Rules.segmentShare(redline, index, Config.RPM_PER_SEGMENT)
	if red >= 1 then
		return ColorSequence.new(colours.lit)
	elseif red <= 0 then
		return ColorSequence.new(colours.redline)
	end
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, colours.lit),
		ColorSequenceKeypoint.new(red, colours.lit),
		ColorSequenceKeypoint.new(red + 0.002, colours.redline),
		ColorSequenceKeypoint.new(1, colours.redline),
	})
end

-- A hard edge `lit` of the way across a segment: shown to its left, clear to its right.
local function edge(lit: number): NumberSequence
	local at = math.min(lit, 0.996)
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(at, 0),
		NumberSequenceKeypoint.new(at + 0.002, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
end

-- Sizes each text so its capitals fill its box's height. TextSize stops at 100, so a larger
-- size is set smaller and scaled up.
local function fit(look: HudLook.Look, texts: { Text }, frameHeight: number)
	local pixel = frameHeight / look.frameSize.Y
	for _, entry in texts do
		local box, face = entry.box, entry.face
		local size = (box[4] - box[2]) * pixel / face.capHeight
		local scale = math.max(1, size / 100)
		entry.label.TextSize = size / scale
		entry.scale.Scale = scale
		entry.label.Size =
			UDim2.fromOffset((box[3] - box[1]) * pixel / scale, (box[4] - box[2]) * pixel / scale)
		if face.capOffset ~= 0 then
			entry.label.Position = UDim2.new(entry.x, 0, entry.y, -face.capOffset * size)
		end
	end
end

local function glyphImage(look: HudLook.Look, holder: GuiObject): ImageLabel
	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.Image = look.partsImage
	image.ImageColor3 = look.colours.text
	image.Parent = holder
	return image
end

-- Lays the numeral's glyphs out for `text`, one sprite per character, reusing its images.
local function layout(look: HudLook.Look, numeral: Numeral, text: string)
	local glyphs = assert(look.glyphs, "a numeral drawn as glyphs needs the look's glyphs")
	local boxes = Rules.glyphBoxes(text, glyphs, numeral.box, numeral.align)
	local drawn = 0
	for index = 1, #text do
		local rect = glyphs.rects[string.sub(text, index, index)]
		if rect then
			drawn += 1
			local image = numeral.images[drawn] or glyphImage(look, numeral.holder)
			numeral.images[drawn] = image
			image.ImageRectOffset = Vector2.new(rect[1], rect[2])
			image.ImageRectSize = Vector2.new(rect[3], rect[4])
			place(look, image, boxes[drawn])
			image.Visible = true
		end
	end
	for index = drawn + 1, #numeral.images do
		numeral.images[index].Visible = false
	end
	numeral.shown = text
end

local function setNumeral(look: HudLook.Look, numeral: Numeral, text: string)
	local label = numeral.label
	if label then
		label.Text = text
	elseif text ~= numeral.shown then
		layout(look, numeral, text)
	end
end

local function tintNumeral(numeral: Numeral, colour: Color3)
	local label = numeral.label
	if label then
		label.TextColor3 = colour
		return
	end
	for _, image in numeral.images do
		image.ImageColor3 = colour
	end
end

local HudView = {}

function HudView.build(parent: Instance, look: HudLook.Look, name: string): View
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 5
	gui.Enabled = false

	local frame = Instance.new("ImageLabel")
	frame.Name = "Frame"
	frame.BackgroundTransparency = 1
	frame.Image = look.frameImage
	if look.frameTransparency > 0 then
		frame.ImageTransparency = look.frameTransparency
	end
	frame.Parent = gui
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = look.frameSize.X / look.frameSize.Y
	aspect.Parent = frame

	local colours = look.colours
	local segments = {}
	for index, box in look.segments do
		local image = part(look, frame, look.segmentRects[index], box)
		image.Visible = false
		local gradient = Instance.new("UIGradient")
		-- No car yet: all lit, redrawn for the car on its first refresh.
		local colors = zone(colours, math.huge, index)
		gradient.Color = colors
		gradient.Parent = image
		segments[index] = { image = image, gradient = gradient, zone = colors }
	end

	local texts: { Text } = {}
	local function text(
		holder: Instance,
		box: Box,
		face: HudLook.Face,
		align: Enum.TextXAlignment,
		color: Color3
	): TextLabel
		local anchorX = if align == Enum.TextXAlignment.Left
			then 0
			elseif align == Enum.TextXAlignment.Right then 1
			else 0.5
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.FontFace = face.font
		label.TextColor3 = color
		label.TextXAlignment = align
		label.AnchorPoint = Vector2.new(anchorX, 0.5)
		local x = (box[1] + (box[3] - box[1]) * anchorX) / look.frameSize.X
		local y = (box[2] + box[4]) / 2 / look.frameSize.Y
		label.Position = UDim2.fromScale(x, y)
		label.Parent = holder
		local scale = Instance.new("UIScale")
		scale.Parent = label
		table.insert(texts, { label = label, scale = scale, box = box, face = face, x = x, y = y })
		return label
	end

	-- The gear sits in a frame-sized holder anchored on its centre, so it pops about its middle.
	local glyphs = look.glyphs
	local readouts = look.texts
	local gearBox = if glyphs then glyphs.gear else readouts.gear
	local centre = Vector2.new(gearBox[1] + gearBox[3], gearBox[2] + gearBox[4]) / 2 / look.frameSize
	local gearHolder = Instance.new("Frame")
	gearHolder.BackgroundTransparency = 1
	gearHolder.Size = UDim2.fromScale(1, 1)
	gearHolder.AnchorPoint = centre
	gearHolder.Position = UDim2.fromScale(centre.X, centre.Y)
	gearHolder.Parent = frame
	local gearPop = Instance.new("UIScale")
	gearPop.Parent = gearHolder

	local function numeral(
		holder: GuiObject,
		box: Box,
		align: Rules.Align,
		textAlign: Enum.TextXAlignment
	): Numeral
		if glyphs then
			return { label = nil, holder = holder, images = {}, box = box, align = align, shown = "" }
		end
		local label = text(holder, box, look.digits, textAlign, colours.text)
		return { label = label, holder = holder, images = {}, box = box, align = align, shown = "" }
	end

	local function arrow(box: Box, glyph: string): TextLabel
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Text = glyph
		label.TextScaled = true
		label.TextColor3 = colours.lamp
		label.Visible = false
		place(look, label, box)
		label.Parent = frame
		return label
	end

	local light = part(look, frame, look.light.rect, look.light.box)
	light.ImageColor3 = colours.unlit
	local modeIcon = look.modeIcon
	if modeIcon then
		part(look, frame, modeIcon.rect, modeIcon.box).ImageColor3 = colours.text
	end
	local mode = text(frame, readouts.mode, look.mode, Enum.TextXAlignment.Left, colours.lit)
	local tc = text(frame, readouts.tc, look.label, Enum.TextXAlignment.Center, colours.ready)
	local tcLine = bar(look, frame, readouts.tcLine)
	local abs = text(frame, readouts.abs, look.label, Enum.TextXAlignment.Center, colours.ready)
	local absLine = bar(look, frame, readouts.absLine)
	local box = text(frame, readouts.box, look.label, Enum.TextXAlignment.Center, colours.text)
	local gear = numeral(gearHolder, gearBox, "Center", Enum.TextXAlignment.Center)
	local speed =
		numeral(frame, if glyphs then glyphs.speed else readouts.speed, "Right", Enum.TextXAlignment.Right)

	local indicators = look.indicators
	local masks = indicators and indicators.masks
	local lamps, arrows = nil, nil
	if indicators and masks then
		lamps = {
			left = part(look, frame, masks.left, indicators.left),
			right = part(look, frame, masks.right, indicators.right),
		}
		lamps.left.ImageColor3 = colours.unlit
		lamps.right.ImageColor3 = colours.unlit
	elseif indicators then
		arrows = { left = arrow(indicators.left, "◀"), right = arrow(indicators.right, "▶") }
	end

	local view: View = {
		look = look,
		gui = gui,
		frame = frame,
		segments = segments,
		mode = mode,
		tc = tc,
		tcLine = tcLine,
		abs = abs,
		absLine = absLine,
		box = box,
		gear = gear,
		gearPop = gearPop,
		speed = speed,
		light = light,
		lamps = lamps,
		arrows = arrows,
		flashColour = ColorSequence.new(colours.flash),
		flashing = false,
		redline = math.huge,
		lastGear = "",
	}
	tc.Text = "TC"
	abs.Text = "ABS"

	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		fit(look, texts, frame.AbsoluteSize.Y)
	end)
	gui.Parent = parent
	fit(look, texts, frame.AbsoluteSize.Y)
	return view
end

-- Bottom centre, or bottom right and smaller in the cockpit, where the centre is the wheel and
-- the hands; the minimal mode is the same, smaller. Every look is sized to its width share of the
-- global HUD's width in that view, its height following its frame's shape.
function HudView.place(view: View, cockpit: boolean, minimal: boolean)
	local look = view.look
	local height = Rules.frameHeight(
		(if cockpit then Config.COCKPIT_HEIGHT else Config.HEIGHT)
			* (if minimal then Config.MINIMAL_SCALE else 1),
		look.width,
		look.frameSize.X / look.frameSize.Y,
		Config.FRAME_SIZE.X / Config.FRAME_SIZE.Y
	)
	local frame = view.frame
	frame.Size = UDim2.fromScale(Config.MAX_WIDTH, height)
	frame.AnchorPoint = if cockpit then Vector2.new(1, 1) else Vector2.new(0.5, 1)
	frame.Position = if cockpit
		then UDim2.new(1, -Config.MARGIN, 1, -Config.MARGIN)
		else UDim2.new(0.5, 0, 1, -Config.MARGIN)
end

function HudView.show(view: View, readouts: Readouts)
	local look = view.look
	local colours = look.colours
	if readouts.redline ~= view.redline then
		view.redline = readouts.redline
		for index, segment in view.segments do
			segment.zone = zone(colours, readouts.redline, index)
			if not view.flashing then
				segment.gradient.Color = segment.zone
			end
		end
	end
	local flash = readouts.flash
	for index, segment in view.segments do
		local lit = Rules.segmentShare(readouts.rpm, index, Config.RPM_PER_SEGMENT)
		segment.image.Visible = lit > 0
		if lit > 0 then
			segment.gradient.Transparency = if lit >= 1 then SOLID else edge(lit)
		end
		if flash ~= view.flashing then
			segment.gradient.Color = if flash then view.flashColour else segment.zone
		end
	end
	view.flashing = flash

	if readouts.gear ~= view.lastGear then
		view.lastGear = readouts.gear
		setNumeral(look, view.gear, readouts.gear)
		view.gearPop.Scale = 1.18
		TweenService:Create(view.gearPop, TweenInfo.new(Config.GEAR_POP), { Scale = 1 }):Play()
	end
	tintNumeral(view.gear, if flash then colours.flash else colours.text)
	view.box.Text = if readouts.manual then "M" else "A"
	setNumeral(look, view.speed, readouts.speed)
	view.mode.Text = readouts.mode
	paint(colours, view.tc, view.tcLine, readouts.tc)
	paint(colours, view.abs, view.absLine, readouts.abs)
	-- Blue for the high beam, as a car's own tell-tale; green for the dipped beam.
	view.light.ImageColor3 = if readouts.light == "High"
		then colours.flash
		elseif readouts.light == "Dipped" then colours.lamp
		else colours.unlit
	local lamps, arrows = view.lamps, view.arrows
	if lamps then
		lamps.left.ImageColor3 = if readouts.left then colours.lamp else colours.unlit
		lamps.right.ImageColor3 = if readouts.right then colours.lamp else colours.unlit
	elseif arrows then
		arrows.left.Visible = readouts.left
		arrows.right.Visible = readouts.right
	end
end

return HudView
