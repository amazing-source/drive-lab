--!strict
--[[
	The white drawn wind-wrap around a runner's shins, one short burst per step, fired by the
	run animation's swap marker: exactly when arms and legs scissor, at whatever rate the run
	plays. Every client watches every character, so everyone sees everyone's bursts with no
	remote.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunWrap = require(ReplicatedStorage.Shared.Config.RunWrap)

-- Tracks already hooked: a track object is reused every time the run plays again.
local hooked: { [AnimationTrack]: boolean } = {}

local function emitter(root: BasePart): ParticleEmitter
	local attachment = Instance.new("Attachment")
	attachment.Name = "RunWrap"
	attachment.Position = RunWrap.OFFSET
	local particles = Instance.new("ParticleEmitter")
	particles.Texture = RunWrap.TEXTURE
	particles.FlipbookLayout = RunWrap.LAYOUT
	particles.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	particles.FlipbookStartRandom = false
	particles.Lifetime = NumberRange.new(RunWrap.LIFETIME)
	-- Drawn strokes stay paper-white whatever the lighting.
	particles.LightEmission = 0
	particles.LightInfluence = 0
	particles.Color = ColorSequence.new(Color3.new(1, 1, 1))
	particles.Speed = NumberRange.new(0)
	particles.Rate = 0
	particles.Enabled = false
	particles.LockedToPart = true
	particles.Orientation = Enum.ParticleOrientation.FacingCameraWorldUp
	particles.Rotation = NumberRange.new(0)
	particles.RotSpeed = NumberRange.new(0)
	particles.Size = NumberSequence.new(RunWrap.SIZE)
	-- The drawings fade themselves out over their last frames.
	particles.Transparency = NumberSequence.new(0)
	particles.Parent = attachment
	attachment.Parent = root
	return particles
end

local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart
	local animator = humanoid:WaitForChild("Animator") :: Animator
	if character.Parent == nil then
		return
	end
	local particles = emitter(root)
	animator.AnimationPlayed:Connect(function(track)
		if hooked[track] or track.Animation.AnimationId ~= RunWrap.RUN_ANIMATION then
			return
		end
		hooked[track] = true
		track:GetMarkerReachedSignal(RunWrap.MARKER):Connect(function()
			particles:Emit(1)
		end)
		track.Destroying:Once(function()
			hooked[track] = nil
		end)
	end)
end

local function watch(player: Player)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
end

local Controller = {}

function Controller.start()
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
end

return Controller
