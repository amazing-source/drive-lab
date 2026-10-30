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
local DriveModes = require(ReplicatedStorage.Shared.Rules.DriveModes)
local DriverAssists = require(ReplicatedStorage.Shared.Rules.DriverAssists)
local InputHelp = require(ReplicatedStorage.Shared.Config.InputHelp)
local Interface = require(ReplicatedStorage.Shared.Vehicle.Interface)
local TyreSmoke = require(ReplicatedStorage.Shared.Rules.TyreSmoke)
local TyreSmokeConfig = require(ReplicatedStorage.Shared.Config.TyreSmoke)
local Types = require(ReplicatedStorage.Shared.Config.Cars.Types)
local VehicleRunner = require(ReplicatedStorage.Shared.Car.VehicleRunner)

local localPlayer = Players.LocalPlayer
local runner: VehicleRunner.Runner? = nil
local connection: RBXScriptConnection? = nil
local pressed = { shiftUp = false, shiftDown = false }
local gearboxMode: "auto" | "manual" = "auto"
-- The entry of the car being driven.
local driven: Catalog.Entry? = nil
-- The drive mode each car was left in, by its name, so a car keeps it from one drive to the next.
local chosenMode: { [string]: Types.DrivingMode } = {}
local escSwitch = DriverAssists.newSwitch()
local tyreReadings: { TyreSmoke.Wheel } = {}

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

local function modeOf(entry: Catalog.Entry): Types.DrivingMode
	return DriveModes.current(entry.physics.modeOrder, chosenMode[entry.physics.name])
end

local function readInput(entry: Catalog.Entry, mode: Types.DrivingMode): Interface.DriverInput
	local padThrottle, padBrake, padSteer = gamepadAxes()
	local keySteer = (if held(Controls.RIGHT) then 1 else 0) - (if held(Controls.LEFT) then 1 else 0)
	local tuning = entry.assists
	local button = tuning.escButton
	if button then
		DriverAssists.updateSwitch(escSwitch, held(Controls.ESC_OFF), os.clock(), button)
	end
	local input: Interface.DriverInput = {
		throttle = math.max(if held(Controls.THROTTLE) then 1 else 0, padThrottle),
		brake = math.max(if held(Controls.BRAKE) then 1 else 0, padBrake),
		steer = if keySteer ~= 0 then keySteer else padSteer,
		handbrake = if held(Controls.HANDBRAKE) then 1 else 0,
		shiftUp = pressed.shiftUp,
		shiftDown = pressed.shiftDown,
		gearboxMode = gearboxMode,
		drivingMode = mode,
		assists = DriverAssists.assists(escSwitch.off, mode, tuning),
	}
	pressed.shiftUp, pressed.shiftDown = false, false
	return input
end

-- Until the car is started, shut and its driver settled in (Rules/CarEntry), it stays parked:
-- the runner still holds it on its suspension, and a tap meant for a pedal or a paddle is dropped.
local function gated(entry: Catalog.Entry, model: Model, input: Interface.DriverInput): Interface.DriverInput
	if CarEntry.drivable(entry, CarState.read(model), Workspace:GetServerTimeNow()) then
		return input
	end
	input.throttle, input.brake, input.steer, input.handbrake = 0, 0, 0, 1
	input.shiftUp, input.shiftDown = false, false
	return input
end

local function publish(
	model: Model,
	result: Interface.StepResult,
	current: VehicleRunner.Runner,
	mode: Types.DrivingMode
)
	local telemetry = result.telemetry
	model:SetAttribute("SpeedKmh", telemetry.speedKmh)
	model:SetAttribute("Rpm", telemetry.rpm)
	model:SetAttribute("Gear", telemetry.gear)
	model:SetAttribute("Throttle", telemetry.throttle)
	model:SetAttribute("Brake", telemetry.brake)
	model:SetAttribute("Steer", telemetry.steer)
	model:SetAttribute("LongitudinalG", current.longitudinalG)
	model:SetAttribute("LateralG", current.lateralG)
	model:SetAttribute("DrivingMode", mode)
	model:SetAttribute("GearboxMode", gearboxMode)
	model:SetAttribute("Shifting", telemetry.shifting)
	model:SetAttribute("Limiter", telemetry.limiter)
	model:SetAttribute("Clutch", telemetry.clutch)
	model:SetAttribute("AbsActive", telemetry.absActive)
	model:SetAttribute("TcActive", telemetry.tcActive)
	model:SetAttribute("EscActive", telemetry.escActive)
	model:SetAttribute("EscOff", escSwitch.off)
	model:SetAttribute("Launch", telemetry.launch)
	-- Per tyre, for the smoke: read from the model, never written back.
	for wheel, reading in TyreSmoke.measure(current.state, result.wheels, tyreReadings) do
		model:SetAttribute(TyreSmokeConfig.SLIP_ATTRIBUTES[wheel], reading.slip)
		model:SetAttribute(TyreSmokeConfig.SLIDE_ATTRIBUTES[wheel], reading.slide)
	end
end

local function stop()
	-- ESC is back on for the next drive, as at a new ignition cycle (the car's assists).
	escSwitch = DriverAssists.newSwitch()
	driven = nil
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
	local entry = if model then Catalog.of(model) else nil
	local rig = if model and entry then CarRig.find(model, entry.model) else nil
	if model == nil or entry == nil or rig == nil or rig.seat ~= seat then
		return
	end
	local help = if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled
		then InputHelp.gamepad
		else InputHelp.keyboard
	local current = VehicleRunner.new(rig, entry.physics, help)
	runner = current
	driven = entry
	connection = RunService.PreSimulation:Connect(function(dt: number)
		local mode = modeOf(entry)
		local result = VehicleRunner.step(current, gated(entry, model, readInput(entry, mode)), dt)
		VehicleRunner.animate(current, dt)
		publish(model, result, current, mode)
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
			local entry = driven
			if entry then
				chosenMode[entry.physics.name] = DriveModes.after(entry.physics.modeOrder, modeOf(entry))
			end
		end
	end)
	if localPlayer.Character then
		task.spawn(onCharacter, localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(onCharacter)
end

return Controller
