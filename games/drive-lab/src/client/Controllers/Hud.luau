--!strict
--[[
	The driving HUD (Config/Hud): the owner's design as a frame image, with the live parts drawn
	over it: ten rev segments of a thousand rpm, filling as a needle would and red past the
	redline, the drive mode, TC and ABS lit while they act (red while switched off), A or M and the
	gear, the speed, the headlight tell-tale, and the indicators while they blink. Shown while this
	player drives, bottom centre, or bottom right in the cockpit; U cycles full, minimal (the same,
	smaller) and off. Reads the readouts the driving and lights controllers publish on the car model.
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CarEntry = require(ReplicatedStorage.Shared.Rules.CarEntry)
local CarRig = require(ReplicatedStorage.Shared.Car.CarRig)
local CarState = require(ReplicatedStorage.Shared.Car.CarState)
local ClusterRules = require(ReplicatedStorage.Shared.Rules.Cluster)
local Config = require(ReplicatedStorage.Shared.Config.Hud)
local Controls = require(ReplicatedStorage.Shared.Config.Controls)
local DriverAssists = require(ReplicatedStorage.Shared.Rules.DriverAssists)
local DriverAssistsConfig = require(ReplicatedStorage.Shared.Config.DriverAssists)
local Rules = require(ReplicatedStorage.Shared.Rules.Hud)

local MONTSERRAT = "rbxasset://fonts/families/Montserrat.json"
local LABEL = Font.new(MONTSERRAT, Enum.FontWeight.SemiBold)
local DIGITS = Font.new(MONTSERRAT, Enum.FontWeight.Heavy, Enum.FontStyle.Italic)

local SOLID = NumberSequence.new(0)
local FLASH = ColorSequence.new(Config.BLUE)

type Text = { label: TextLabel, scale: UIScale, box: Config.Box }

type Segment = { image: ImageLabel, gradient: UIGradient, zone: ColorSequence }

type Ui = {
	gui: ScreenGui,
	frame: ImageLabel,
	segments: { Segment },
	mode: TextLabel,
	tc: TextLabel,
	tcLine: Frame,
	abs: TextLabel,
	absLine: Frame,
	box: TextLabel,
	gear: TextLabel,
	gearPop: UIScale,
	speed: TextLabel,
	light: ImageLabel,
	left: TextLabel,
	right: TextLabel,
	flashing: boolean,
}

local localPlayer = Players.LocalPlayer
local ui: Ui? = nil
local hudMode: Rules.Mode = "Full"
local elapsed = 0
local lastGear = ""

local function share(x: number, y: number): UDim2
	return UDim2.fromScale(x / Config.FRAME_SIZE.X, y / Config.FRAME_SIZE.Y)
end

local function place(item: GuiObject, box: Config.Box)
	item.Position = share(box[1], box[2])
	item.Size = share(box[3] - box[1], box[4] - box[2])
end

local function part(parent: Instance, rect: Config.Box, box: Config.Box): ImageLabel
	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.Image = Config.PARTS_IMAGE
	image.ImageRectOffset = Vector2.new(rect[1], rect[2])
	image.ImageRectSize = Vector2.new(rect[3], rect[4])
	place(image, box)
	image.Parent = parent
	return image
end

local function bar(parent: Instance, box: Config.Box): Frame
	local line = Instance.new("Frame")
	line.BorderSizePixel = 0
	place(line, box)
	line.Parent = parent
	return line
end

-- A tell-tale's text and line: grey while ready, yellow while it acts, red while switched off.
local function paint(label: TextLabel, line: Frame, state: DriverAssists.Telltale)
	label.TextColor3 = if state == "Acting"
		then Config.YELLOW
		elseif state == "Off" then Config.RED
		else Config.GREY
	line.BackgroundColor3 = if state == "Acting"
		then Config.YELLOW
		elseif state == "Off" then Config.RED
		else Config.LINE_GREY
end

-- The segment's colour along its length: yellow, then red from where the redline falls in it.
local function zone(index: number): ColorSequence
	local red = Rules.segmentShare(Config.REDLINE_RPM, index, Config.RPM_PER_SEGMENT)
	if red >= 1 then
		return ColorSequence.new(Config.YELLOW)
	elseif red <= 0 then
		return ColorSequence.new(Config.RED)
	end
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, Config.YELLOW),
		ColorSequenceKeypoint.new(red, Config.YELLOW),
		ColorSequenceKeypoint.new(red + 0.002, Config.RED),
		ColorSequenceKeypoint.new(1, Config.RED),
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
local function fit(texts: { Text }, frameHeight: number)
	local pixel = frameHeight / Config.FRAME_SIZE.Y
	for _, entry in texts do
		local box = entry.box
		local size = (box[4] - box[2]) * pixel / Config.CAP_HEIGHT
		local scale = math.max(1, size / 100)
		entry.label.TextSize = size / scale
		entry.scale.Scale = scale
		entry.label.Size =
			UDim2.fromOffset((box[3] - box[1]) * pixel / scale, (box[4] - box[2]) * pixel / scale)
	end
end

local function build(parent: Instance): Ui
	local gui = Instance.new("ScreenGui")
	gui.Name = "DriveHud"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 5
	gui.Enabled = false

	local frame = Instance.new("ImageLabel")
	frame.Name = "Frame"
	frame.BackgroundTransparency = 1
	frame.Image = Config.FRAME_IMAGE
	frame.Parent = gui
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = Config.FRAME_SIZE.X / Config.FRAME_SIZE.Y
	aspect.Parent = frame

	local segments = {}
	for index, box in Config.SEGMENTS do
		local rect = if index == 1
			then Config.PARTS.first
			elseif index == #Config.SEGMENTS then Config.PARTS.last
			else Config.PARTS.middle
		local image = part(frame, rect, box)
		image.Visible = false
		local gradient = Instance.new("UIGradient")
		local colors = zone(index)
		gradient.Color = colors
		gradient.Parent = image
		segments[index] = { image = image, gradient = gradient, zone = colors }
	end

	local texts: { Text } = {}
	local function text(
		holder: Instance,
		box: Config.Box,
		font: Font,
		align: Enum.TextXAlignment,
		color: Color3
	): TextLabel
		local anchorX = if align == Enum.TextXAlignment.Left
			then 0
			elseif align == Enum.TextXAlignment.Right then 1
			else 0.5
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.FontFace = font
		label.TextColor3 = color
		label.TextXAlignment = align
		label.AnchorPoint = Vector2.new(anchorX, 0.5)
		label.Position = share(box[1] + (box[3] - box[1]) * anchorX, (box[2] + box[4]) / 2)
		label.Parent = holder
		local scale = Instance.new("UIScale")
		scale.Parent = label
		table.insert(texts, { label = label, scale = scale, box = box })
		return label
	end

	-- The gear sits in a frame-sized holder anchored on its centre, so it pops about its middle.
	local readouts = Config.READOUTS
	local gearBox = readouts.gear
	local centre = Vector2.new(gearBox[1] + gearBox[3], gearBox[2] + gearBox[4]) / 2 / Config.FRAME_SIZE
	local gearHolder = Instance.new("Frame")
	gearHolder.BackgroundTransparency = 1
	gearHolder.Size = UDim2.fromScale(1, 1)
	gearHolder.AnchorPoint = centre
	gearHolder.Position = UDim2.fromScale(centre.X, centre.Y)
	gearHolder.Parent = frame
	local gearPop = Instance.new("UIScale")
	gearPop.Parent = gearHolder

	local function arrow(box: Config.Box, glyph: string): TextLabel
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Text = glyph
		label.TextScaled = true
		label.TextColor3 = Config.GREEN
		label.Visible = false
		place(label, box)
		label.Parent = frame
		return label
	end

	local light = part(frame, Config.PARTS.light, readouts.light)
	light.ImageColor3 = Config.OFF
	local built: Ui = {
		gui = gui,
		frame = frame,
		segments = segments,
		mode = text(frame, readouts.mode, LABEL, Enum.TextXAlignment.Left, Config.YELLOW),
		tc = text(frame, readouts.tcText, LABEL, Enum.TextXAlignment.Center, Config.GREY),
		tcLine = bar(frame, readouts.tcLine),
		abs = text(frame, readouts.absText, LABEL, Enum.TextXAlignment.Center, Config.GREY),
		absLine = bar(frame, readouts.absLine),
		box = text(frame, readouts.box, LABEL, Enum.TextXAlignment.Center, Config.WHITE),
		gear = text(gearHolder, gearBox, DIGITS, Enum.TextXAlignment.Center, Config.WHITE),
		gearPop = gearPop,
		speed = text(frame, readouts.speed, DIGITS, Enum.TextXAlignment.Right, Config.WHITE),
		light = light,
		left = arrow(readouts.indicatorLeft, "◀"),
		right = arrow(readouts.indicatorRight, "▶"),
		flashing = false,
	}
	built.tc.Text = "TC"
	built.abs.Text = "ABS"

	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		fit(texts, frame.AbsoluteSize.Y)
	end)
	gui.Parent = parent
	fit(texts, frame.AbsoluteSize.Y)
	return built
end

local function drivenModel(): Model?
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	local model = seat and seat.Parent
	if model and model:IsA("Model") and CollectionService:HasTag(model, CarRig.TAG) then
		return model
	end
	return nil
end

local function number(model: Model, name: string): number
	local value = model:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

local function arrange(current: Ui)
	local camera = Workspace.CurrentCamera
	local cockpit = camera ~= nil and camera:GetAttribute("DriveLabView") == "Cockpit"
	local height = (if cockpit then Config.COCKPIT_HEIGHT else Config.HEIGHT)
		* (if hudMode == "Minimal" then Config.MINIMAL_SCALE else 1)
	local frame = current.frame
	frame.Size = UDim2.fromScale(Config.MAX_WIDTH, height)
	frame.AnchorPoint = if cockpit then Vector2.new(1, 1) else Vector2.new(0.5, 1)
	frame.Position = if cockpit
		then UDim2.new(1, -Config.MARGIN, 1, -Config.MARGIN)
		else UDim2.new(0.5, 0, 1, -Config.MARGIN)
end

local function refresh(current: Ui, model: Model)
	local rpm = CarEntry.shownRpm(CarState.read(model), Workspace:GetServerTimeNow(), number(model, "Rpm"))
	local manual = model:GetAttribute("GearboxMode") == "manual"
	local flash = Rules.shiftFlash(rpm, Config.REDLINE_RPM, manual, os.clock(), Config.FLASH_HZ)
	for index, segment in current.segments do
		local lit = Rules.segmentShare(rpm, index, Config.RPM_PER_SEGMENT)
		segment.image.Visible = lit > 0
		if lit > 0 then
			segment.gradient.Transparency = if lit >= 1 then SOLID else edge(lit)
		end
		if flash ~= current.flashing then
			segment.gradient.Color = if flash then FLASH else segment.zone
		end
	end
	current.flashing = flash

	local gear = ClusterRules.gearLabel(math.round(number(model, "Gear")))
	if gear ~= lastGear then
		lastGear = gear
		current.gear.Text = gear
		current.gearPop.Scale = 1.18
		TweenService:Create(current.gearPop, TweenInfo.new(Config.GEAR_POP), { Scale = 1 }):Play()
	end
	current.gear.TextColor3 = if flash then Config.BLUE else Config.WHITE
	current.box.Text = if manual then "M" else "A"
	current.speed.Text = tostring(math.round(number(model, "SpeedKmh")))
	local modeName = model:GetAttribute("DrivingMode")
	current.mode.Text = if typeof(modeName) == "string" then string.upper(modeName) else ""

	local assists = DriverAssists.assists(model:GetAttribute("EscOff") == true, DriverAssistsConfig)
	paint(
		current.tc,
		current.tcLine,
		DriverAssists.telltale(assists.tc, model:GetAttribute("TcActive") == true)
	)
	paint(
		current.abs,
		current.absLine,
		DriverAssists.telltale(assists.abs, model:GetAttribute("AbsActive") == true)
	)
	current.light.ImageColor3 = if model:GetAttribute("HeadlightsOn") == true
		then Config.GREEN
		else Config.OFF
	current.left.Visible = model:GetAttribute("IndicatorLeft") == true
	current.right.Visible = model:GetAttribute("IndicatorRight") == true
end

local function update(dt: number)
	local current = ui
	if current == nil then
		return
	end
	local driven = drivenModel()
	-- Not while getting in or out (Rules/CarEntry).
	local model = if driven
			and CarEntry.phase(CarState.read(driven), Workspace:GetServerTimeNow()) == "Seated"
		then driven
		else nil
	current.gui.Enabled = model ~= nil and hudMode ~= "Off"
	if model == nil or hudMode == "Off" then
		return
	end
	elapsed += dt
	if elapsed < Config.UPDATE_INTERVAL then
		return
	end
	elapsed = 0
	arrange(current)
	refresh(current, model)
end

local Controller = {}

function Controller.start()
	ui = build(localPlayer:WaitForChild("PlayerGui"))
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and table.find(Controls.HUD_MODE, input.KeyCode) and drivenModel() then
			hudMode = Rules.nextMode(hudMode)
		end
	end)
	RunService.Heartbeat:Connect(update)
end

return Controller
