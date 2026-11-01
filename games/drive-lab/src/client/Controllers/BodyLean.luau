--!strict
--[[
	Leans every character toward where it travels and into its turns, and straight back upright
	when it stops. Each client does this for every character from the velocities physics already
	replicates, so nothing is sent. The lean pivots about the feet, the
	way a body balances, rather than about the hips, which would swing the legs out.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BodyLean = require(ReplicatedStorage.Shared.Rules.BodyLean)
local JointLayer = require(script.Parent.Parent.Rig.JointLayer)
local StartupLean = require(script.Parent.Parent.Rig.StartupLean)

type Body = {
	layer: JointLayer.JointLayer,
	humanoid: Humanoid,
	root: BasePart,
	-- From the root joint's pivot down to the ground, in the root part's axes.
	toGround: Vector3,
	state: BodyLean.State,
}

-- States in which the body is not balancing on its feet.
local RELAXED: { [Enum.HumanoidStateType]: true } = {
	[Enum.HumanoidStateType.Seated] = true,
	[Enum.HumanoidStateType.Swimming] = true,
	[Enum.HumanoidStateType.Climbing] = true,
	[Enum.HumanoidStateType.Ragdoll] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
	[Enum.HumanoidStateType.Physics] = true,
	[Enum.HumanoidStateType.Dead] = true,
	[Enum.HumanoidStateType.PlatformStanding] = true,
}

local bodies: { [Model]: Body } = {}
local pending: { [Model]: true } = {}

local function groundOffset(humanoid: Humanoid, root: BasePart, layer: JointLayer.JointLayer): Vector3
	-- The root part floats this far above the ground: R6 legs are 2 studs; R15 uses HipHeight.
	local rootHeight = if humanoid.RigType == Enum.HumanoidRigType.R6
		then root.Size.Y / 2 + 2
		else humanoid.HipHeight + root.Size.Y / 2
	local pivotInRoot = if layer.parent == root
		then layer.pivot
		else root.CFrame:PointToObjectSpace(layer.parent.CFrame:PointToWorldSpace(layer.pivot))
	return Vector3.new(0, -(rootHeight + pivotInRoot.Y), 0)
end

local function bodyOf(character: Model): Body?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	local layer = JointLayer.find(character, "Root")
	if humanoid == nil or root == nil or not root:IsA("BasePart") or layer == nil then
		return nil
	end
	return {
		layer = layer,
		humanoid = humanoid,
		root = root,
		toGround = groundOffset(humanoid, root, layer),
		state = BodyLean.new(),
	}
end

local function forget(character: Model)
	bodies[character] = nil
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

-- Pitch positive leans forward (a negative turn about the root's +X); roll positive leans
-- right (a negative turn about its -Z-facing axis). Both pivot about the ground under the body.
local function leanFor(body: Body): CFrame
	local tilt = CFrame.Angles(-body.state.pitch, 0, 0) * CFrame.Angles(0, 0, -body.state.roll)
	return CFrame.new(body.toGround) * tilt * CFrame.new(-body.toGround)
end

local function update(dt: number)
	for character in pending do
		local body = bodyOf(character)
		if body then
			pending[character] = nil
			bodies[character] = body
		end
	end
	local gravity = Workspace.Gravity
	for character, body in bodies do
		if not JointLayer.alive(body.layer) then
			bodies[character] = nil
			continue
		end
		local velocity = body.root.AssemblyLinearVelocity
		local facing = body.root.CFrame.LookVector
		body.state = BodyLean.step(body.state, {
			velocityX = velocity.X,
			velocityZ = velocity.Z,
			facingX = facing.X,
			facingZ = facing.Z,
			-- Turning right is a negative spin about up.
			yawRate = -body.root.AssemblyAngularVelocity.Y,
			gravity = gravity,
			upright = not RELAXED[body.humanoid:GetState()],
		}, dt)
		-- A seated driver's start-up lean goes through this same layer: one writer per joint.
		local lean = leanFor(body)
		local startup = StartupLean.rootTurn(body.humanoid, body.layer.parent, body.layer.pivot)
		JointLayer.apply(body.layer, if startup then lean * startup else lean)
	end
end

local Controller = {}

function Controller.start()
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	RunService.PreSimulation:Connect(update)
end

return Controller
