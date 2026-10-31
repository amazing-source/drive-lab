--!strict
--[[
	The air a fast car drives through: dust, grit and the odd leaf, or fine water on a wet road,
	emitted at rest in three slabs of air (left, right, above) along the path the car will take
	a moment from now, so it is the car's own motion that streams them past. Nothing is emitted
	in the car's own path, so nothing goes through the cabin. At high speed the same slabs carry
	faint streaks of air (Effects/AirStreaks). The car's wake also lifts the odd leaf and chip off
	a dry road from its rear corners. Rules/AirDebris has the reasoning.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config.AirDebris)
local Rules = require(ReplicatedStorage.Shared.Rules.AirDebris)
local Units = require(ReplicatedStorage.Shared.Units)

local AirStreaks = require(script.Parent.AirStreaks)

export type Motion = {
	model: Model,
	-- The car's bounding box this frame, in the car's orientation, and its size (studs).
	box: CFrame,
	size: Vector3,
	-- Studs a second, and how fast the path turns (rad/s, positive to the right).
	velocity: Vector3,
	turnRate: number,
}

type Side = "Left" | "Right" | "Top"
-- A slab's offset from the path's centre line at road level, and its cross-section (m²).
type Slab = { side: Side, part: Part, offset: CFrame, area: number }
-- `slab` is nil for the wake's emitters.
type Emitting = { emitter: ParticleEmitter, kind: Config.Kind, rate: number, slab: Slab? }
type Wake = { model: Model, attachments: { Attachment }, emitting: { Emitting } }

export type AirDebris = {
	folder: Folder,
	slabs: { Slab },
	-- Every slab's emitters, one list.
	emitting: { Emitting },
	streaks: AirStreaks.AirStreaks,
	parts: { BasePart },
	frames: { CFrame },
	wake: Wake?,
	-- The slab length last applied (studs) and the car size it was laid out for.
	length: number,
	size: Vector3,
	-- Reused each frame: the rate each of `emitting` wants.
	wanted: { number },
}

local SIDES: { Side } = { "Left", "Right", "Top" }
local KIND_NAMES: { string } = {}
for name in Config.KINDS do
	table.insert(KIND_NAMES, name)
end
table.sort(KIND_NAMES)

local function studs(metres: number): number
	return Units.metresToStuds(metres)
end

local function debrisEmitter(kind: Config.Kind, parent: Instance): ParticleEmitter
	local particles = Instance.new("ParticleEmitter")
	particles.Texture = kind.texture
	particles.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2
	particles.FlipbookMode = Enum.ParticleFlipbookMode.Loop
	-- One variant per particle, kept for its life: the cells are different objects.
	particles.FlipbookFramerate = NumberRange.new(0)
	particles.FlipbookStartRandom = true
	local small, large = studs(kind.size[1]) / Config.FILL, studs(kind.size[2]) / Config.FILL
	local middle, half = (small + large) / 2, (large - small) / 2
	particles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, middle, half),
		NumberSequenceKeypoint.new(1, middle, half),
	})
	local fadeIn, fadeOut = Config.FADE[1], Config.FADE[2]
	particles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(fadeIn, kind.transparency),
		NumberSequenceKeypoint.new(1 - fadeOut, kind.transparency),
		NumberSequenceKeypoint.new(1, 1),
	})
	particles.Lifetime = NumberRange.new(Config.LIFETIME[1], Config.LIFETIME[2])
	particles.Color = ColorSequence.new(Color3.fromRGB(kind.color.r, kind.color.g, kind.color.b))
	particles.LightEmission = 0
	particles.LightInfluence = 1
	particles.Acceleration = Vector3.new(0, -studs(kind.fall), 0)
	particles.Speed = NumberRange.new(0, studs(kind.drift))
	if kind.water then
		-- Spray settling: drawn along its fall with the smear trailing. Drawn along a drift back
		-- down the path instead, drops ahead face the camera edge-on and none showed (2026-10-28).
		particles.Orientation = Enum.ParticleOrientation.VelocityParallel
		particles.Rotation = NumberRange.new(Config.STREAK_ROTATION)
		particles.Speed = NumberRange.new(studs(kind.drift) * 0.7, studs(kind.drift))
		particles.EmissionDirection = Enum.NormalId.Bottom
		particles.SpreadAngle = Vector2.new(20, 20)
	else
		particles.Rotation = NumberRange.new(0, 360)
		particles.RotSpeed = NumberRange.new(-kind.spin, kind.spin)
		particles.EmissionDirection = Enum.NormalId.Top
		particles.SpreadAngle = Vector2.new(180, 180)
	end
	particles.Shape = Enum.ParticleEmitterShape.Box
	particles.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	particles.LockedToPart = false
	particles.VelocityInheritance = 0
	particles.WindAffectsDrag = false
	particles.Rate = 0
	particles.Parent = parent
	return particles
end

local function slabPart(side: Side, folder: Folder): Part
	local part = Instance.new("Part")
	part.Name = `AirDebris{side}`
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.Parent = folder
	return part
end

local function newSlab(side: Side, folder: Folder, emitting: { Emitting }): Slab
	local slab: Slab = { side = side, part = slabPart(side, folder), offset = CFrame.identity, area = 0 }
	for _, name in KIND_NAMES do
		local kind = Config.KINDS[name]
		table.insert(
			emitting,
			{ emitter = debrisEmitter(kind, slab.part), kind = kind, rate = 0, slab = slab }
		)
	end
	return slab
end

local function host(model: Model): BasePart?
	local chassis = model:FindFirstChild("Chassis")
	if chassis and chassis:IsA("BasePart") then
		return chassis
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

-- Emitters at the car's rear corners, low, thrown outward, back and up.
local function newWake(model: Model, box: CFrame, size: Vector3): Wake?
	local part = host(model)
	if part == nil then
		return nil
	end
	local wake = Config.WAKE
	local attachments: { Attachment } = {}
	local emitting: { Emitting } = {}
	for _, sign in { -1, 1 } do
		local at = box
			* Vector3.new(
				sign * (size.X / 2 - studs(0.1)),
				-size.Y / 2 + studs(0.12),
				size.Z / 2 - studs(0.3)
			)
		local outward = math.rad(wake.outward)
		local flat = box.ZVector * math.cos(outward) + box.XVector * sign * math.sin(outward)
		local rise = math.rad(wake.rise)
		local direction = flat * math.cos(rise) + box.YVector * math.sin(rise)
		local attachment = Instance.new("Attachment")
		attachment.Name = "DriveLabWake"
		attachment.CFrame = part.CFrame:ToObjectSpace(CFrame.lookAt(at, at + direction))
		attachment.Parent = part
		table.insert(attachments, attachment)
		for _, name in Config.WAKE_KINDS do
			local kind = Config.KINDS[name]
			local particles = debrisEmitter(kind, attachment)
			particles.EmissionDirection = Enum.NormalId.Front
			particles.SpreadAngle = Vector2.new(wake.spread, wake.spread)
			particles.Speed = NumberRange.new(studs(wake.speed[1]), studs(wake.speed[2]))
			particles.Drag = wake.drag
			particles.VelocityInheritance = wake.inherit
			particles.Lifetime = NumberRange.new(wake.lifetime[1], wake.lifetime[2])
			table.insert(emitting, { emitter = particles, kind = kind, rate = 0 })
		end
	end
	return { model = model, attachments = attachments, emitting = emitting }
end

local function dropWake(debris: AirDebris)
	local wake = debris.wake
	if wake then
		debris.wake = nil
		for _, attachment in wake.attachments do
			attachment:Destroy()
		end
	end
end

local function setRate(item: Emitting, rate: number)
	if rate ~= item.rate then
		item.emitter.Rate = rate
		item.rate = rate
	end
end

-- Sizes and places the slabs for a car of `size` and a slab `length` (studs): beside the car's
-- path from the road up, and over it above the roof, each clear of the car by the margin.
local function layout(debris: AirDebris, size: Vector3, length: number)
	local region = Config.REGION
	local margin, reach, height = studs(region.margin), studs(region.reach), studs(region.height)
	local width, roof = size.X / 2 + margin, size.Y + margin
	for _, slab in debris.slabs do
		local across, tall = reach, height
		local offset =
			Vector3.new((if slab.side == "Left" then -1 else 1) * (width + reach / 2), height / 2, 0)
		if slab.side == "Top" then
			across, tall = width * 2, math.max(height - roof, 0)
			offset = Vector3.new(0, (roof + height) / 2, 0)
		end
		slab.part.Size = Vector3.new(math.max(across, 0.05), math.max(tall, 0.05), math.max(length, 0.05))
		slab.offset = CFrame.new(offset)
		slab.area = Units.studsToMetres(across) * Units.studsToMetres(tall)
	end
	debris.length, debris.size = length, size
end

local AirDebris = {}

function AirDebris.new(): AirDebris
	local folder = Instance.new("Folder")
	folder.Name = "DriveLabAirDebris"
	local slabs: { Slab } = {}
	local emitting: { Emitting } = {}
	local parts: { BasePart } = {}
	local streakSlabs: { AirStreaks.Slab } = {}
	for _, side: Side in SIDES do
		local slab = newSlab(side, folder, emitting)
		table.insert(slabs, slab)
		table.insert(parts, slab.part)
		table.insert(streakSlabs, slab)
	end
	folder.Parent = Workspace
	return {
		folder = folder,
		slabs = slabs,
		emitting = emitting,
		streaks = AirStreaks.new(streakSlabs),
		parts = parts,
		frames = table.create(#parts, CFrame.identity),
		wake = nil,
		length = -1,
		size = Vector3.zero,
		wanted = {},
	}
end

-- Stops new debris; what is in the air finishes its life.
function AirDebris.idle(debris: AirDebris)
	for _, item in debris.emitting do
		setRate(item, 0)
	end
	AirStreaks.idle(debris.streaks)
	if debris.wake then
		for _, item in debris.wake.emitting do
			setRate(item, 0)
		end
	end
end

local function place(debris: AirDebris, motion: Motion, speed: number)
	local up = motion.box.UpVector
	local direction = motion.velocity / speed
	if math.abs(direction:Dot(up)) > 0.95 then
		return false
	end
	local road = motion.box.Position - up * motion.size.Y / 2
	local travel = CFrame.lookAt(road, road + direction, up)
	local lead = Config.REGION.lead
	local forward, right, heading = Rules.ahead(speed, motion.turnRate, (lead[1] + lead[2]) / 2)
	local centre = travel * CFrame.new(right, 0, -forward) * CFrame.Angles(0, -heading, 0)
	local length = speed * (lead[2] - lead[1])
	if motion.size ~= debris.size or math.abs(length - debris.length) > debris.length * 0.05 then
		layout(debris, motion.size, length)
	end
	for index, slab in debris.slabs do
		debris.frames[index] = centre * slab.offset
	end
	Workspace:BulkMoveTo(debris.parts, debris.frames, Enum.BulkMoveMode.FireCFrameChanged)
	return true
end

-- One frame: `motion` is the car the camera rides with, nil when there is none.
function AirDebris.update(debris: AirDebris, motion: Motion?, wetness: number)
	if motion == nil then
		AirDebris.idle(debris)
		return
	end
	if debris.wake == nil or debris.wake.model ~= motion.model then
		dropWake(debris)
		debris.wake = newWake(motion.model, motion.box, motion.size)
	end
	local speed = motion.velocity.Magnitude
	local metresPerSecond = Units.studsToMetres(speed)
	local share = Rules.speedShare(Units.mpsToKmh(metresPerSecond), Config.SPEEDS)
	if share <= 0 or not place(debris, motion, speed) then
		AirDebris.idle(debris)
		return
	end
	local water = Rules.waterShare(wetness, Config.WATER.from, Config.WATER.to)
	local wanted = debris.wanted
	for index, item in debris.emitting do
		local mix = if item.kind.water then water else 1 - water
		local area = if item.slab then item.slab.area else 0
		wanted[index] = Rules.rate(item.kind.density, area, metresPerSecond, share * mix, math.huge)
	end
	Rules.cap(wanted, Config.MAX_RATE)
	for index, item in debris.emitting do
		setRate(item, wanted[index])
	end
	AirStreaks.update(debris.streaks, metresPerSecond, 1 - water)
	local wake = debris.wake
	if wake then
		local each = Config.WAKE.rate * share * (1 - water) / #Config.WAKE_KINDS
		for _, item in wake.emitting do
			setRate(item, each)
		end
	end
end

function AirDebris.destroy(debris: AirDebris)
	dropWake(debris)
	debris.folder:Destroy()
end

return AirDebris
