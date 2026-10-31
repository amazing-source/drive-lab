--!strict
--[[
	The driven car's switches that not every car has (Config/CarSwitches): the wiper and its
	washer, the rain light, the display's pages and the pit radio. A key does nothing in a car
	without its switch. The state is published on the car's model for its lamps, display, effects
	and sounds (WiperOn, WiperSpeed, WiperSweep, Washing, RainLightOn, DisplayPage, RadioTalking);
	like every readout on the driven car, it is local, and it is cleared when the driver gets out. A
	car that is got into again starts with them off and on its first page. On a car whose hand
	gestures play a switch (Rig/ControlPresses), its press acts when the hand works it and the
	washer runs while the thumb holds its button; any other switch acts at its key.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CarRig = require(ReplicatedStorage.Shared.Car.CarRig)
local Catalog = require(ReplicatedStorage.Shared.Config.Cars.Catalog)
local ControlPresses = require(script.Parent.Parent.Rig.ControlPresses)
local Controls = require(ReplicatedStorage.Shared.Config.Controls)
local Wiper = require(ReplicatedStorage.Shared.Rules.Wiper)

type Drive = {
	model: Model,
	entry: Catalog.Entry,
	-- Nil on a car without a wiper.
	wiper: Wiper.State?,
	rainLight: boolean,
	page: number,
	radio: boolean,
}

-- The switches a press steps once, by their Config/Controls names.
local SWITCH_KEYS: { [string]: { Enum.KeyCode } } =
	{ WIPER = Controls.WIPER, RAIN_LIGHT = Controls.RAIN_LIGHT, DISPLAY_PAGE = Controls.DISPLAY_PAGE }

local ATTRIBUTES =
	{ "WiperOn", "WiperSpeed", "WiperSweep", "Washing", "RainLightOn", "DisplayPage", "RadioTalking" }

local localPlayer = Players.LocalPlayer
local drive: Drive? = nil
-- Keys held since a press the game saw: a key typed into a text box (the chat) holds nothing.
local down: { [Enum.KeyCode]: true } = {}

local function held(keys: { Enum.KeyCode }): boolean
	for _, key in keys do
		if down[key] then
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
	local model, switches, wiper = current.model, current.entry.switches, current.wiper
	model:SetAttribute("WiperOn", if wiper then wiper.speed > 0 else nil)
	model:SetAttribute("WiperSpeed", if wiper then wiper.speed else nil)
	model:SetAttribute("WiperSweep", if wiper then Wiper.sweep(wiper) else nil)
	model:SetAttribute("Washing", if wiper then wiper.washing else nil)
	model:SetAttribute("RainLightOn", if switches.rainLight then current.rainLight else nil)
	model:SetAttribute("DisplayPage", if switches.displayPages then current.page else nil)
	model:SetAttribute("RadioTalking", if switches.radio then current.radio else nil)
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
	local tuning = entry.switches.wiper
	local fresh: Drive = {
		model = model,
		entry = entry,
		wiper = if tuning then Wiper.newState(tuning) else nil,
		rainLight = false,
		page = 1,
		radio = false,
	}
	drive = fresh
	return fresh
end

local function update(dt: number)
	local current = follow()
	if current == nil then
		return
	end
	local tuning, wiper = current.entry.switches.wiper, current.wiper
	if tuning and wiper then
		local model = current.model
		local washing = if ControlPresses.claimed(model, "WASHER")
			then ControlPresses.holding(model, "WASHER")
			else held(Controls.WASHER)
		Wiper.step(wiper, tuning, washing, dt)
	end
	current.radio = held(Controls.RADIO)
	publish(current)
end

-- `presses` presses of the switch `control` take effect.
local function apply(current: Drive, control: string, presses: number)
	local switches = current.entry.switches
	local tuning, wiper = switches.wiper, current.wiper
	for _ = 1, presses do
		if control == "WIPER" and tuning and wiper then
			Wiper.cycle(wiper, tuning)
		elseif control == "RAIN_LIGHT" and switches.rainLight then
			current.rainLight = not current.rainLight
		elseif control == "DISPLAY_PAGE" and switches.displayPages then
			current.page = current.page % switches.displayPages + 1
		end
	end
end

-- The switch a key presses, if it is one of these.
local function switchOf(key: Enum.KeyCode): string?
	for control, keys in SWITCH_KEYS do
		if table.find(keys, key) then
			return control
		end
	end
	return nil
end

local Controller = {}

function Controller.start()
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed then
			down[input.KeyCode] = true
		end
		local current = follow()
		if processed or current == nil then
			return
		end
		local control = switchOf(input.KeyCode)
		if control and not ControlPresses.claimed(current.model, control) then
			apply(current, control, 1)
		end
	end)
	ControlPresses.connect(function(model: Model, name: string, presses: number)
		local current = drive
		if current and current.model == model and ControlPresses.claimed(model, name) then
			apply(current, name, presses)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		down[input.KeyCode] = nil
	end)
	UserInputService.WindowFocusReleased:Connect(function()
		table.clear(down)
	end)
	RunService.Heartbeat:Connect(update)
end

return Controller
