--!strict
--[[
	Draws an analog cluster's small screens (Config/Gauges) on the rig's display parts: the
	seven-segment readout, every segment a frame lit or faintly showing through the lens, and the
	message centre's two lines. Each canvas takes its screen's shape at Gauges.PIXELS_PER_METRE.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cluster = require(ReplicatedStorage.Shared.Config.Cluster)
local Gauges = require(ReplicatedStorage.Shared.Config.Gauges)
local SevenSegment = require(ReplicatedStorage.Shared.Rules.SevenSegment)
local Units = require(ReplicatedStorage.Shared.Units)

type Digit = { segments: { [string]: Frame }, point: Frame }

export type Readout = { gui: SurfaceGui, spec: Gauges.Readout, digits: { Digit }, text: string? }

export type Message = { gui: SurfaceGui, lines: { TextLabel }, shown: string? }

local LINES = 2

local GaugeScreens = {}

local function colour(value: Cluster.Rgb): Color3
	return Color3.fromRGB(value.r, value.g, value.b)
end

local function surface(part: BasePart, name: string, brightness: number): (SurfaceGui, Vector2)
	local canvas = Vector2.new(
		math.max(1, math.round(Units.studsToMetres(part.Size.X) * Gauges.PIXELS_PER_METRE)),
		math.max(1, math.round(Units.studsToMetres(part.Size.Y) * Gauges.PIXELS_PER_METRE))
	)
	local gui = Instance.new("SurfaceGui")
	gui.Name = name
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = canvas
	gui.LightInfluence = 0
	gui.Brightness = brightness
	gui.Enabled = false
	return gui, canvas
end

local function bar(
	parent: Instance,
	rect: SevenSegment.Rect,
	origin: Vector2,
	size: Vector2,
	tint: Color3
): Frame
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = tint
	frame.Position = UDim2.fromOffset(origin.X + rect.x * size.X, origin.Y + rect.y * size.Y)
	frame.Size = UDim2.fromOffset(rect.width * size.X, rect.height * size.Y)
	frame.Parent = parent
	return frame
end

function GaugeScreens.readout(part: BasePart, spec: Gauges.Readout): Readout
	local gui, canvas = surface(part, "LiveReadout", spec.brightness)
	local shape = Gauges.SEGMENT
	local height = canvas.Y * shape.height
	local width = height * shape.aspect
	local space = width * shape.spacing
	local total = spec.digits * width + (spec.digits - 1) * space
	local fit = math.min(1, canvas.X * 0.95 / total)
	height, width, space, total = height * fit, width * fit, space * fit, total * fit
	local cell = Vector2.new(width, height)
	local rects = SevenSegment.layout(shape.thickness, shape.gap, shape.aspect)
	local tint = colour(spec.lit)
	local left, top = (canvas.X - total) / 2, (canvas.Y - height) / 2
	local digits: { Digit } = table.create(spec.digits)
	for index = 1, spec.digits do
		local origin = Vector2.new(left + (index - 1) * (width + space), top)
		local segments: { [string]: Frame } = {}
		for name, rect in rects do
			segments[name] = bar(gui, rect, origin, cell, tint)
		end
		local dot = shape.thickness * height
		local point = bar(gui, {
			x = 1 + (shape.spacing - dot / width) / 2,
			y = 1 - shape.thickness,
			width = dot / width,
			height = shape.thickness,
		}, origin, cell, tint)
		digits[index] = { segments = segments, point = point }
	end
	gui.Parent = part
	return { gui = gui, spec = spec, digits = digits, text = nil }
end

-- Shows `text` (Rules/SevenSegment.cells), or turns the readout off for nil.
function GaugeScreens.showReadout(view: Readout, text: string?)
	if text == view.text then
		return
	end
	view.text = text
	view.gui.Enabled = text ~= nil
	if text == nil then
		return
	end
	local dim = view.spec.unlitTransparency
	for index, cell in SevenSegment.cells(text, view.spec.digits) do
		local digit = view.digits[index]
		for name, frame in digit.segments do
			frame.BackgroundTransparency = if SevenSegment.lit(cell, name) then 0 else dim
		end
		digit.point.BackgroundTransparency = if cell.point then 0 else dim
	end
end

function GaugeScreens.message(part: BasePart, spec: Gauges.Message): Message
	local gui, canvas = surface(part, "LiveMessage", spec.brightness)
	local lines: { TextLabel } = table.create(LINES)
	for index = 1, LINES do
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.FontFace = Font.new(spec.font)
		label.TextColor3 = colour(spec.text)
		label.TextSize = canvas.Y / LINES * 0.75
		label.Size = UDim2.fromScale(1, 1 / LINES)
		label.Position = UDim2.fromScale(0, (index - 1) / LINES)
		label.Text = ""
		label.Parent = gui
		lines[index] = label
	end
	gui.Parent = part
	return { gui = gui, lines = lines, shown = nil }
end

-- Shows the two lines, or turns the screen off for nil.
function GaugeScreens.showMessage(view: Message, lines: { string }?)
	local joined = if lines then table.concat(lines, "\n") else nil
	if joined == view.shown then
		return
	end
	view.shown = joined
	view.gui.Enabled = lines ~= nil
	for index, label in view.lines do
		label.Text = if lines then lines[index] or "" else ""
	end
end

return table.freeze(GaugeScreens)
