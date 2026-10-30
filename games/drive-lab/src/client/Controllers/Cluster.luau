--!strict
--[[
	The live instrument cluster of the car the local player drives: the car's own cluster face
	(its entry's cluster), on the screen the rig mounts over the model's static one, with its rev
	counter lighting cell by cell (red from the redline, flashing on the limiter), the gear, the
	speed, the driving mode in its colour and the TC/ABS tell-tales drawn over it. The screen stays
	dark until START is pressed, then the dial sweeps to the top and back. Built once per drive,
	then updated from the car's readouts a few dozen times a second, touching only what changed.
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
local DriveModes = require(ReplicatedStorage.Shared.Rules.DriveModes)
local DriverAssists = require(ReplicatedStorage.Shared.Rules.DriverAssists)
local Rules = require(ReplicatedStorage.Shared.Rules.Cluster)

type Palette = { accent: Color3, dim: Color3, text: Color3 }

type Display = {
	model: Model,
	entry: Catalog.Entry,
	spec: Cluster.Face,
	palettes: { [string]: Palette },
	warning: Color3,
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

local localPlayer = Players.LocalPlayer
local display: Display? = nil
local elapsed = 0

local function colour(value: Cluster.Rgb): Color3
	return Color3.fromRGB(value.r, value.g, value.b)
end

-- Canvas pixels per pixel of the face image.
local function scaleOf(spec: Cluster.Face): number
	return spec.canvasHeight / spec.imageHeight
end

local function at(spec: Cluster.Face, x: number, y: number): UDim2
	local scale = scaleOf(spec)
	return UDim2.fromOffset(x * scale, y * scale)
end

local function label(
	parent: Instance,
	spec: Cluster.Face,
	spot: Cluster.Spot,
	text: string,
	anchor: Vector2,
	color: Color3
): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.FontFace = FONT
	item.Text = text
	item.TextSize = spot.size * scaleOf(spec)
	item.AutomaticSize = Enum.AutomaticSize.XY
	item.Size = UDim2.fromOffset(0, 0)
	item.AnchorPoint = anchor
	item.Position = at(spec, spot.x, spot.y)
	item.TextColor3 = color
	item.Parent = parent
	return item
end

local function litLayer(parent: Instance, spec: Cluster.Face, image: string): (ImageLabel, UIGradient)
	local side = spec.litSize * scaleOf(spec)
	local layer = Instance.new("ImageLabel")
	layer.BackgroundTransparency = 1
	layer.Image = image
	layer.AnchorPoint = Vector2.new(0.5, 0.5)
	layer.Size = UDim2.fromOffset(side, side)
	layer.Position = at(spec, spec.dialX, spec.dialY)
	layer.Parent = parent
	local wipe = Instance.new("UIGradient")
	wipe.Transparency = WIPE
	wipe.Rotation = Rules.wipeRotation(spec, 0)
	wipe.Parent = layer
	return layer, wipe
end

local function build(model: Model, entry: Catalog.Entry, spec: Cluster.Face, screen: BasePart): Display
	local palettes: { [string]: Palette } = {}
	for name, theme in spec.modes do
		palettes[name] = { accent = colour(theme.accent), dim = colour(theme.dim), text = colour(theme.text) }
	end
	local warning = colour(spec.warning)
	-- The colours of the mode a car starts in show until the car reports another.
	local first = entry.physics.modeOrder[1]
	local textColor = palettes[first].text

	local gui = Instance.new("SurfaceGui")
	gui.Name = "LiveCluster"
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(spec.canvasWidth, spec.canvasHeight)
	gui.LightInfluence = 0
	gui.Brightness = spec.brightness
	gui.ClipsDescendants = true

	local background = Instance.new("Frame")
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = colour(spec.background)
	background.BorderSizePixel = 0
	background.Parent = gui

	-- The face fills the canvas's height, centred across its width.
	local face = Instance.new("ImageLabel")
	face.BackgroundTransparency = 1
	face.Image = spec.baseImage
	face.AnchorPoint = Vector2.new(0.5, 0)
	face.Position = UDim2.fromScale(0.5, 0)
	face.Size = UDim2.fromOffset(spec.imageWidth * scaleOf(spec), spec.canvasHeight)
	face.Parent = background

	local lit, litWipe = litLayer(face, spec, spec.litImage)
	local red, redWipe = litLayer(face, spec, spec.redImage)
	local centred = Vector2.new(0.5, 0.5)
	local esc = label(face, spec, spec.esc, "", centred, warning)

	gui.Parent = screen
	return {
		model = model,
		entry = entry,
		spec = spec,
		palettes = palettes,
		warning = warning,
		gui = gui,
		face = face,
		lit = lit,
		red = red,
		wipes = { litWipe, redWipe },
		esc = esc,
		gear = label(face, spec, spec.gear, "N", centred, textColor),
		speed = label(face, spec, spec.speed, "0", Vector2.new(1, 0.5), textColor),
		mode = label(face, spec, spec.mode, string.upper(entry.modeLabels[first]), centred, textColor),
		tc = label(face, spec, spec.tc, "TC", centred, textColor),
		abs = label(face, spec, spec.abs, "ABS", centred, textColor),
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
	local spec = current.spec
	local now = os.clock()
	local themeName = DriveModes.current(current.entry.physics.modeOrder, read(model, "DrivingMode"))
	local theme = current.palettes[themeName]
	if themeName ~= current.theme then
		current.theme = themeName
		current.lit.ImageColor3 = theme.accent
		current.mode.TextColor3 = theme.accent
		current.mode.Text = string.upper(current.entry.modeLabels[themeName])
		current.gear.TextColor3 = theme.text
		current.speed.TextColor3 = theme.text
	end

	-- Dark until START is pressed; from the press the dial sweeps, then shows the start-up's revs.
	local serverNow = Workspace:GetServerTimeNow()
	local state = CarState.read(model)
	local sincePress = CarEntry.startup(current.entry, state, serverNow).sincePress
	current.face.Visible = sincePress ~= nil
	local sweep = if sincePress then Rules.startupRpm(spec, sincePress) else nil
	local rpm = sweep or CarEntry.shownRpm(current.entry, state, serverNow, number(model, "Rpm"))
	local cells = Rules.litCells(spec, rpm)
	if cells ~= current.cells then
		current.cells = cells
		for _, wipe in current.wipes do
			wipe.Rotation = Rules.wipeRotation(spec, cells)
		end
	end
	local shown = Rules.cellsShown(spec, read(model, "Limiter") == true, now)
	current.lit.Visible = shown
	current.red.Visible = shown

	current.gear.Text = Rules.gearLabel(math.round(number(model, "Gear")))
	current.speed.Text = tostring(math.round(number(model, "SpeedKmh")))
	current.tc.TextColor3 = if read(model, "TcActive") == true then current.warning else theme.dim
	current.abs.TextColor3 = if read(model, "AbsActive") == true then current.warning else theme.dim
	local lamp: DriverAssists.Lamp = DriverAssists.escLamp(
		read(model, "EscOff") == true,
		read(model, "EscActive") == true,
		now,
		current.entry.assists
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
		local face = entry and entry.cluster
		if screen == nil or not screen:IsA("BasePart") or entry == nil or face == nil then
			return
		end
		current = build(model, entry, face, screen)
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
