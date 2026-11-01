--!strict
--[[
	Drives the car the local player sits in. The server hands this client the car's assembly,
	so the physics runs here every frame against the player's own input, with no round trip.
	The car's live readings go out as attributes on its model for the camera and the HUD. The
	drive-mode knob and the pit limiter act when the driver's hand works them, on a car whose hand
	gestures play them (Rig/ControlPresses), and at their key otherwise. T steps the gearbox modes
	(Rules/GearboxModes); a stall goes to the server and back (Rules/Stall).
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
local ControlPresses = require(script.Parent.Parent.Rig.ControlPresses)
local Controls = require(ReplicatedStorage.Shared.Config.Controls)
local DriveModes = require(ReplicatedStorage.Shared.Rules.DriveModes)
local DriverAssists = require(ReplicatedStorage.Shared.Rules.DriverAssists)
local DrivingConfig = require(ReplicatedStorage.Shared.Config.Driving)
local Gearbox = require(ReplicatedStorage.Shared.Vehicle.Gearbox)
local GearboxModes = require(ReplicatedStorage.Shared.Rules.GearboxModes)
local InputHelp = require(ReplicatedStorage.Shared.Config.InputHelp)
local Interface = require(ReplicatedStorage.Shared.Vehicle.Interface)
local Net = require(ReplicatedStorage.Kit.Net)
local PitLimiter = require(ReplicatedStorage.Shared.Rules.PitLimiter)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ShiftSync = require(ReplicatedStorage.Shared.Rules.ShiftSync)
local Stall = require(ReplicatedStorage.Shared.Rules.Stall)
local TyreSmoke = require(ReplicatedStorage.Shared.Rules.TyreSmoke)
local TyreSmokeConfig = require(ReplicatedStorage.Shared.Config.TyreSmoke)
local Types = require(ReplicatedStorage.Shared.Config.Cars.Types)
local VehicleModel = require(ReplicatedStorage.Shared.Vehicle.Model)
local VehicleRunner = require(ReplicatedStorage.Shared.Car.VehicleRunner)

local localPlayer = Players.LocalPlayer
local runner: VehicleRunner.Runner? = nil
local connection: RBXScriptConnection? = nil
local pressed = { shiftUp = false, shiftDown = false }
local gearboxMode: Gearbox.GearboxMode = "auto"
-- The driver uses the keyboard (InputHelp's preset), where the clutch mode is offered.
local keyboard = true
-- The entry and model of the car being driven.
local driven: Catalog.Entry? = nil
local drivenModel: Model? = nil
-- The drive mode each car was left in, by its name, so a car keeps it from one drive to the next.
local chosenMode: { [string]: Types.DrivingMode } = {}
local escSwitch = DriverAssists.newSwitch()
local pitLimiter = PitLimiter.newState()
local tyreReadings: { TyreSmoke.Wheel } = {}
local stall = Stall.newTracker()
local STALL_TIMING: Stall.Timing = table.freeze({
	resendAfter = DrivingConfig.STALL_RESEND_SECONDS,
	resumeAfter = DrivingConfig.STALL_RESUME_SECONDS,
})
-- Shifts refused with the player's clutch up, counted for the car's grind (Rules/GearboxModes).
local grinds = 0
-- The gear of the frame before, on a car with an H-pattern manual, for the instant a shift engages.
local lastGear: number? = nil

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
		-- The same key: held through a bend fast enough it drifts the car, otherwise it is the
		-- handbrake (Vehicle/Drift).
		drift = held(Controls.HANDBRAKE),
		shiftUp = pressed.shiftUp,
		shiftDown = pressed.shiftDown,
		clutchPedal = if held(Controls.CLUTCH) then 1 else 0,
		gearboxMode = gearboxMode,
		drivingMode = mode,
		assists = DriverAssists.assists(escSwitch.off, mode, tuning),
	}
	pressed.shiftUp, pressed.shiftDown = false, false
	return input
end

-- Until the car is started, shut and its driver settled in (Rules/CarEntry), it stays parked:
-- the runner still holds it on its suspension, and a tap meant for a pedal or a paddle is dropped.
-- A car that stalled rolls on with the driver's input (Rules/Stall).
local function gated(
	entry: Catalog.Entry,
	model: Model,
	current: VehicleRunner.Runner,
	input: Interface.DriverInput
): Interface.DriverInput
	local drivable = CarEntry.drivable(entry, CarState.read(model), Workspace:GetServerTimeNow())
	if Stall.drives(drivable, Gearbox.stalled(current.state.gearbox)) then
		return input
	end
	input.throttle, input.brake, input.steer, input.handbrake = 0, 0, 0, 1
	input.shiftUp, input.shiftDown = false, false
	return input
end

-- The driven car's readouts from the frame before, for the switches that act on them.
local function published(model: Model, name: string): number
	local value = model:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

-- On a car with a pit limiter: releases it out of the arming gear and caps the throttle while it
-- is armed.
local function limitPit(
	entry: Catalog.Entry,
	model: Model,
	input: Interface.DriverInput
): Interface.DriverInput
	local tuning = entry.switches.pitLimiter
	if tuning then
		PitLimiter.update(pitLimiter, tuning, published(model, "Gear"), modeOf(entry))
		input.throttle = PitLimiter.throttle(pitLimiter, tuning, input.throttle, published(model, "SpeedKmh"))
	end
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
	model:SetAttribute("Drift", telemetry.drift)
	model:SetAttribute("DriftTarget", math.deg(telemetry.driftTarget))
	model:SetAttribute("PitLimiter", pitLimiter.armed)
	grinds = GearboxModes.grinds(grinds, telemetry.shiftRefusal)
	model:SetAttribute("ShiftGrinds", grinds)
	local entry = driven
	local manual = if entry then entry.physics.gearbox.manual else nil
	if entry and manual and entry.physics.gearbox.kind == "manual" then
		local readout = ShiftSync.readout(telemetry, current.state.gearbox.hbox, manual.gates)
		model:SetAttribute("ClutchPedal", readout.ClutchPedal)
		model:SetAttribute("ClutchFoot", readout.ClutchFoot)
		model:SetAttribute("ShiftHand", readout.ShiftHand)
		model:SetAttribute("ShiftFrom", readout.ShiftFrom)
		model:SetAttribute("ShiftTo", readout.ShiftTo)
		model:SetAttribute("ShiftElapsed", readout.ShiftElapsed)
		model:SetAttribute("LeverColumn", readout.LeverColumn)
		model:SetAttribute("LeverRow", readout.LeverRow)
		model:SetAttribute("KnobDown", readout.KnobDown)
		if ShiftSync.engaged(lastGear, telemetry) then
			ControlPresses.fire(model, "SHIFT")
		end
		lastGear = telemetry.gear
	end
	-- Per tyre, for the smoke: read from the model, never written back.
	for wheel, reading in TyreSmoke.measure(current.state, result.wheels, tyreReadings) do
		model:SetAttribute(TyreSmokeConfig.SLIP_ATTRIBUTES[wheel], reading.slip)
		model:SetAttribute(TyreSmokeConfig.SLIDE_ATTRIBUTES[wheel], reading.slide)
	end
end

local function stop()
	-- ESC is back on for the next drive, as at a new ignition cycle (the car's assists).
	escSwitch = DriverAssists.newSwitch()
	pitLimiter = PitLimiter.newState()
	stall = Stall.newTracker()
	grinds = 0
	lastGear = nil
	driven = nil
	drivenModel = nil
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
	drivenModel = model
	keyboard = help == InputHelp.keyboard
	gearboxMode = GearboxModes.valid(entry.physics.gearbox, gearboxMode, keyboard)
	connection = RunService.PreSimulation:Connect(function(dt: number)
		local mode = modeOf(entry)
		local input = limitPit(entry, model, readInput(entry, mode))
		local result = VehicleRunner.step(current, gated(entry, model, current, input), dt)
		VehicleRunner.animate(current, dt)
		publish(model, result, current, mode)
		local engineOn = CarState.read(model).engine == "On"
		local action = Stall.step(stall, result.telemetry.stalled, engineOn, os.clock(), STALL_TIMING)
		if action == "Report" then
			Net.send(Remotes.CAR_ACTION, { car = model, action = "Stall" })
		elseif action == "Restart" then
			-- The key start already asked for the clutch down (Rules/CarEntry.startRefusal); a resume
			-- follows the engine the server shows running.
			VehicleModel.restart(current.state, 1)
		end
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

-- One press of the drive-mode knob or the pit limiter takes effect.
local function apply(control: string)
	local entry, model = driven, drivenModel
	if entry == nil or model == nil then
		return
	end
	if control == "DRIVING_MODE" then
		chosenMode[entry.physics.name] = DriveModes.after(entry.physics.modeOrder, modeOf(entry))
	elseif control == "PIT_LIMITER" then
		local tuning = entry.switches.pitLimiter
		if tuning then
			PitLimiter.press(
				pitLimiter,
				tuning,
				published(model, "Gear"),
				published(model, "SpeedKmh"),
				modeOf(entry)
			)
		end
	end
end

-- A key press of `control`: at once, unless the car's hand gestures play it (Rig/ControlPresses),
-- when it takes effect as the hand works it.
local function pressSwitch(control: string)
	local model = drivenModel
	if model and not ControlPresses.claimed(model, control) then
		apply(control)
	end
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
		elseif contains(Controls.GEARBOX_MODE, key) and driven then
			gearboxMode = GearboxModes.after(driven.physics.gearbox, gearboxMode, keyboard)
		elseif contains(Controls.DRIVING_MODE, key) then
			pressSwitch("DRIVING_MODE")
		elseif contains(Controls.PIT_LIMITER, key) then
			pressSwitch("PIT_LIMITER")
		end
	end)
	ControlPresses.connect(function(model: Model, name: string, presses: number)
		if model == drivenModel and ControlPresses.claimed(model, name) then
			for _ = 1, presses do
				apply(name)
			end
		end
	end)
	if localPlayer.Character then
		task.spawn(onCharacter, localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(onCharacter)
end

return Controller
