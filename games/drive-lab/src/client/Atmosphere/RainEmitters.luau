--!strict
--[[
	Builds the rain's particle emitters from the config: streak emitters for the rings, the
	splash and ripple emitters, and tints the streaks with the weather's look. Kept apart from
	Rain so the per-frame code there only moves parts and sets rates.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.Atmosphere)
local RainStreaks = require(ReplicatedStorage.Shared.Rules.RainStreaks)

-- What a splash emitter needs: the ground's splashes and the car's share it.
export type Crowns = {
	texture: string,
	size: { number },
	lifetime: { number },
	transparency: number,
	color: Config.Rgb,
}

local RAIN = Config.RAIN

local RainEmitters = {}

function RainEmitters.colour(value: Config.Rgb): Color3
	return Color3.fromRGB(value.r, value.g, value.b)
end

function RainEmitters.invisiblePart(name: string, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.Parent = parent
	return part
end

-- The Size and Squash that draw a sprite as one of a layer's streaks.
function RainEmitters.fit(sprite: Config.Sprite, layer: Config.Layer): RainStreaks.Fit
	local length = RainStreaks.length(RAIN.fallSpeed, RAIN.exposure, RAIN.maxLength)
	return RainStreaks.fit(length, layer.width, sprite.along, sprite.across)
end

-- Studs from a streak particle's centre to the end of its quad along its motion, at its largest.
function RainEmitters.halfLength(sprite: Config.Sprite, layer: Config.Layer): number
	local fit = RainEmitters.fit(sprite, layer)
	return RainStreaks.halfLength(fit.size * (1 + layer.spread), fit.squash)
end

-- Fades in and out at the ends of a life; through the middle each particle draws its own
-- transparency within the layer's spread, so streaks differ in strength.
local function fade(layer: Config.Layer, opacity: number): NumberSequence
	local middle = 1 - (1 - layer.transparency) * math.clamp(opacity, 0, 1)
	local spread = math.min(layer.transparencySpread, middle, 1 - middle)
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(RAIN.fadeIn, middle, spread),
		NumberSequenceKeypoint.new(1 - RAIN.fadeOut, middle, spread),
		NumberSequenceKeypoint.new(1, 1),
	})
end

-- A streak emitter for one sprite. Its part is turned so the bottom face points along the
-- rain's fall; VelocityParallel lays the texture's horizontal axis along the motion (seen in
-- Studio) and the streaks are drawn vertical, so the particle is turned a quarter, which also
-- makes a positive Squash lengthen it along the fall (measured, Rules/RainStreaks). World
-- space: particles stay where they were emitted when the part moves on.
function RainEmitters.streaks(
	sprite: Config.Sprite,
	layer: Config.Layer,
	lifetime: number,
	parent: Part
): ParticleEmitter
	local fit = RainEmitters.fit(sprite, layer)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = sprite.image
	emitter.Rotation = NumberRange.new(90)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, fit.size, fit.size * layer.spread),
		NumberSequenceKeypoint.new(1, fit.size, fit.size * layer.spread),
	})
	emitter.Squash = NumberSequence.new(fit.squash)
	-- Each particle should fall to the ground and no further (Rules/RainRings.column).
	emitter.Lifetime = NumberRange.new(lifetime)
	emitter.Speed = NumberRange.new(RAIN.fallSpeed / math.cos(RAIN.lean))
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.Orientation = Enum.ParticleOrientation.VelocityParallel
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.LockedToPart = false
	-- Lit by the scene, never glowing: measured in Studio (2026-10-28), lighting is per
	-- particle and takes the local SpotLights and PointLights, so by night a streak shows
	-- where a headlight or lamp falls on it. The blend follows the look (tone).
	emitter.LightInfluence = 1
	emitter.LightEmission = 0
	emitter.Rate = 0
	emitter.Parent = parent
	return emitter
end

-- The weather's tone on a streak emitter: its albedo, the share of its opacity shown, and how
-- additive it blends (Config.Look.rainEmission).
function RainEmitters.tone(
	emitter: ParticleEmitter,
	layer: Config.Layer,
	color: Color3,
	opacity: number,
	emission: number
)
	emitter.Color = ColorSequence.new(color)
	emitter.Transparency = fade(layer, opacity)
	emitter.LightEmission = math.clamp(emission, 0, 1)
end

-- Upright crowns standing on a flat box, played once over a life.
function RainEmitters.splashes(splash: Crowns, parent: Part): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = splash.texture
	emitter.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
	emitter.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	emitter.Color = ColorSequence.new(RainEmitters.colour(splash.color))
	emitter.Transparency = NumberSequence.new(splash.transparency, 1)
	local middle, spread = (splash.size[1] + splash.size[2]) / 2, (splash.size[2] - splash.size[1]) / 2
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, middle, spread),
		NumberSequenceKeypoint.new(1, middle, spread),
	})
	emitter.Lifetime = NumberRange.new(splash.lifetime[1], splash.lifetime[2])
	emitter.Speed = NumberRange.new(0)
	emitter.Orientation = Enum.ParticleOrientation.FacingCameraWorldUp
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.LightInfluence = 1
	emitter.LightEmission = 0
	emitter.Rate = 0
	emitter.Parent = parent
	return emitter
end

-- Rings lying flat on a splash box, growing from a third of their diameter while they fade.
-- VelocityPerpendicular with a crawl upward lays the quad level (a still particle has no
-- direction to lie across); the depth test keeps the road in front of it where it should.
function RainEmitters.ripples(ripples: Config.Ripples, sprite: Config.Sprite, parent: Part): ParticleEmitter
	local low, high = ripples.diameter[1] / sprite.across / 2, ripples.diameter[2] / sprite.across / 2
	local middle, spread = (low + high) / 2, (high - low) / 2
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = sprite.image
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, middle / 3, spread / 3),
		NumberSequenceKeypoint.new(1, middle, spread),
	})
	local peak = 1 - ripples.opacity
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.1, peak),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.Lifetime = NumberRange.new(ripples.lifetime[1], ripples.lifetime[2])
	emitter.Speed = NumberRange.new(0.01)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.LightInfluence = 1
	emitter.LightEmission = 0
	emitter.Rate = 0
	emitter.Parent = parent
	return emitter
end

return RainEmitters
