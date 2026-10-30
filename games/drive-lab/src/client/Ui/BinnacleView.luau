--!strict
--[[
	Draws a binnacle display (Config/Binnacle) on a screen part: the strip of shift lights along the
	top, the page below it (the first with its rpm bar), each field as its label over its value.
	A functional layout of the photographed pages' contents, not a copy of their typography.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Binnacle = require(ReplicatedStorage.Shared.Config.Binnacle)
local Cluster = require(ReplicatedStorage.Shared.Config.Cluster)
local Rules = require(ReplicatedStorage.Shared.Rules.Binnacle)

export type State = {
	-- Off before the car's start-up: the screen and the strip are dark.
	on: boolean,
	readout: Rules.Readout,
	page: number,
	lamps: Rules.Lamps,
	now: number,
}

export type View = {
	gui: SurfaceGui,
	screen: Binnacle.Screen,
	content: Frame,
	lights: { Frame },
	bar: Frame?,
	values: { TextLabel },
	shownPage: Binnacle.Page?,
}

local FONT = Font.fromEnum(Enum.Font.RobotoMono)
local BOLD = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold)
local BAR_HEIGHT = 34
local TITLE_HEIGHT = 30
local GAP = 8

local BinnacleView = {}

local function colour(value: Cluster.Rgb): Color3
	return Color3.fromRGB(value.r, value.g, value.b)
end

local function text(parent: Instance, value: string, font: Font, size: number, rgb: Cluster.Rgb): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = font
	label.TextSize = size
	label.TextColor3 = colour(rgb)
	label.Text = value
	label.Parent = parent
	return label
end

local function buildStrip(view: View, parent: Instance)
	local screen = view.screen
	local count = #screen.revLights.colours + 2
	local strip = Instance.new("Frame")
	strip.Name = "Strip"
	strip.BackgroundTransparency = 1
	strip.Size = UDim2.new(1, 0, 0, screen.stripHeight)
	strip.Parent = parent
	local size = screen.lightSize
	-- The rev lights close together in the middle, a lamp at each end (1 + 6 + 1).
	local spacing = size * 1.4
	local middle = (count - 2) * spacing
	for index = 1, count do
		local x
		if index == 1 then
			x = size
		elseif index == count then
			x = screen.canvasWidth - size
		else
			x = (screen.canvasWidth - middle) / 2 + (index - 1.5) * spacing
		end
		local light = Instance.new("Frame")
		light.Name = `Light{index}`
		light.AnchorPoint = Vector2.new(0.5, 0.5)
		light.Position = UDim2.fromOffset(x, screen.stripHeight / 2)
		light.Size = UDim2.fromOffset(size, size)
		light.BackgroundColor3 = colour(screen.dim)
		light.BorderSizePixel = 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = light
		light.Parent = strip
		table.insert(view.lights, light)
	end
end

local function buildPage(view: View, page: Binnacle.Page, first: boolean)
	local screen = view.screen
	view.content:ClearAllChildren()
	table.clear(view.values)
	view.bar = nil
	local top = 0
	if first then
		local back = Instance.new("Frame")
		back.Name = "RpmBar"
		back.BackgroundColor3 = colour(screen.dim)
		back.BorderSizePixel = 0
		back.Size = UDim2.new(1, -2 * GAP, 0, BAR_HEIGHT)
		back.Position = UDim2.fromOffset(GAP, 0)
		back.Parent = view.content
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.BackgroundColor3 = colour(screen.barRgb)
		fill.BorderSizePixel = 0
		fill.Size = UDim2.fromScale(0, 1)
		fill.Parent = back
		view.bar = fill
		for _, mark in screen.barMarks do
			local share = (mark * 1000 - screen.barFromRpm) / (screen.barToRpm - screen.barFromRpm)
			local label = text(back, tostring(mark), BOLD, 18, screen.text)
			label.AnchorPoint = Vector2.new(0.5, 0)
			label.Position = UDim2.new(share, 0, 1, 2)
			label.Size = UDim2.fromOffset(20, 18)
		end
		top = BAR_HEIGHT + 24
	elseif page.title ~= "" then
		local title = text(view.content, page.title, BOLD, 22, screen.text)
		title.Size = UDim2.new(1, 0, 0, TITLE_HEIGHT)
		top = TITLE_HEIGHT + GAP
	end
	local fields = page.fields
	local rows = math.ceil(#fields / 2)
	local height = screen.canvasHeight - screen.stripHeight - top - GAP
	local rowHeight = height / math.max(rows, 1)
	for index, field in fields do
		local column = (index - 1) % 2
		local row = math.floor((index - 1) / 2)
		local cell = Instance.new("Frame")
		cell.Name = if field.label ~= "" then field.label else `Field{index}`
		cell.BackgroundTransparency = 1
		cell.Position = UDim2.new(column * 0.5, GAP, 0, top + row * rowHeight)
		cell.Size = UDim2.new(0.5, -2 * GAP, 0, rowHeight)
		cell.Parent = view.content
		local label = text(cell, field.label, FONT, math.min(rowHeight * 0.35, 18), screen.dim)
		label.Size = UDim2.fromScale(0.55, 1)
		label.TextXAlignment = Enum.TextXAlignment.Left
		local value = text(cell, "--", BOLD, math.min(rowHeight * 0.6, 30), screen.text)
		value.Position = UDim2.fromScale(0.55, 0)
		value.Size = UDim2.fromScale(0.45, 1)
		value.TextXAlignment = Enum.TextXAlignment.Right
		table.insert(view.values, value)
	end
	view.shownPage = page
end

function BinnacleView.build(part: BasePart, screen: Binnacle.Screen): View
	local gui = Instance.new("SurfaceGui")
	gui.Name = "LiveBinnacle"
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(screen.canvasWidth, screen.canvasHeight)
	gui.LightInfluence = 0
	gui.Brightness = screen.brightness
	gui.ClipsDescendants = true
	local background = Instance.new("Frame")
	background.Name = "Background"
	background.BackgroundColor3 = colour(screen.background)
	background.BorderSizePixel = 0
	background.Size = UDim2.fromScale(1, 1)
	background.Parent = gui
	local content = Instance.new("Frame")
	content.Name = "Page"
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromOffset(0, screen.stripHeight)
	content.Size = UDim2.new(1, 0, 1, -screen.stripHeight)
	content.Parent = background
	local view: View = {
		gui = gui,
		screen = screen,
		content = content,
		lights = {},
		bar = nil,
		values = {},
		shownPage = nil,
	}
	buildStrip(view, background)
	gui.Parent = part
	return view
end

-- Shows `state`, touching only what changed.
function BinnacleView.update(view: View, state: State)
	local screen = view.screen
	view.content.Visible = state.on
	local strip = if state.on
		then Rules.strip(screen, state.readout.rpm, state.now, state.lamps)
		else table.create(#view.lights)
	for index, light in view.lights do
		local lit = strip[index]
		local want = if lit then colour(lit) else colour(screen.dim)
		if light.BackgroundColor3 ~= want then
			light.BackgroundColor3 = want
		end
	end
	if not state.on then
		return
	end
	local page = Rules.page(screen, state.page)
	if page ~= view.shownPage then
		buildPage(view, page, page == screen.pages[1])
	end
	local bar = view.bar
	if bar then
		bar.Size = UDim2.fromScale(Rules.barShare(screen, state.readout.rpm), 1)
	end
	for index, field in page.fields do
		local value = view.values[index]
		local shown = Rules.fieldText(field, state.readout)
		if value and value.Text ~= shown then
			value.Text = shown
		end
	end
end

return BinnacleView
