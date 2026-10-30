--!strict
--[[
	Tyre smoke from a car: an emitter behind each tyre's contact patch, fed by the slip Driving
	publishes on the car (TyreSlipFL, TyreSlideFL and the rest; only the driver's client has
	them). Particles stay in the world where they are made, so a burnout piles a cloud up behind
	the car and a slide lays a trail; they rise a little and hang, lit by the scene. Mounted on
	the chassis (any part, unrigged) at the wheels' rest positions, so the suspension's few
	centimetres of travel do not move them.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage.Shared.Config.Cars.Catalog)
local Config = require(ReplicatedStorage.Shared.Config.TyreSmoke)
local Rules = require(ReplicatedStorage.Shared.Rules.TyreSmoke)
local Units = require(ReplicatedStorage.Shared.Units)

type Wheel = { emitter: ParticleEmitter, rate: number, throw: number }

export type TyreSmoke = {
	model: Model,
	wheels: { Wheel },
	attachments: { Attachment },
	-- Each wheel's smoke share, carried between frames as the tread heats and cools.
	heats: { number },
	-- Reused each frame.
	rates: { number },
}

local function sequence(points: { { number } }): NumberSequence
	local keypoints = table.create(#points)
	for index, point in points do
		keypoints[index] = NumberSequenceKeypoint.new(point[1], point[2])
	end
	return NumberSequence.new(keypoints)
end

local function emitter(parent: Attachment): ParticleEmitter
	local particles = Instance.new("ParticleEmitter")
	particles.Texture = Config.TEXTURE
	particles.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2
	particles.FlipbookMode = Enum.ParticleFlipbookMode.Loop
	-- One puff per particle, kept for its life: the four cells are variants, not frames.
	particles.FlipbookFramerate = NumberRange.new(0)
	particles.FlipbookStartRandom = true
	local born, dies, spread = Config.SIZE[1], Config.SIZE[2], Config.SIZE_SPREAD
	particles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, born, born * spread),
		NumberSequenceKeypoint.new(1, dies, dies * spread),
	})
	particles.Transparency = sequence(Config.TRANSPARENCY)
	particles.Lifetime = NumberRange.new(Config.LIFETIME[1], Config.LIFETIME[2])
	local color = Config.COLOR
	particles.Color = ColorSequence.new(Color3.fromRGB(color.r, color.g, color.b))
	particles.LightEmission = 0
	particles.LightInfluence = 1
	particles.EmissionDirection = Enum.NormalId.Front
	particles.SpreadAngle = Vector2.new(Config.SPREAD, Config.SPREAD)
	particles.Speed = NumberRange.new(0)
	particles.Drag = Config.DRAG
	particles.Acceleration = Vector3.new(0, Config.BUOYANCY, 0)
	particles.Rotation = NumberRange.new(-Config.ROTATION, Config.ROTATION)
	particles.RotSpeed = NumberRange.new(-Config.ROT_SPEED, Config.ROT_SPEED)
	particles.ZOffset = Config.Z_OFFSET
	particles.VelocityInheritance = 0
	particles.LockedToPart = false
	particles.WindAffectsDrag = false
	particles.Rate = 0
	particles.Parent = parent
	return particles
end

local function host(model: Model): BasePart?
	local chassis = model:FindFirstChild("Chassis")
	if chassis and chassis:IsA("BasePart") then
		return chassis
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

local TyreSmoke = {}

-- Emitters behind each tyre of a catalogued car, aimed back and a little up; nil for a model
-- that is not one.
function TyreSmoke.new(model: Model): TyreSmoke?
	local entry = Catalog.of(model)
	local part = host(model)
	if entry == nil or part == nil then
		return nil
	end
	local parts: { BasePart } = {}
	for index, wheelName in entry.model.wheels do
		local wheel = model:FindFirstChild(wheelName, true)
		if wheel == nil or not wheel:IsA("BasePart") then
			return nil
		end
		parts[index] = wheel
	end
	local frame = model:GetPivot()
	local aim = CFrame.Angles(math.rad(Config.RISE), 0, 0)
	local wheels: { Wheel } = {}
	local attachments: { Attachment } = {}
	for index, wheel in parts do
		local radius = wheel.Size.Y / 2
		local at = wheel.Position
			- frame.UpVector * (radius - Units.metresToStuds(Config.LIFT))
			+ frame.ZVector * Units.metresToStuds(Config.BACK)
		local attachment = Instance.new("Attachment")
		attachment.Name = "DriveLabTyreSmoke"
		attachment.CFrame = part.CFrame:ToObjectSpace(CFrame.lookAt(at, at + frame.ZVector) * aim)
		attachment.Parent = part
		attachments[index] = attachment
		wheels[index] = { emitter = emitter(attachment), rate = 0, throw = -1 }
	end
	return {
		model = model,
		wheels = wheels,
		attachments = attachments,
		heats = table.create(#wheels, 0),
		rates = table.create(#wheels, 0),
	}
end

-- Fills `into` with the car's per-wheel readings; a missing one reads as no slip.
function TyreSmoke.read(model: Model, into: { Rules.Wheel })
	for index, name in Config.SLIP_ATTRIBUTES do
		local slip = model:GetAttribute(name)
		local slide = model:GetAttribute(Config.SLIDE_ATTRIBUTES[index])
		local reading = into[index]
		if reading == nil then
			reading = { slip = 0, slide = 0 }
			into[index] = reading
		end
		reading.slip = if typeof(slip) == "number" then slip else 0
		reading.slide = if typeof(slide) == "number" then slide else 0
	end
end

function TyreSmoke.update(smoke: TyreSmoke, readings: { Rules.Wheel }, wetness: number, dt: number)
	local rates = Rules.rates(readings, wetness, Config.THRESHOLDS, smoke.heats, dt, smoke.rates)
	for index, wheel in smoke.wheels do
		local rate = rates[index] or 0
		if rate ~= wheel.rate then
			wheel.emitter.Rate = rate
			wheel.rate = rate
		end
		local reading = readings[index]
		if rate > 0 and reading then
			local throw = Units.metresToStuds(Rules.throwSpeed(reading.slide, Config.THROW))
			if math.abs(throw - wheel.throw) > math.max(throw, 1) * 0.1 then
				wheel.emitter.Speed = NumberRange.new(throw * 0.6, throw)
				wheel.throw = throw
			end
		end
	end
end

-- Stops new smoke; what is in the air stays until it fades.
function TyreSmoke.idle(smoke: TyreSmoke)
	table.clear(smoke.heats)
	for _, wheel in smoke.wheels do
		if wheel.rate ~= 0 then
			wheel.emitter.Rate = 0
			wheel.rate = 0
		end
	end
end

function TyreSmoke.destroy(smoke: TyreSmoke)
	for _, attachment in smoke.attachments do
		attachment:Destroy()
	end
	table.clear(smoke.wheels)
end

return TyreSmoke
