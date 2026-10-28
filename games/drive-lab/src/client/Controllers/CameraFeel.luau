--!strict
--[[
	The on-foot camera: the field of view widens with ground speed, easing into a sprint and out
	of it. Roblox's camera script still places the camera; the orbit follows the mouse exactly,
	unsmoothed (the owner's call, 2026-10-27). Seated, this steps aside for the car's camera.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CameraFeel = require(ReplicatedStorage.Shared.Config.CameraFeel)
local Movement = require(ReplicatedStorage.Shared.Config.Movement)
local Rules = require(ReplicatedStorage.Shared.Rules.CameraFeel)

local localPlayer = Players.LocalPlayer
local fieldOfView: number? = nil

local function footing(): BasePart?
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or humanoid.SeatPart ~= nil or humanoid.Health <= 0 then
		return nil
	end
	return if root and root:IsA("BasePart") then root else nil
end

local function stepAside(camera: Camera)
	if fieldOfView then
		camera.FieldOfView = CameraFeel.BASE_FOV
	end
	fieldOfView = nil
end

local function widen(dt: number)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	local root = footing()
	if root == nil or camera.CameraType ~= Enum.CameraType.Custom then
		stepAside(camera)
		return
	end
	local velocity = root.AssemblyLinearVelocity
	local ground = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local wanted = Rules.fieldOfView(ground, Movement.WALK_SPEED, Movement.SPRINT_SPEED)
	local fov = fieldOfView or camera.FieldOfView
	fov += (wanted - fov) * Rules.blend(dt, CameraFeel.FOV_HALF_LIFE)
	fieldOfView = fov
	camera.FieldOfView = fov
end

local Controller = {}

function Controller.start()
	-- After Roblox's camera script, which would otherwise reset the field of view.
	RunService:BindToRenderStep("CameraFeel", Enum.RenderPriority.Camera.Value + 1, widen)
end

return Controller
