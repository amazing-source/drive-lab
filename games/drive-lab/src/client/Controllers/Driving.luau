--!strict
--[[
	Drives the car the local player sits in. The server hands this client the car's assembly,
	so the physics runs here every frame against the player's own input, with no round trip.
	The car's live readings go out as attributes on its model for the camera and the HUD.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CarEntry = require(ReplicatedStorage.Shared.Rules.CarEntry)
local CarRig = require(ReplicatedStorage.Shared.Car.CarRig)
local CarState = require(ReplicatedStorage.Shared.Car.CarState)
local Catalog = require(ReplicatedStorage.Shared.Config.Cars.Catalog)
local Controls = require(ReplicatedStorage.Shared.Config.Controls)
local InputHelp = require(ReplicatedStorage.Shared.Config.InputHelp)
local Interface = require(ReplicatedStorage.Shared.Vehicle.Interface)
local Types = require(ReplicatedStorage.Shared.Config.Cars.Types)
local VehicleRunner = require(ReplicatedStorage.Shared.Car.VehicleRunner)

local MODES: { Types.DrivingMode } = { "Strada", "Sport", "Corsa" }

local localPlayer = Players.LocalPlayer
local runner: VehicleRunner.Runner? = nil
local connection: RBXScriptConnection? = nil
local pressed = { shiftUp = false, shiftDown = false }
local gearboxMode: "auto" | "manual" = "auto"
local modeIndex = 1

local function held(keys: { Enum.KeyCode }): boolean
	for _, key in keys do
		if
			UserInputService:IsKeyDown(key)
			or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, key)
		then
			return true
		end
	end
	return false
end

local function contains(keys: { Enum.KeyCode }, key: Enum.KeyCode): boolean
	return table.find(keys, key) ~= nil
end

local function gamepadAxes(): (number, number, number)
	local throttle, brake, steer = 0, 0, 0
	if not UserInputService:GetGamepadConnected(Enum.UserInputType.Gamepad1) then
		return throttle, brake, steer
	end
	for _, state in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
		if state.KeyCode == Enum.KeyCode.ButtonR2 then
			throttle = state.Position.Z
		elseif state.KeyCode == Enum.KeyCode.ButtonL2 then
			brake = state.Position.Z
		elseif state.KeyCode == Enum.KeyCode.Thumbstick1 then
			local x = state.Position.X
			steer = if math.abs(x) < Controls.STICK_DEADZONE then 0 else x
		end
	end
	return throttle, brake, steer
end

local function readInput(): Interface.DriverInput
	local padThrottle, padBrake, padSteer = gamepadAxes()
	local keySteer = (if held(Controls.RIGHT) then 1 else 0) - (if held(Controls.LEFT) then 1 else 0)
	local input: Interface.DriverInput = {
		throttle = math.max(if held(Controls.THROTTLE) then 1 else 0, padThrottle),
		brake = math.max(if held(Controls.BRAKE) then 1 else 0, padBrake),
		steer = if keySteer ~= 0 then keySteer else padSteer,
		handbrake = if held(Controls.HANDBRAKE) then 1 else 0,
		shiftUp = pressed.shiftUp,
		shiftDown = pressed.shiftDown,
		gearboxMode = gearboxMode,
		drivingMode = MODES[modeIndex],
		assists = { abs = true, tc = true, esc = true },
	}
	pressed.shiftUp, pressed.shiftDown = false, false
	return input
end

-- Until the car is started, shut and its driver settled in (Rules/CarEntry), it stays parked:
-- the runner still holds it on its suspension, and a tap meant for a pedal or a paddle is dropped.
local function gated(model: Model, input: Interface.DriverInput): Interface.DriverInput
	if CarEntry.drivable(CarState.read(model), Workspace:GetServerTimeNow()) then
		return input
	end
	input.throttle, input.brake, input.steer, input.handbrake = 0, 0, 0, 1
	input.shiftUp, input.shiftDown = false, false
	return input
end

local function publish(model: Model, result: Interface.StepResult, current: VehicleRunner.Runner)
	local telemetry = result.telemetry
	model:SetAttribute("SpeedKmh", telemetry.speedKmh)
	model:SetAttribute("Rpm", telemetry.rpm)
	model:SetAttribute("Gear", telemetry.gear)
	model:SetAttribute("Throttle", telemetry.throttle)
	model:SetAttribute("Brake", telemetry.brake)
	model:SetAttribute("Steer", telemetry.steer)
	model:SetAttribute("LongitudinalG", current.longitudinalG)
	model:SetAttribute("LateralG", current.lateralG)
	model:SetAttribute("DrivingMode", MODES[modeIndex])
	model:SetAttribute("GearboxMode", gearboxMode)
	model:SetAttribute("Shifting", telemetry.shifting)
	model:SetAttribute("Limiter", telemetry.limiter)
	model:SetAttribute("Clutch", telemetry.clutch)
	model:SetAttribute("AbsActive", telemetry.absActive)
	model:SetAttribute("TcActive", telemetry.tcActive)
end

local function stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if runner then
		VehicleRunner.release(runner.rig)
		runner = nil
	end
end

local function start(seat: Seat)
	local model = seat:FindFirstAncestorOfClass("Model")
	local name = model and model:GetAttribute("Car")
	local entry = if typeof(name) == "string" then Catalog[name] else nil
	local rig = if model and entry then CarRig.find(model, entry.model) else nil
	if model == nil or entry == nil or rig == nil or rig.seat ~= seat then
		return
	end
	local help = if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled
		then InputHelp.gamepad
		else InputHelp.keyboard
	local current = VehicleRunner.new(rig, entry.physics, help)
	runner = current
	connection = RunService.PreSimulation:Connect(function(dt: number)
		local result = VehicleRunner.step(current, gated(model, readInput()), dt)
		VehicleRunner.animate(current, dt)
		publish(model, result, current)
	end)
end

local function onSeat(humanoid: Humanoid)
	stop()
	local seat = humanoid.SeatPart
	if seat and seat:IsA("Seat") and seat.Parent and seat.Parent:HasTag(CarRig.TAG) then
		start(seat)
	end
end

local function onCharacter(character: Model)
	stop()
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	if character.Parent == nil then
		return
	end
	humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
		onSeat(humanoid)
	end)
end

local Controller = {}

function Controller.start()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or runner == nil then
			return
		end
		local key = input.KeyCode
		if contains(Controls.SHIFT_UP, key) then
			pressed.shiftUp = true
		elseif contains(Controls.SHIFT_DOWN, key) then
			pressed.shiftDown = true
		elseif contains(Controls.GEARBOX_MODE, key) then
			gearboxMode = if gearboxMode == "auto" then "manual" else "auto"
		elseif contains(Controls.DRIVING_MODE, key) then
			modeIndex = modeIndex % #MODES + 1
		end
	end)
	if localPlayer.Character then
		task.spawn(onCharacter, localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(onCharacter)
end

return Controller
