--!strict
--[[
	The driven car's switches that not every car has (Config/CarSwitches): the wiper and its
	washer, the rain light and the display's pages. A key does nothing in a car without its switch.
	The state is published on the car's model for its lamps, display and effects (WiperOn,
	WiperSweep, Washing, RainLightOn, DisplayPage); like every readout on the driven car, it is
	local, and it is cleared when the driver gets out. A car that is got into again starts with them
	off and on its first page.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CarRig = require(ReplicatedStorage.Shared.Car.CarRig)
local Catalog = require(ReplicatedStorage.Shared.Config.Cars.Catalog)
local Controls = require(ReplicatedStorage.Shared.Config.Controls)
local Wiper = require(ReplicatedStorage.Shared.Rules.Wiper)

type Drive = {
	model: Model,
	entry: Catalog.Entry,
	wiper: Wiper.State,
	rainLight: boolean,
	page: number,
}

local ATTRIBUTES = { "WiperOn", "WiperSweep", "Washing", "RainLightOn", "DisplayPage" }

local localPlayer = Players.LocalPlayer
local drive: Drive? = nil

local function held(keys: { Enum.KeyCode }): boolean
	for _, key in keys do
		if UserInputService:IsKeyDown(key) then
			return true
		end
	end
	return false
end

local function seatedModel(): Model?
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	local model = seat and seat.Parent
	return if model and model:IsA("Model") and model:HasTag(CarRig.TAG) then model else nil
end

local function publish(current: Drive)
	local model, switches = current.model, current.entry.switches
	local tuning = switches.wiper
	model:SetAttribute("WiperOn", if tuning then current.wiper.on else nil)
	model:SetAttribute("WiperSweep", if tuning then Wiper.sweep(current.wiper, tuning) else nil)
	model:SetAttribute("Washing", if tuning then current.wiper.washing else nil)
	model:SetAttribute("RainLightOn", if switches.rainLight then current.rainLight else nil)
	model:SetAttribute("DisplayPage", if switches.displayPages then current.page else nil)
end

-- Follows the seat: a new drive for each car got into, nothing while on foot.
local function follow(): Drive?
	local model = seatedModel()
	local current = drive
	if current and current.model == model then
		return current
	end
	if current then
		-- Out of the car: its switches go off with the driver.
		for _, name in ATTRIBUTES do
			current.model:SetAttribute(name, nil)
		end
	end
	local entry = model and Catalog.of(model)
	if model == nil or entry == nil then
		drive = nil
		return nil
	end
	local fresh: Drive =
		{ model = model, entry = entry, wiper = Wiper.newState(), rainLight = false, page = 1 }
	drive = fresh
	return fresh
end

local function update(dt: number)
	local current = follow()
	if current == nil then
		return
	end
	local tuning = current.entry.switches.wiper
	if tuning then
		Wiper.step(current.wiper, tuning, held(Controls.WASHER), dt)
	end
	publish(current)
end

local Controller = {}

function Controller.start()
	UserInputService.InputBegan:Connect(function(input, processed)
		local current = follow()
		if processed or current == nil then
			return
		end
		local key = input.KeyCode
		local switches = current.entry.switches
		if table.find(Controls.WIPER, key) and switches.wiper then
			Wiper.toggle(current.wiper)
		elseif table.find(Controls.RAIN_LIGHT, key) and switches.rainLight then
			current.rainLight = not current.rainLight
		elseif table.find(Controls.DISPLAY_PAGE, key) then
			local pages = switches.displayPages
			if pages then
				current.page = current.page % pages + 1
			end
		end
	end)
	RunService.Heartbeat:Connect(update)
end

return Controller
