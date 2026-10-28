--!strict
--[[
	Turns every character's head toward where its player is looking. The local character
	follows the camera each frame; the others ease toward the angles the server replicates.
	Angles are measured against the torso, not the root, so a run that leans the body 45 degrees
	still has its head looking ahead rather than at the ground. Seated, the head faces straight
	ahead whatever the camera does: driving, only the arms move (the owner's call, 2026-10-27).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local HeadLook = require(ReplicatedStorage.Shared.Rules.HeadLook)
local JointLayer = require(script.Parent.Parent.Rig.JointLayer)
local Look = require(ReplicatedStorage.Shared.Config.Look)
local Net = require(ReplicatedStorage.Kit.Net)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

type Neck = { layer: JointLayer.JointLayer, angles: HeadLook.Angles }

local localPlayer = Players.LocalPlayer
local necks: { [Model]: Neck } = {}
-- Characters whose neck has not arrived yet (streaming, or a rig still assembling).
local pending: { [Model]: true } = {}
local AHEAD: HeadLook.Angles = table.freeze({ yaw = 0, pitch = 0 })
local lastSent: HeadLook.Angles = { yaw = 0, pitch = 0 }
local lastSentAt = 0

-- Yaw before pitch, so the head nods about its own turned axis.
local function turnFor(angles: HeadLook.Angles): CFrame
	return CFrame.Angles(0, angles.yaw, 0) * CFrame.Angles(angles.pitch, 0, 0)
end

local function forget(character: Model)
	necks[character] = nil
	pending[character] = nil
end

local function track(character: Model)
	pending[character] = true
	character.Destroying:Once(function()
		forget(character)
	end)
end

local function watch(player: Player)
	if player.Character then
		track(player.Character)
	end
	player.CharacterAdded:Connect(track)
	player.CharacterRemoving:Connect(forget)
end

local function cameraAngles(character: Model, neck: Neck): HeadLook.Angles?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.SeatPart then
		return AHEAD
	end
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return nil
	end
	local direction = neck.layer.parent.CFrame:VectorToObjectSpace(camera.CFrame.LookVector)
	return HeadLook.fromDirection(direction.X, direction.Y, direction.Z)
end

local function replicatedAngles(character: Model): HeadLook.Angles
	local yaw, pitch = character:GetAttribute("LookYaw"), character:GetAttribute("LookPitch")
	return {
		yaw = if typeof(yaw) == "number" then yaw else 0,
		pitch = if typeof(pitch) == "number" then pitch else 0,
	}
end

local function send(angles: HeadLook.Angles)
	local now = os.clock()
	if now - lastSentAt < Look.SEND_INTERVAL or not HeadLook.differs(angles, lastSent) then
		return
	end
	lastSent, lastSentAt = angles, now
	Net.send(Remotes.LOOK, angles)
end

local function update(dt: number)
	for character in pending do
		local layer = JointLayer.find(character, "Neck")
		if layer then
			pending[character] = nil
			necks[character] = { layer = layer, angles = { yaw = 0, pitch = 0 } }
		end
	end
	for character, neck in necks do
		if not JointLayer.alive(neck.layer) then
			necks[character] = nil
			continue
		end
		if character == localPlayer.Character then
			local angles = cameraAngles(character, neck)
			if angles then
				neck.angles = HeadLook.approach(neck.angles, angles, dt, Look.LOCAL_HALF_LIFE)
				send(angles)
			end
		else
			neck.angles = HeadLook.approach(neck.angles, replicatedAngles(character), dt)
		end
		JointLayer.apply(neck.layer, turnFor(neck.angles))
	end
end

local Controller = {}

function Controller.start()
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	-- After the Animator has written this frame's pose and after the camera has moved.
	RunService.PreSimulation:Connect(update)
end

return Controller
