--!strict
--[[
	The lights of every car on this client (Rules/CarLights decides, Effects/CarLamps shows). A
	car's lamps are dark until its ignition is on; the engine state is the server's, so every
	client knows it for every car.

	The driver of a car: H cycles the headlights (automatic, on, off; automatic means at night or
	in heavy rain), J switches the high beam, or flashes it while held on a car whose switch flashes
	(Config/CarSwitches), even with the headlights off, X and C toggle the left and right
	indicators, L the cabin light; on a pad, D-pad left and right are the indicators and D-pad down steps the
	headlights Auto, On, high beam, Off on a tap and switches the cabin light on a hold. The car this player drives also shows its brakes and
	reverse from its readouts, and its rain light from its switch (RainLightOn, Controllers/
	CarSwitches); other cars show what this client can know: running lights and headlights.
	Everything here is local.
]]
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CarEntry = require(ReplicatedStorage.Shared.Rules.CarEntry)
local CarLamps = require(script.Parent.Parent.Effects.CarLamps)
local CarRig = require(ReplicatedStorage.Shared.Car.CarRig)
local CarState = require(ReplicatedStorage.Shared.Car.CarState)
local Catalog = require(ReplicatedStorage.Shared.Config.Cars.Catalog)
local Config = require(ReplicatedStorage.Shared.Config.CarLights)
local Controls = require(ReplicatedStorage.Shared.Config.Controls)
local Rules = require(ReplicatedStorage.Shared.Rules.CarLights)
local StreetLamps = require(ReplicatedStorage.Shared.Rules.StreetLamps)
local StreetLights = require(ReplicatedStorage.Shared.Config.StreetLights)

local localPlayer = Players.LocalPlayer
local cars: { [Model]: CarLamps.Lamps } = {}
local waiting: { [Model]: true } = {}
local mode: Rules.Mode = "Auto"
local highBeam = false
local indicator: Rules.Side? = nil
local indicatorSince = 0
local cabin = false
local rainLightOn = false
local rainLightSince = 0
local pad: Rules.Press = { since = nil, spent = false }
local sinceScan = 0

local function track(model: Instance)
	if not model:IsA("Model") or cars[model] then
		return
	end
	-- A car streamed in without its light pieces yet is picked up on a later scan.
	local entry = Catalog.of(model)
	local lamps = if entry then CarLamps.build(model, entry) else nil
	if lamps then
		cars[model] = lamps
		waiting[model] = nil
	else
		waiting[model] = true
	end
end

local function drivenModel(): Model?
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	local model = seat and seat.Parent
	return if model and model:IsA("Model") and cars[model] then model else nil
end

local function number(model: Model, name: string, default: number): number
	local value = model:GetAttribute(name)
	return if typeof(value) == "number" then value else default
end

local function held(keys: { Enum.KeyCode }): boolean
	for _, key in keys do
		if UserInputService:IsKeyDown(key) then
			return true
		end
	end
	return false
end

local function toggleIndicator(side: Rules.Side)
	indicator = if indicator == side then nil else side
	indicatorSince = os.clock()
end

-- The cabin light's controls do nothing in a car whose model has no cabin lamp.
local function hasCabinLight(model: Model?): boolean
	local entry = model and Catalog.of(model)
	return entry ~= nil and entry.model.cabinLight ~= nil
end

local function padButton(now: number)
	local down = false
	for _, key in Controls.LIGHTS_PAD do
		down = down or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, key)
	end
	local driving = drivenModel()
	local gesture = Rules.press(pad, down and driving ~= nil, now, Config.PAD_HOLD_SECONDS)
	if gesture == "Tap" then
		mode, highBeam = Rules.nextPadLights(mode, highBeam)
	elseif gesture == "Hold" and hasCabinLight(driving) then
		cabin = not cabin
	end
end

local function update(dt: number)
	sinceScan += dt
	if sinceScan > 1 then
		sinceScan = 0
		for model in waiting do
			track(model)
		end
	end
	local now = os.clock()
	padButton(now)
	local night = StreetLamps.isNight(Lighting.ClockTime, StreetLights.DUSK, StreetLights.DAWN)
	local daylight = Rules.daylight(Lighting.Brightness, Config.NIGHT_BRIGHTNESS, Config.DAY_BRIGHTNESS)
	local rain = Workspace:GetAttribute("RainIntensity")
	local serverNow = Workspace:GetServerTimeNow()
	local driven = drivenModel()
	local rainSwitch = driven ~= nil and driven:GetAttribute("RainLightOn") == true
	if rainSwitch ~= rainLightOn then
		rainLightOn = rainSwitch
		rainLightSince = now
	end
	for model, lamps in cars do
		if model.Parent == nil then
			cars[model] = nil
			continue
		end
		local mine = model == driven
		local entry = Catalog.of(model)
		local flashing = mine
			and entry ~= nil
			and entry.switches.highBeam == "Flash"
			and held(Controls.HIGH_BEAM)
		local rainLight = entry and entry.lights.rain
		local lit = Rules.decide({
			running = entry ~= nil
				and CarEntry.startup(entry, CarState.read(model), serverNow).sincePress ~= nil,
			mode = if mine then mode else "Auto",
			highBeam = mine and highBeam,
			flash = flashing,
			night = night,
			rain = if typeof(rain) == "number" then rain else 0,
			brake = if mine then number(model, "Brake", 0) else 0,
			gear = if mine then number(model, "Gear", 1) else 1,
			indicator = if mine then indicator else nil,
			indicating = now - indicatorSince,
			cabin = mine and cabin,
			rainLight = mine and rainLight ~= nil and rainLightOn,
			rainLightFor = now - rainLightSince,
		}, Config.TUNING, rainLight and rainLight.pattern)
		-- Shadowed lights cost a pass each; only the car this player drives casts them.
		CarLamps.apply(lamps, lit, daylight, mine)
		if mine then
			-- For the HUD's tell-tales; local, like every readout on the driven car.
			model:SetAttribute("HeadlightsOn", lit.headlights)
			model:SetAttribute("HighBeamOn", lit.highBeam)
			model:SetAttribute("IndicatorLeft", lit.left)
			model:SetAttribute("IndicatorRight", lit.right)
		end
	end
end

local Controller = {}

function Controller.start()
	for _, model in CollectionService:GetTagged(CarRig.TAG) do
		track(model)
	end
	CollectionService:GetInstanceAddedSignal(CarRig.TAG):Connect(track)
	CollectionService:GetInstanceRemovedSignal(CarRig.TAG):Connect(function(model)
		if model:IsA("Model") then
			waiting[model] = nil
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or drivenModel() == nil then
			return
		end
		local key = input.KeyCode
		if table.find(Controls.HEADLIGHTS, key) then
			mode = Rules.nextMode(mode)
		elseif table.find(Controls.HIGH_BEAM, key) then
			local driving = drivenModel()
			local entry = driving and Catalog.of(driving)
			if entry and entry.switches.highBeam == "Toggle" then
				highBeam = not highBeam
			end
		elseif table.find(Controls.CABIN_LIGHT, key) and hasCabinLight(drivenModel()) then
			cabin = not cabin
		elseif table.find(Controls.INDICATOR_LEFT, key) then
			toggleIndicator("Left")
		elseif table.find(Controls.INDICATOR_RIGHT, key) then
			toggleIndicator("Right")
		end
	end)
	RunService.Heartbeat:Connect(update)
end

return Controller
