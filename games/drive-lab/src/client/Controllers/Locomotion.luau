--!strict
--[[
	Animates the local character and runs its sprint: Roblox's own R6 idle, jump, fall, climb and
	sit, with our walk and run. Animations played on the local character replicate, so every
	player sees them. Walk and run play at the rate that keeps their feet planted: the speed each
	was authored for, scaled by the character's real ground speed.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Log = require(ReplicatedStorage.Kit.Log)
local Movement = require(ReplicatedStorage.Shared.Config.Movement)

type Name = "idle" | "walk" | "run" | "jump" | "fall" | "climb" | "sit"

type Body = {
	humanoid: Humanoid,
	root: BasePart,
	tracks: { [string]: AnimationTrack },
	playing: AnimationTrack?,
}

local LOOPED: { [string]: boolean } = {
	idle = true,
	walk = true,
	run = true,
	fall = true,
	climb = true,
	sit = true,
	jump = false,
}

local log = Log.scope("Locomotion")
local localPlayer = Players.LocalPlayer
local body: Body? = nil
local gamepadSprint = false

local function load(animator: Animator): { [string]: AnimationTrack }
	local tracks: { [string]: AnimationTrack } = {}
	for name, spec in Movement.ANIMATIONS do
		local animation = Instance.new("Animation")
		animation.AnimationId = spec.id
		local track = animator:LoadAnimation(animation)
		track.Priority = spec.priority
		track.Looped = LOOPED[name]
		tracks[name] = track
	end
	return tracks
end

local function play(current: Body, name: Name, rate: number?)
	local track = current.tracks[name]
	if current.playing ~= track then
		if current.playing then
			current.playing:Stop(Movement.FADE)
		end
		track:Play(Movement.FADE)
		current.playing = track
	end
	if rate then
		track:AdjustSpeed(rate)
	end
end

local function sprinting(): boolean
	return gamepadSprint or UserInputService:IsKeyDown(Movement.SPRINT_KEYS[1])
end

local function update(current: Body)
	local humanoid = current.humanoid
	local state = humanoid:GetState()
	humanoid.WalkSpeed = if sprinting() then Movement.SPRINT_SPEED else Movement.WALK_SPEED
	if state == Enum.HumanoidStateType.Dead then
		if current.playing then
			current.playing:Stop(Movement.FADE)
			current.playing = nil
		end
	elseif state == Enum.HumanoidStateType.Seated then
		play(current, "sit")
	elseif state == Enum.HumanoidStateType.Jumping then
		play(current, "jump")
	elseif state == Enum.HumanoidStateType.Freefall then
		play(current, "fall")
	elseif state == Enum.HumanoidStateType.Climbing then
		play(current, "climb", current.root.AssemblyLinearVelocity.Magnitude / Movement.WALK_PACE)
	else
		local velocity = current.root.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		if speed < 0.5 then
			play(current, "idle")
		elseif speed < Movement.RUN_THRESHOLD then
			play(current, "walk", speed / Movement.WALK_PACE)
		else
			play(current, "run", speed / Movement.RUN_PACE)
		end
	end
end

local function onCharacter(character: Model)
	body = nil
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart
	local animator = humanoid:WaitForChild("Animator") :: Animator
	if character.Parent == nil then
		return
	end
	if humanoid.RigType ~= Enum.HumanoidRigType.R6 then
		log.warn("the walk and run are R6 animations; this character is R15, so it stays unanimated")
		return
	end
	body = { humanoid = humanoid, root = root, tracks = load(animator), playing = nil }
end

local Controller = {}

function Controller.start()
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Movement.SPRINT_KEYS[2] then
			gamepadSprint = not gamepadSprint
		end
	end)
	if localPlayer.Character then
		task.spawn(onCharacter, localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(onCharacter)
	RunService.Heartbeat:Connect(function()
		local current = body
		if current and current.humanoid.Parent then
			update(current)
		end
	end)
end

return Controller
