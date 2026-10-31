--!strict
--[[
	Faint streaks of air at high speed, in Effects/AirDebris's slabs beside and above the car's
	path, so none crosses the car. Each streak is left at rest in the world, laid along the path:
	a speck smeared over a camera's exposure (Rules/AirDebris.streak), so the car's own motion
	brings it past.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.AirDebris)
local Rules = require(ReplicatedStorage.Shared.Rules.AirDebris)
local Units = require(ReplicatedStorage.Shared.Units)

-- One of AirDebris's slabs: its part and its cross-section (m²).
export type Slab = { part: Part, area: number }

type Streaking = { emitter: ParticleEmitter, rate: number, slab: Slab }

export type AirStreaks = {
	streaking: { Streaking },
	-- The car speed (m/s) the streaks are sized for.
	sizedFor: number,
	-- Reused each frame: the rate each streak emitter wants.
	wanted: { number },
}

-- The slab's front faces along the path, and a slow drift that way makes VelocityParallel lay
-- the streak along the path. The sprite's streak runs up its height, so it is turned a quarter,
-- which also makes a positive Squash lengthen it along the motion (Rules/RainStreaks).
local function streakEmitter(parent: Instance): ParticleEmitter
	local streaks = Config.STREAKS
	local particles = Instance.new("ParticleEmitter")
	particles.Texture = streaks.texture
	particles.Orientation = Enum.ParticleOrientation.VelocityParallel
	particles.Rotation = NumberRange.new(90)
	particles.Size = NumberSequence.new(0)
	local fadeIn, fadeOut = Config.FADE[1], Config.FADE[2]
	particles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(fadeIn, streaks.transparency),
		NumberSequenceKeypoint.new(1 - fadeOut, streaks.transparency),
		NumberSequenceKeypoint.new(1, 1),
	})
	particles.Lifetime = NumberRange.new(Config.LIFETIME[1], Config.LIFETIME[2])
	particles.Color = ColorSequence.new(Color3.fromRGB(streaks.color.r, streaks.color.g, streaks.color.b))
	particles.LightEmission = 0
	particles.LightInfluence = 1
	particles.Speed = NumberRange.new(Units.metresToStuds(streaks.drift))
	particles.EmissionDirection = Enum.NormalId.Front
	particles.SpreadAngle = Vector2.zero
	particles.Shape = Enum.ParticleEmitterShape.Box
	particles.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	particles.LockedToPart = false
	particles.VelocityInheritance = 0
	particles.WindAffectsDrag = false
	particles.Rate = 0
	particles.Parent = parent
	return particles
end

local function setRate(item: Streaking, rate: number)
	if rate ~= item.rate then
		item.emitter.Rate = rate
		item.rate = rate
	end
end

-- A streak's size depends on the car's speed; every emitter is resized together.
local function resize(streaks: AirStreaks, metresPerSecond: number)
	local fit = Rules.streak(metresPerSecond, Config.STREAKS.shape)
	local size = NumberSequence.new(Units.metresToStuds(fit.size))
	local squash = NumberSequence.new(fit.squash)
	for _, item in streaks.streaking do
		item.emitter.Size = size
		item.emitter.Squash = squash
	end
	streaks.sizedFor = metresPerSecond
end

local AirStreaks = {}

function AirStreaks.new(slabs: { Slab }): AirStreaks
	local streaking: { Streaking } = {}
	for _, slab in slabs do
		table.insert(streaking, { emitter = streakEmitter(slab.part), rate = 0, slab = slab })
	end
	return { streaking = streaking, sizedFor = 0, wanted = table.create(#streaking, 0) }
end

-- Stops new streaks; those in the air finish their life.
function AirStreaks.idle(streaks: AirStreaks)
	for _, item in streaks.streaking do
		setRate(item, 0)
	end
end

-- One frame at `metresPerSecond`, with `dry` the share of the air that is not water.
function AirStreaks.update(streaks: AirStreaks, metresPerSecond: number, dry: number)
	local config = Config.STREAKS
	local share = Rules.speedShare(Units.mpsToKmh(metresPerSecond), config.speeds) * dry
	if share <= 0 then
		AirStreaks.idle(streaks)
		return
	end
	if math.abs(metresPerSecond - streaks.sizedFor) > streaks.sizedFor * config.resize then
		resize(streaks, metresPerSecond)
	end
	local wanted = streaks.wanted
	for index, item in streaks.streaking do
		wanted[index] = Rules.rate(config.density, item.slab.area, metresPerSecond, share, math.huge)
	end
	Rules.cap(wanted, config.maxRate)
	for index, item in streaks.streaking do
		setRate(item, wanted[index])
	end
end

return AirStreaks
