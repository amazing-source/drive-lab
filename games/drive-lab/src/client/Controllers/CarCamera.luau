--!strict
--[[
	The driving cameras, while the local player drives: Chase (behind, hung off the rear axle:
	ChaseView), Cockpit (the driver's eyes, fixed in the car:
	the owner wants the head still while driving, 2026-10-27) and Hood. V or the right stick's click cycles them; the right mouse
	button or the right stick looks around, easing back on release. The current view is published
	on the camera as "DriveLabView" for the weather effects, "OnFoot" when not driving. On top
	of each view's placement: the vibrations of Rules/CarShake, noise around the place computed
	this frame (never a lag), and each view's field of view widening under acceleration, held
	through a gear change, and with speed.
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CameraFeel = require(ReplicatedStorage.Shared.Config.CameraFeel)
local CarCamera = require(ReplicatedStorage.Shared.Config.CarCamera)
local CarRig = require(ReplicatedStorage.Shared.Car.CarRig)
local CarShake = require(ReplicatedStorage.Shared.Rules.CarShake)
local CarShakeConfig = require(ReplicatedStorage.Shared.Config.CarShake)
local Catalog = require(ReplicatedStorage.Shared.Config.Cars.Catalog)
local ChaseView = require(script.Parent.ChaseView)
local Controls = require(ReplicatedStorage.Shared.Config.Controls)
local DriveModes = require(ReplicatedStorage.Shared.Rules.DriveModes)
local Rules = require(ReplicatedStorage.Shared.Rules.CarCamera)
local Units = require(ReplicatedStorage.Shared.Units)

local EntryView = require(script.Parent.EntryView)

type Drive = {
	model: Model,
	chassis: BasePart,
	bodyRaise: number,
	views: CarCamera.CarViews,
	modes: { string },
}

local localPlayer = Players.LocalPlayer
local viewIndex = 1
local active = false
local looking = false
local lookYaw, lookPitch = 0, 0
-- How far the player has moved the cockpit eye from the car's own, metres; kept for the session.
local eyeForward, eyeUp = 0, 0
local hidden: { BasePart } = {}
local shake = CarShake.new()
local kick = Rules.newKick()
-- Degrees the view is widened by the speed, eased.
local widen = 0
local chaseState = ChaseView.new()

local function studs(metres: number): number
	return Units.metresToStuds(metres)
end

local function currentDrive(): Drive?
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	local model = seat and seat.Parent
	if model == nil or not model:IsA("Model") or not CollectionService:HasTag(model, CarRig.TAG) then
		return nil
	end
	local chassis = model:FindFirstChild("Chassis")
	local entry = Catalog.of(model)
	if chassis == nil or not chassis:IsA("BasePart") or entry == nil then
		return nil
	end
	return {
		model = model,
		chassis = chassis,
		bodyRaise = entry.model.bodyRaise,
		views = entry.camera,
		modes = entry.physics.modeOrder,
	}
end

local function anyHeld(keys: { Enum.KeyCode }): boolean
	for _, key in keys do
		if UserInputService:IsKeyDown(key) then
			return true
		end
	end
	return false
end

local function number(model: Model, name: string): number
	local value = model:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

-- The local head, torso and whatever they wear vanish in the cockpit, as in Roblox's own first
-- person: the eye sits inside the head, and the blocky torso would fill the bottom of the view.
-- The drawn arms stay. Set every frame, since Roblox's camera transparency code also writes these.
local function hideHead(hide: boolean)
	if not hide then
		for _, part in hidden do
			part.LocalTransparencyModifier = 0
		end
		table.clear(hidden)
		return
	end
	local character = localPlayer.Character
	if character == nil then
		return
	end
	if #hidden == 0 then
		for _, part in character:GetDescendants() do
			if
				part:IsA("BasePart")
				and (
					part.Name == "Head"
					or part.Name == "Torso"
					or part:FindFirstAncestorOfClass("Accessory")
				)
			then
				table.insert(hidden, part)
			end
		end
	end
	for _, part in hidden do
		part.LocalTransparencyModifier = 1
	end
end

local function release(camera: Camera)
	if not active then
		camera:SetAttribute("DriveLabView", "OnFoot")
		return
	end
	active, looking = false, false
	lookYaw, lookPitch = 0, 0
	shake, kick, chaseState = CarShake.new(), Rules.newKick(), ChaseView.new()
	widen = 0
	hideHead(false)
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	local humanoid = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
	camera.CameraType = Enum.CameraType.Custom
	if humanoid then
		camera.CameraSubject = humanoid
	end
	camera.FieldOfView = CameraFeel.BASE_FOV
	camera:SetAttribute("DriveLabView", "OnFoot")
end

local function chase(drive: Drive): CFrame
	return ChaseView.place(chaseState, drive.chassis.CFrame, lookYaw, lookPitch)
end

local function cockpit(drive: Drive): CFrame
	local frame = drive.chassis.CFrame
	local character = localPlayer.Character
	local headPart = character and character:FindFirstChild("Head")
	local base = if headPart and headPart:IsA("BasePart") then headPart.Position else frame.Position
	local at = drive.views.eye
	local eye = base
		+ frame.LookVector * studs(at.forward + eyeForward)
		+ frame.UpVector * studs(at.up + eyeUp)
	return CFrame.new(eye) * frame.Rotation * CFrame.Angles(0, lookYaw, 0) * CFrame.Angles(lookPitch, 0, 0)
end

local function hood(drive: Drive): CFrame
	local at = drive.views.hood
	local offset = CFrame.new(0, studs(at.up + drive.bodyRaise), -studs(at.forward))
	return drive.chassis.CFrame * offset * CFrame.Angles(lookPitch, 0, 0) * CFrame.Angles(0, lookYaw, 0)
end

local function easeLook(dt: number)
	local pad = UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)
	for _, state in pad do
		if
			state.KeyCode == Enum.KeyCode.Thumbstick2
			and state.Position.Magnitude > Controls.STICK_DEADZONE
		then
			lookYaw = -state.Position.X * CarCamera.MAX_LOOK_YAW
			lookPitch = state.Position.Y * CarCamera.MAX_LOOK_PITCH
			return
		end
	end
	if not looking then
		local share = Rules.blend(dt, CarCamera.LOOK_RETURN_HALF_LIFE)
		lookYaw -= lookYaw * share
		lookPitch -= lookPitch * share
	end
end

-- Every frame in every view, getting in and out included, so neither the chase nor the kick is
-- stale when it shows.
local function follow(drive: Drive, dt: number)
	ChaseView.step(chaseState, drive.model, drive.chassis.CFrame, drive.chassis.AssemblyLinearVelocity, dt)
	Rules.stepKick(kick, Rules.kickTarget(number(drive.model, "LongitudinalG")), dt)
	widen = Rules.stepSpeedWiden(widen, Rules.speedTarget(number(drive.model, "SpeedKmh")), dt)
end

local function update(dt: number)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	local drive = currentDrive()
	if drive == nil then
		release(camera)
		return
	end
	active = true
	camera.CameraType = Enum.CameraType.Scriptable
	follow(drive, dt)
	easeLook(dt)
	local view: CarCamera.View = CarCamera.VIEWS[viewIndex]
	hideHead(view == "Cockpit")
	-- Getting in or out, EntryView follows the body and eases into or out of the view.
	local placed = EntryView.place(
		view,
		drive.model,
		if view == "Chase" then chase(drive) elseif view == "Cockpit" then cockpit(drive) else hood(drive),
		camera.CFrame
	)
	local model = drive.model
	local speed = number(model, "SpeedKmh")
	local mode = DriveModes.current(drive.modes, model:GetAttribute("DrivingMode"))
	local offset = CarShake.step(shake, {
		view = view,
		speedKmh = speed,
		throttle = number(model, "Throttle"),
		longitudinalG = number(model, "LongitudinalG"),
		gear = number(model, "Gear"),
		shiftScale = drive.views.shiftKick[mode],
	}, dt, CarShakeConfig)
	camera.CFrame = placed * CFrame.Angles(offset.pitch, offset.yaw, offset.roll)
		+ placed.UpVector * studs(offset.lift)
	camera.FieldOfView = Rules.fieldOfView(view, kick.degrees, widen)
	camera:SetAttribute("DriveLabView", view)
end

local Controller = {}

function Controller.start()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not active then
			return
		end
		if table.find(Controls.CAMERA_VIEW, input.KeyCode) then
			viewIndex = viewIndex % #CarCamera.VIEWS + 1
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			looking = true
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 and looking then
			looking = false
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if
			active
			and input.UserInputType == Enum.UserInputType.MouseWheel
			and CarCamera.VIEWS[viewIndex] == "Cockpit"
		then
			local range = CarCamera.EYE_RANGE
			local notch = math.sign(input.Position.Z) * range.step
			local drive = currentDrive()
			local clutchMode = drive ~= nil and drive.model:GetAttribute("GearboxMode") == "manualClutch"
			local move = Rules.eyeScroll(
				UserInputService:IsKeyDown(Enum.KeyCode.LeftShift),
				clutchMode and anyHeld(Controls.CLUTCH)
			)
			if move == "Height" then
				eyeUp = math.clamp(eyeUp + notch, range.up[1], range.up[2])
			elseif move == "Forward" then
				eyeForward = math.clamp(eyeForward + notch, range.forward[1], range.forward[2])
			end
		end
		if looking and input.UserInputType == Enum.UserInputType.MouseMovement then
			lookYaw = math.clamp(
				lookYaw - input.Delta.X * CarCamera.LOOK_SENSITIVITY,
				-CarCamera.MAX_LOOK_YAW,
				CarCamera.MAX_LOOK_YAW
			)
			lookPitch = math.clamp(
				lookPitch - input.Delta.Y * CarCamera.LOOK_SENSITIVITY,
				-CarCamera.MAX_LOOK_PITCH,
				CarCamera.MAX_LOOK_PITCH
			)
		end
	end)
	-- After Roblox's camera script, which leaves a Scriptable camera alone.
	RunService:BindToRenderStep("CarCamera", Enum.RenderPriority.Camera.Value + 2, update)
end

return Controller
