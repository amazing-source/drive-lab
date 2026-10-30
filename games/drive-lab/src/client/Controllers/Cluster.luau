--!strict
--[[
	The live instrument cluster of the car the local player drives: the SVJ's own cluster face,
	on the screen the rig mounts over the model's static one, with its rev counter lighting cell
	by cell (red from the redline, flashing on the limiter), the gear, the speed, the driving
	mode in its colour and the TC/ABS tell-tales drawn over it. The screen stays dark until START
	is pressed, then the dial sweeps to the top and back. Built once per drive, then updated from the car's readouts a few
	dozen times a second, touching only what changed.
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CarEntry = require(ReplicatedStorage.Shared.Rules.CarEntry)
local CarRig = require(ReplicatedStorage.Shared.Car.CarRig)
local CarState = require(ReplicatedStorage.Shared.Car.CarState)
local Catalog = require(ReplicatedStorage.Shared.Config.Cars.Catalog)
local Cluster = require(ReplicatedStorage.Shared.Config.Cluster)
local ClusterTheme = require(ReplicatedStorage.Shared.Config.ClusterTheme)
local DriverAssists = require(ReplicatedStorage.Shared.Rules.DriverAssists)
local DriverAssistsConfig = require(ReplicatedStorage.Shared.Config.DriverAssists)
local Rules = require(ReplicatedStorage.Shared.Rules.Cluster)

type Display = {
	model: Model,
	entry: Catalog.Entry,
	gui: SurfaceGui,
	lit: ImageLabel,
	red: ImageLabel,
	wipes: { UIGradient },
	esc: TextLabel,
	gear: TextLabel,
	speed: TextLabel,
	mode: TextLabel,
	tc: TextLabel,
	abs: TextLabel,
	face: ImageLabel,
	cells: number,
	theme: string,
}

local FONT = Font.fromEnum(Enum.Font.Michroma)
-- Opaque up to the gradient's middle, clear after it: the edge Rules.wipeRotation turns.
local WIPE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(0.502, 1),
	NumberSequenceKeypoint.new(1, 1),
})
-- Canvas pixels per pixel of the face image.
local SCALE = Cluster.CANVAS_HEIGHT / Cluster.IMAGE_HEIGHT

local localPlayer = Players.LocalPlayer
local display: Display? = nil
local elapsed = 0

local function at(x: number, y: number): UDim2
	return UDim2.fromOffset(x * SCALE, y * SCALE)
end

local function label(parent: Instance, spot: Cluster.Spot, text: string, anchor: Vector2): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.FontFace = FONT
	item.Text = text
	item.TextSize = spot.size * SCALE
	item.AutomaticSize = Enum.AutomaticSize.XY
	item.Size = UDim2.fromOffset(0, 0)
	item.AnchorPoint = anchor
	item.Position = at(spot.x, spot.y)
	item.TextColor3 = ClusterTheme.MODES.Strada.text
	item.Parent = parent
	return item
end

local function litLayer(parent: Instance, image: string): (ImageLabel, UIGradient)
	local layer = Instance.new("ImageLabel")
	layer.BackgroundTransparency = 1
	layer.Image = image
	layer.AnchorPoint = Vector2.new(0.5, 0.5)
	layer.Size = UDim2.fromOffset(Cluster.LIT_SIZE * SCALE, Cluster.LIT_SIZE * SCALE)
	layer.Position = at(Cluster.DIAL_X, Cluster.DIAL_Y)
	layer.Parent = parent
	local wipe = Instance.new("UIGradient")
	wipe.Transparency = WIPE
	wipe.Rotation = Rules.wipeRotation(0)
	wipe.Parent = layer
	return layer, wipe
end

local function build(model: Model, entry: Catalog.Entry, screen: BasePart): Display
	local gui = Instance.new("SurfaceGui")
	gui.Name = "LiveCluster"
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(Cluster.CANVAS_WIDTH, Cluster.CANVAS_HEIGHT)
	gui.LightInfluence = 0
	gui.Brightness = Cluster.BRIGHTNESS
	gui.ClipsDescendants = true

	local background = Instance.new("Frame")
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = ClusterTheme.BACKGROUND
	background.BorderSizePixel = 0
	background.Parent = gui

	-- The face fills the canvas's height, centred across its width.
	local face = Instance.new("ImageLabel")
	face.BackgroundTransparency = 1
	face.Image = Cluster.BASE_IMAGE
	face.AnchorPoint = Vector2.new(0.5, 0)
	face.Position = UDim2.fromScale(0.5, 0)
	face.Size = UDim2.fromOffset(Cluster.IMAGE_WIDTH * SCALE, Cluster.CANVAS_HEIGHT)
	face.Parent = background

	local lit, litWipe = litLayer(face, Cluster.LIT_IMAGE)
	local red, redWipe = litLayer(face, Cluster.RED_IMAGE)
	local centred = Vector2.new(0.5, 0.5)
	local esc = label(face, Cluster.ESC, "", centred)
	esc.TextColor3 = ClusterTheme.WARNING

	gui.Parent = screen
	return {
		model = model,
		entry = entry,
		gui = gui,
		face = face,
		lit = lit,
		red = red,
		wipes = { litWipe, redWipe },
		esc = esc,
		gear = label(face, Cluster.GEAR, "N", centred),
		speed = label(face, Cluster.SPEED, "0", Vector2.new(1, 0.5)),
		mode = label(face, Cluster.MODE, "STRADA", centred),
		tc = label(face, Cluster.TC, "TC", centred),
		abs = label(face, Cluster.ABS, "ABS", centred),
		cells = 0,
		theme = "",
	}
end

local function read(model: Model, name: string): any
	return model:GetAttribute(name)
end

local function number(model: Model, name: string): number
	local value = read(model, name)
	return if typeof(value) == "number" then value else 0
end

local function refresh(current: Display)
	local model = current.model
	local now = os.clock()
	local modeName = read(model, "DrivingMode")
	local themeName = if typeof(modeName) == "string" and ClusterTheme.MODES[modeName]
		then modeName
		else "Strada"
	local theme = ClusterTheme.MODES[themeName]
	if themeName ~= current.theme then
		current.theme = themeName
		current.lit.ImageColor3 = theme.accent
		current.mode.TextColor3 = theme.accent
		current.mode.Text = string.upper(themeName)
		current.gear.TextColor3 = theme.text
		current.speed.TextColor3 = theme.text
	end

	-- Dark until START is pressed; from the press the dial sweeps, then shows the start-up's revs.
	local serverNow = Workspace:GetServerTimeNow()
	local state = CarState.read(model)
	local sincePress = CarEntry.startup(current.entry, state, serverNow).sincePress
	current.face.Visible = sincePress ~= nil
	local sweep = if sincePress then Rules.startupRpm(sincePress) else nil
	local rpm = sweep or CarEntry.shownRpm(current.entry, state, serverNow, number(model, "Rpm"))
	local cells = Rules.litCells(rpm)
	if cells ~= current.cells then
		current.cells = cells
		for _, wipe in current.wipes do
			wipe.Rotation = Rules.wipeRotation(cells)
		end
	end
	local shown = Rules.cellsShown(read(model, "Limiter") == true, now)
	current.lit.Visible = shown
	current.red.Visible = shown

	current.gear.Text = Rules.gearLabel(math.round(number(model, "Gear")))
	current.speed.Text = tostring(math.round(number(model, "SpeedKmh")))
	current.tc.TextColor3 = if read(model, "TcActive") == true then ClusterTheme.WARNING else theme.dim
	current.abs.TextColor3 = if read(model, "AbsActive") == true then ClusterTheme.WARNING else theme.dim
	local lamp: DriverAssists.Lamp = DriverAssists.escLamp(
		read(model, "EscOff") == true,
		read(model, "EscActive") == true,
		now,
		DriverAssistsConfig
	)
	local launch = read(model, "Launch")
	local escText = Rules.lampText(lamp, launch == "Armed" or launch == "Launching")
	if current.esc.Text ~= escText then
		current.esc.Text = escText
	end
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

local function update(dt: number)
	local model = drivenModel()
	local current = display
	if current and current.model ~= model then
		current.gui:Destroy()
		display, current = nil, nil
	end
	if model == nil then
		return
	end
	if current == nil then
		local screen = model:FindFirstChild("ClusterScreen")
		local entry = Catalog.of(model)
		if screen == nil or not screen:IsA("BasePart") or entry == nil then
			return
		end
		current = build(model, entry, screen)
		display = current
	end
	elapsed += dt
	if elapsed < Cluster.UPDATE_INTERVAL then
		return
	end
	elapsed = 0
	refresh(current :: Display)
end

local Controller = {}

function Controller.start()
	RunService.Heartbeat:Connect(update)
end

return Controller
