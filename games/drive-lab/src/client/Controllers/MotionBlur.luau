--!strict
--[[
	The blur of a turning camera (Rules/MotionBlur, Config/MotionBlur), on a BlurEffect of its
	own (the strongest blur in Lighting wins, so the rain's lighter one is never weakened). While
	driving, the turn is measured inside the car: the car stays still on screen in every driving
	view and the cabin moves with the eye, so only looking around blurs, never the car's own
	yaw. On foot it is the camera's turn in the world. The speed's blur is the depth of field's
	near blur, in Atmosphere/Optics, which owns the one DepthOfFieldEffect.
]]
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CarRig = require(ReplicatedStorage.Shared.Car.CarRig)
local Config = require(ReplicatedStorage.Shared.Config.MotionBlur)
local Rules = require(ReplicatedStorage.Shared.Rules.MotionBlur)

-- Under this many pixels the blur is switched off rather than drawn for nothing.
local OFF_BELOW = 0.05

local localPlayer = Players.LocalPlayer
local blur: BlurEffect? = nil
local size = 0
local last: CFrame? = nil
local lastCar: BasePart? = nil

local function drivenChassis(): BasePart?
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	local model = seat and seat.Parent
	if model == nil or not model:IsA("Model") or not CollectionService:HasTag(model, CarRig.TAG) then
		return nil
	end
	local chassis = model:FindFirstChild("Chassis")
	return if chassis and chassis:IsA("BasePart") then chassis else nil
end

-- Degrees between two orientations, 0 to 180.
local function degreesBetween(a: CFrame, b: CFrame): number
	local _, angle = (a.Rotation:Inverse() * b.Rotation):ToAxisAngle()
	angle = math.abs(angle) % (2 * math.pi)
	return math.deg(if angle > math.pi then 2 * math.pi - angle else angle)
end

local function update(dt: number)
	local effect, camera = blur, Workspace.CurrentCamera
	if effect == nil or camera == nil then
		return
	end
	local chassis = drivenChassis()
	local frame = if chassis then chassis.CFrame:ToObjectSpace(camera.CFrame) else camera.CFrame
	-- Getting in or out changes what the turn is measured against: no turn that frame.
	local previous = if chassis == lastCar then last else nil
	last, lastCar = frame, chassis
	local rate = if previous
		then Rules.turnRate(degreesBetween(previous, frame), dt, Config.ROTATION.cut)
		else nil
	local target = if rate then Rules.rotationSize(rate, Config.ROTATION) else 0
	size = Rules.follow(size, target, dt, Config.ROTATION)
	local on = size >= OFF_BELOW
	if effect.Enabled ~= on then
		effect.Enabled = on
	end
	if on then
		effect.Size = size
	end
end

local Controller = {}

function Controller.start()
	local effect = Instance.new("BlurEffect")
	effect.Name = "DriveLabMotionBlur"
	effect.Size = 0
	effect.Enabled = false
	effect.Parent = Lighting
	blur = effect
	RunService:BindToRenderStep("DriveLabMotionBlur", Enum.RenderPriority.Camera.Value + 4, update)
end

return Controller
