--!strict
--[[
	Draws a binnacle display (Config/Binnacle). On the screen part: each page's design image,
	centred at full height with the sides in its edge colours, and over it the live values, the
	pills and the lit rpm segments. On each lens of the strip: that lamp's image, lit or not.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Binnacle = require(ReplicatedStorage.Shared.Config.Binnacle)
local Cluster = require(ReplicatedStorage.Shared.Config.Cluster)
local Log = require(ReplicatedStorage.Kit.Log)
local Rules = require(ReplicatedStorage.Shared.Rules.Binnacle)

export type State = {
	-- Off before the car's start-up: the screen is dark and every lamp unlit.
	on: boolean,
	readout: Rules.Readout,
	page: number,
	lamps: Rules.Lamps,
	now: number,
}

type Value = { field: Binnacle.Field, text: TextLabel, pill: ImageLabel? }

type PageView = {
	page: Binnacle.Page,
	image: ImageLabel,
	values: { Value },
	segments: { ImageLabel },
	lit: number,
}

export type View = {
	gui: SurfaceGui,
	screen: Binnacle.Screen,
	background: Frame,
	title: Frame,
	pages: { PageView },
	lenses: { [number]: ImageLabel },
	lensGuis: { SurfaceGui },
	shown: PageView?,
}

local MAX_TEXT_SIZE = 100
local LENS_CANVAS = 64
local WHITE = Color3.new(1, 1, 1)
local WEIGHTS: { [string]: Enum.FontWeight } = {
	Regular = Enum.FontWeight.Regular,
	Medium = Enum.FontWeight.Medium,
	SemiBold = Enum.FontWeight.SemiBold,
	Bold = Enum.FontWeight.Bold,
}
local FACES: { [string]: Enum.NormalId } = {
	Front = Enum.NormalId.Front,
	Back = Enum.NormalId.Back,
	Left = Enum.NormalId.Left,
	Right = Enum.NormalId.Right,
	Top = Enum.NormalId.Top,
	Bottom = Enum.NormalId.Bottom,
}

local log = Log.scope("BinnacleView")

local BinnacleView = {}

local function colour(value: Cluster.Rgb): Color3
	return Color3.fromRGB(value.r, value.g, value.b)
end

local function place(object: GuiObject, rect: Binnacle.Rect)
	object.Position = UDim2.fromScale(rect.x, rect.y)
	object.Size = UDim2.fromScale(rect.width, rect.height)
end

local function setSprite(label: ImageLabel, sprite: Binnacle.Sprite)
	label.Image = sprite.image
	label.ImageRectOffset = Vector2.new(sprite.x, sprite.y)
	label.ImageRectSize = Vector2.new(sprite.width, sprite.height)
end

local function image(name: string, sprite: Binnacle.Sprite, zIndex: number): ImageLabel
	local label = Instance.new("ImageLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.ZIndex = zIndex
	setSprite(label, sprite)
	return label
end

-- A value's text, sized so its capitals and their outline fill the slot's height, centred in the
-- slot. TextSize stops at 100, so a larger size is set smaller and scaled up.
local function text(
	holder: ImageLabel,
	slot: Binnacle.Rect,
	page: Vector2,
	font: Binnacle.Font,
	rgb: Cluster.Rgb
): TextLabel
	local capitals = slot.height * page.Y / (1 + 2 * font.stroke)
	local size = capitals / font.capHeight
	local scale = math.max(1, size / MAX_TEXT_SIZE)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.ZIndex = 3
	label.FontFace = Font.new(font.family, WEIGHTS[font.weight])
	label.TextSize = size / scale
	label.TextColor3 = colour(rgb)
	label.Text = ""
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.new(slot.x + slot.width / 2, 0, slot.y + slot.height / 2, -font.capOffset * size)
	label.Size = UDim2.fromOffset(slot.width * page.X / scale, size / scale)
	if font.stroke > 0 then
		local outline = Instance.new("UIStroke")
		outline.Color = label.TextColor3
		outline.LineJoinMode = Enum.LineJoinMode.Miter
		outline.Thickness = font.stroke * capitals / scale
		outline.Parent = label
	end
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = scale
	uiScale.Parent = label
	label.Parent = holder
	return label
end

local function buildPage(view: View, page: Binnacle.Page, index: number, fit: Binnacle.Rect): PageView
	local screen, art = view.screen, page.art
	local holder = image(`Page{index}`, art.art, 1)
	place(holder, fit)
	holder.Visible = false
	local pageView: PageView = { page = page, image = holder, values = {}, segments = {}, lit = 0 }
	local band = art.band
	if band then
		for segmentIndex, segment in band.segments do
			local lit = image(`Segment{segmentIndex}`, segment.sprite, 2)
			place(lit, segment.rect)
			lit.ImageColor3 = colour(band.rgb)
			lit.Visible = false
			lit.Parent = holder
			pageView.segments[segmentIndex] = lit
		end
	end
	local pixels = Vector2.new(screen.canvasWidth * fit.width, screen.canvasHeight * fit.height)
	for _, field in page.fields do
		local pillArt = art.pills and art.pills[field.label]
		local pill: ImageLabel? = nil
		if field.pill and pillArt then
			local shape = image(`{field.label} pill`, pillArt.sprite, 2)
			place(shape, pillArt.rect)
			shape.Parent = holder
			pill = shape
		end
		local rgb = if pill then screen.pillTextRgb else screen.valueRgb
		local label = text(holder, art.slots[field.label], pixels, screen.font, rgb)
		label.Name = field.label
		table.insert(pageView.values, { field = field, text = label, pill = pill })
	end
	holder.Parent = view.background
	return pageView
end

local function buildLenses(view: View, model: Model)
	local screen = view.screen
	for index, name in screen.lenses do
		local part = model:FindFirstChild(name, true)
		if part == nil or not part:IsA("BasePart") then
			log.warn(`{model:GetFullName()} has no lens {name}; its shift lamp is not drawn`)
			continue
		end
		local gui = Instance.new("SurfaceGui")
		gui.Name = "LiveLamp"
		gui.Face = FACES[screen.lensFace]
		gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		gui.CanvasSize = Vector2.new(LENS_CANVAS, LENS_CANVAS)
		gui.LightInfluence = 0
		gui.Brightness = screen.brightness
		local lamp = image("Lamp", screen.lamps.off[index], 1)
		lamp.Size = UDim2.fromScale(1, 1)
		lamp.Parent = gui
		gui.Parent = part
		view.lenses[index] = lamp
		table.insert(view.lensGuis, gui)
	end
end

function BinnacleView.build(part: BasePart, model: Model, screen: Binnacle.Screen): View
	local gui = Instance.new("SurfaceGui")
	gui.Name = "LiveBinnacle"
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(screen.canvasWidth, screen.canvasHeight)
	gui.LightInfluence = 0
	gui.Brightness = screen.brightness
	gui.ClipsDescendants = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local background = Instance.new("Frame")
	background.Name = "Background"
	background.BackgroundColor3 = colour(screen.background)
	background.BorderSizePixel = 0
	background.Size = UDim2.fromScale(1, 1)
	background.Parent = gui
	local title = Instance.new("Frame")
	title.Name = "TitleStrip"
	title.BorderSizePixel = 0
	title.ZIndex = 0
	title.Visible = false
	title.Parent = background
	local view: View = {
		gui = gui,
		screen = screen,
		background = background,
		title = title,
		pages = {},
		lenses = {},
		lensGuis = {},
		shown = nil,
	}
	for index, page in screen.pages do
		local fit =
			Rules.fitPage(screen.canvasWidth / screen.canvasHeight, page.art.art.width / page.art.art.height)
		view.pages[index] = buildPage(view, page, index, fit)
	end
	buildLenses(view, model)
	gui.Parent = part
	return view
end

function BinnacleView.destroy(view: View)
	view.gui:Destroy()
	for _, gui in view.lensGuis do
		gui:Destroy()
	end
end

local function showPage(view: View, shown: PageView?)
	view.shown = shown
	local art = shown and shown.page.art
	view.background.BackgroundColor3 = colour(if art then art.edge else view.screen.background)
	local title = art and art.title
	view.title.Visible = title ~= nil
	if shown and title then
		local holder = shown.image
		view.title.Position = UDim2.fromScale(0, holder.Position.Y.Scale)
		view.title.Size = UDim2.fromScale(1, title.height * holder.Size.Y.Scale)
		view.title.BackgroundColor3 = colour(title.rgb)
	end
end

local function updatePage(pageView: PageView, readout: Rules.Readout)
	local band = pageView.page.art.band
	if band then
		local lit = Rules.litSegments(band.segments, readout.rpm)
		if lit ~= pageView.lit then
			for index, segment in pageView.segments do
				segment.Visible = index <= lit
			end
			pageView.lit = lit
		end
	end
	for _, value in pageView.values do
		local shown = Rules.fieldText(value.field, readout)
		if value.text.Text == shown then
			continue
		end
		value.text.Text = shown
		local pill = value.pill
		if pill then
			local rgb = Rules.pillColour(value.field, shown)
			pill.Visible = rgb ~= nil
			if rgb then
				pill.ImageColor3 = colour(rgb)
			end
		end
	end
end

local function updateLenses(view: View, state: State)
	local screen = view.screen
	local strip = if state.on then Rules.strip(screen, state.readout.rpm, state.now, state.lamps) else {}
	for index, lamp in view.lenses do
		local lit = strip[index]
		local sprite = if lit then screen.lamps.on[index] else screen.lamps.off[index]
		if lamp.ImageRectOffset.X ~= sprite.x or lamp.ImageRectOffset.Y ~= sprite.y then
			setSprite(lamp, sprite)
		end
		local tint = if lit then colour(lit) else WHITE
		if lamp.ImageColor3 ~= tint then
			lamp.ImageColor3 = tint
		end
	end
end

-- Shows `state`, touching only what changed.
function BinnacleView.update(view: View, state: State)
	local page = if state.on then Rules.page(view.screen, state.page) else nil
	local shown: PageView? = nil
	for _, pageView in view.pages do
		local visible = pageView.page == page
		if pageView.image.Visible ~= visible then
			pageView.image.Visible = visible
		end
		if visible then
			shown = pageView
		end
	end
	if shown ~= view.shown then
		showPage(view, shown)
	end
	updateLenses(view, state)
	if shown then
		updatePage(shown, state.readout)
	end
end

return BinnacleView
