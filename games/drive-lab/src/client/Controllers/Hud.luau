--!strict
--[[
	The driving HUD (Ui/HudView, in the driven car's look from Ui/HudLook): ten rev segments of a
	thousand rpm, filling as a needle would and red past the redline, the drive mode, TC and ABS lit
	while they act (red while switched off), A or M and the gear, the speed, the headlight tell-tale
	and the indicators. Shown while this player drives, bottom centre, or bottom right in the
	cockpit; U cycles full, minimal (the same, smaller) and off. Reads the readouts the driving and
	lights controllers publish on the car model.
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CarEntry = require(ReplicatedStorage.Shared.Rules.CarEntry)
local CarRig = require(ReplicatedStorage.Shared.Car.CarRig)
local CarState = require(ReplicatedStorage.Shared.Car.CarState)
local Catalog = require(ReplicatedStorage.Shared.Config.Cars.Catalog)
local ClusterRules = require(ReplicatedStorage.Shared.Rules.Cluster)
local Config = require(ReplicatedStorage.Shared.Config.Hud)
local Contract = require(ReplicatedStorage.Shared.Config.Cars.Contract)
local Controls = require(ReplicatedStorage.Shared.Config.Controls)
local DriveModes = require(ReplicatedStorage.Shared.Rules.DriveModes)
local DriverAssists = require(ReplicatedStorage.Shared.Rules.DriverAssists)
local GameFeel = require(ReplicatedStorage.Shared.Rules.GameFeel)
local GameFeelConfig = require(ReplicatedStorage.Shared.Config.GameFeel)
local HudLook = require(script.Parent.Parent.Ui.HudLook)
local HudView = require(script.Parent.Parent.Ui.HudView)
local Rules = require(ReplicatedStorage.Shared.Rules.Hud)

-- The global HUD's ScreenGui; a car's own is named after the car.
local GLOBAL_NAME = "DriveHud"

local localPlayer = Players.LocalPlayer
local views: { [HudLook.Look]: HudView.View } = {}
local hudMode: Rules.Mode = "Full"
local elapsed = 0
-- The game-feel notch last seen on the driven car (nil until one is published) and when it changed.
local lastNotch: GameFeelConfig.Notch? = nil
local notchChangedAt: number? = nil

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

local function readouts(model: Model, entry: Catalog.Entry): HudView.Readouts
	local rpm =
		CarEntry.shownRpm(entry, CarState.read(model), Workspace:GetServerTimeNow(), number(model, "Rpm"))
	local manual = model:GetAttribute("GearboxMode") == "manual"
	local redline = Contract.redline(entry)
	local launch = model:GetAttribute("Launch")
	local mode = DriveModes.current(entry.physics.modeOrder, model:GetAttribute("DrivingMode"))
	local assists = DriverAssists.assists(model:GetAttribute("EscOff") == true, mode, entry.assists)
	local published = model:GetAttribute("GameFeel")
	if typeof(published) == "string" then
		local notch: GameFeelConfig.Notch = GameFeel.current(published)
		if lastNotch ~= nil and notch ~= lastNotch then
			notchChangedAt = os.clock()
		end
		lastNotch = notch
	end
	local level = if lastNotch
		then GameFeel.flash(lastNotch, notchChangedAt, os.clock(), GameFeelConfig.FLASH_SECONDS)
		else nil
	return {
		rpm = rpm,
		redline = redline,
		flash = Rules.shiftFlash(rpm, redline, manual, os.clock(), Config.FLASH_HZ),
		manual = manual,
		gear = ClusterRules.gearLabel(math.round(number(model, "Gear"))),
		speed = tostring(math.round(number(model, "SpeedKmh"))),
		mode = level or Rules.modeText(
			entry.modeLabels[mode],
			launch == "Armed" or launch == "Launching",
			Config.LAUNCH_TEXT
		),
		tc = DriverAssists.telltale(assists.tc, model:GetAttribute("TcActive") == true),
		abs = DriverAssists.telltale(assists.abs, model:GetAttribute("AbsActive") == true),
		light = if model:GetAttribute("HighBeamOn") == true
			then "High"
			elseif model:GetAttribute("HeadlightsOn") == true then "Dipped"
			else "Off",
		left = model:GetAttribute("IndicatorLeft") == true,
		right = model:GetAttribute("IndicatorRight") == true,
	}
end

local function update(dt: number)
	local model = drivenModel()
	local entry = model and Catalog.of(model)
	-- Not while getting in or out (Rules/CarEntry).
	local seated = model ~= nil
		and entry ~= nil
		and CarEntry.phase(entry, CarState.read(model), Workspace:GetServerTimeNow()) == "Seated"
	local view = if entry then views[HudLook.of(entry)] else nil
	for _, other in views do
		other.gui.Enabled = other == view and seated and hudMode ~= "Off"
	end
	if not seated then
		lastNotch, notchChangedAt = nil, nil
	end
	if model == nil or entry == nil or view == nil or not seated or hudMode == "Off" then
		return
	end
	elapsed += dt
	if elapsed < Config.UPDATE_INTERVAL then
		return
	end
	elapsed = 0
	local camera = Workspace.CurrentCamera
	HudView.place(
		view,
		camera ~= nil and camera:GetAttribute("DriveLabView") == "Cockpit",
		hudMode == "Minimal"
	)
	HudView.show(view, readouts(model, entry))
end

local Controller = {}

function Controller.start()
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	-- Every look is built before any car, so no frame waits on its images when driving starts.
	local names: { string } = {}
	for name in Catalog.cars do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		local entry = Catalog.cars[name]
		local look = HudLook.of(entry)
		if views[look] == nil then
			views[look] =
				HudView.build(playerGui, look, if entry.hud then `{GLOBAL_NAME}{name}` else GLOBAL_NAME)
		end
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and table.find(Controls.HUD_MODE, input.KeyCode) and drivenModel() then
			hudMode = Rules.nextMode(hudMode)
		end
	end)
	RunService.Heartbeat:Connect(update)
end

return Controller
