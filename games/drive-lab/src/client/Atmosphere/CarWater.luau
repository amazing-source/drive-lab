--!strict
--[[
	The rain on the car nearest the camera: crowns splashing on its bodywork, and spray off its
	rear tyres with a mist left hanging behind. Built for a car the first time it is the nearest
	in the rain; switching cars rebuilds it, and stop removes it all. The paint is never
	darkened: a SurfaceAppearance's maps cannot change at run time.

	The bodywork is found once by rays straight down over the car's top. Each that meets paint
	(not the windows, not a steep side) becomes a flat patch that follows the car every frame,
	its splashes locked to it. The spray's emitters sit on attachments under the car's own
	chassis, so they inherit its velocity and the water is left behind in the air.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Catalog = require(ReplicatedStorage.Shared.Config.Cars.Catalog)
local Config = require(ReplicatedStorage.Shared.Config.CarWater)
local RainEmitters = require(script.Parent.RainEmitters)
local Rules = require(ReplicatedStorage.Shared.Rules.CarWater)
local Units = require(ReplicatedStorage.Shared.Units)

type Patch = { part: Part, emitter: ParticleEmitter, offset: CFrame, area: number, rate: number }
type Spray = { emitter: ParticleEmitter, share: number, rate: number }

type Rig = {
	model: Model,
	patches: { Patch },
	-- The patches' parts, in the same order, for one BulkMoveTo a frame.
	parts: { BasePart },
	sprays: { Spray },
	attachments: { Attachment },
	speed: number,
}

-- `frames` is reused every frame for the patches' moves.
export type CarWater = { folder: Folder, rig: Rig?, frames: { CFrame } }

local SPLASHES = Config.SPLASHES
local SPRAY = Config.SPRAY
-- Bodywork steeper than 40 degrees (the car's flanks) takes no patch.
local FLAT_ENOUGH = math.cos(math.rad(40))

local function glazing(model: Model): { [string]: boolean }
	local names = {}
	local entry = Catalog.of(model)
	if entry then
		for _, part in entry.model.glazing do
			names[part] = true
		end
	end
	return names
end

-- A frame lying on the surface a ray met, just over it, X along `right`.
local function flatOn(hit: RaycastResult, right: Vector3): CFrame
	local up = hit.Normal
	local back = right:Cross(up).Unit
	return CFrame.fromMatrix(hit.Position + up * SPLASHES.lift, up:Cross(back), up, back)
end

local function newPatch(
	folder: Folder,
	name: string,
	at: CFrame,
	cell: Vector2,
	offset: CFrame,
	area: number
): Patch
	local part = RainEmitters.invisiblePart(name, folder)
	part.Size = Vector3.new(cell.X, 0.01, cell.Y)
	part.CFrame = at
	local emitter = RainEmitters.splashes(SPLASHES, part)
	-- The crowns ride with the car rather than being left on the road behind it.
	emitter.LockedToPart = true
	return { part = part, emitter = emitter, offset = offset, area = area, rate = 0 }
end

-- Flat patches over the car's painted top, from a grid of rays straight down onto it.
local function patches(model: Model, folder: Folder): { Patch }
	local box, size = model:GetBoundingBox()
	local pivot = model:GetPivot()
	local glass = glazing(model)
	local rays = RaycastParams.new()
	rays.FilterType = Enum.RaycastFilterType.Include
	rays.FilterDescendantsInstances = { model }
	local cell = Vector2.new(size.X * 0.8 / SPLASHES.columns, size.Z * 0.9 / SPLASHES.rows)
	local area = Units.studsToMetres(cell.X) * Units.studsToMetres(cell.Y)
	local found: { Patch } = {}
	for column = 1, SPLASHES.columns do
		for row = 1, SPLASHES.rows do
			local x = (column - (SPLASHES.columns + 1) / 2) * cell.X
			local z = (row - (SPLASHES.rows + 1) / 2) * cell.Y
			local origin = box * Vector3.new(x, size.Y / 2 + 1, z)
			local hit = Workspace:Raycast(origin, -box.UpVector * (size.Y + 2), rays)
			if hit and not glass[hit.Instance.Name] and hit.Normal:Dot(box.UpVector) > FLAT_ENOUGH then
				local at = flatOn(hit, box.RightVector)
				table.insert(
					found,
					newPatch(folder, `CarSplashes{#found + 1}`, at, cell, pivot:ToObjectSpace(at), area)
				)
			end
		end
	end
	return found
end

local function puffs(parent: Attachment, spec: Config.Puffs, share: number): Spray
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPRAY.texture
	emitter.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2
	emitter.FlipbookMode = Enum.ParticleFlipbookMode.Loop
	emitter.FlipbookFramerate = NumberRange.new(0)
	emitter.FlipbookStartRandom = true
	emitter.Color = ColorSequence.new(RainEmitters.colour(SPRAY.color))
	emitter.Size = NumberSequence.new(spec.size[1], spec.size[2])
	emitter.Transparency = NumberSequence.new(spec.transparency[1], spec.transparency[2])
	emitter.Lifetime = NumberRange.new(spec.lifetime[1], spec.lifetime[2])
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-40, 40)
	emitter.SpreadAngle = Vector2.new(SPRAY.spread, SPRAY.spread)
	emitter.EmissionDirection = Enum.NormalId.Front
	emitter.VelocityInheritance = 1
	emitter.Drag = SPRAY.drag
	emitter.LightInfluence = 1
	emitter.LightEmission = 0
	emitter.Rate = 0
	emitter.Parent = parent
	return { emitter = emitter, share = share, rate = 0 }
end

-- Attachments under the chassis (or any part, unrigged) behind each rear tyre's contact
-- patch, aimed back and a little up, and one behind the car for the mist.
local function sprays(model: Model): ({ Spray }, { Attachment })
	local chassis = model:FindFirstChild("Chassis")
	local host = if chassis and chassis:IsA("BasePart")
		then chassis
		else model:FindFirstChildWhichIsA("BasePart", true)
	local entry = Catalog.of(model)
	if host == nil or entry == nil then
		return {}, {}
	end
	local frame = model:GetPivot()
	local aim = CFrame.Angles(math.rad(SPRAY.rise), 0, 0)
	local found, attachments = {}, {}
	local function mount(at: Vector3, spec: Config.Puffs, share: number)
		local attachment = Instance.new("Attachment")
		attachment.Name = "DriveLabSpray"
		attachment.CFrame = host.CFrame:ToObjectSpace(CFrame.lookAt(at, at + frame.ZVector) * aim)
		attachment.Parent = host
		table.insert(attachments, attachment)
		table.insert(found, puffs(attachment, spec, share))
	end
	local rear = Vector3.zero
	for index = 3, 4 do
		local wheel = model:FindFirstChild(entry.model.wheels[index], true)
		if wheel and wheel:IsA("BasePart") then
			local radius = wheel.Size.Y / 2
			local contact = wheel.Position - frame.UpVector * radius * 0.85 + frame.ZVector * radius * 0.7
			mount(contact, SPRAY.puffs, 1)
			rear += contact / 2
		end
	end
	if #found > 0 then
		mount(rear + frame.ZVector * Units.metresToStuds(0.6), SPRAY.mist, SPRAY.mistShare)
	end
	return found, attachments
end

local function build(water: CarWater, model: Model): Rig
	local found, attachments = sprays(model)
	local made = patches(model, water.folder)
	local parts: { BasePart } = {}
	for _, patch in made do
		table.insert(parts, patch.part)
	end
	return {
		model = model,
		patches = made,
		parts = parts,
		sprays = found,
		attachments = attachments,
		speed = -1,
	}
end

local function clear(water: CarWater)
	local rig = water.rig
	if rig == nil then
		return
	end
	water.rig = nil
	for _, patch in rig.patches do
		patch.part:Destroy()
	end
	for _, attachment in rig.attachments do
		attachment:Destroy()
	end
end

-- Writes an emitter's rate only when it changes; returns the rate now set.
local function setRate(emitter: ParticleEmitter, current: number, rate: number): number
	if rate ~= current then
		emitter.Rate = rate
	end
	return rate
end

local CarWater = {}

function CarWater.new(): CarWater
	local folder = Instance.new("Folder")
	folder.Name = "DriveLabCarWater"
	folder.Parent = Workspace
	return { folder = folder, rig = nil, frames = {} }
end

-- `exposure` is the share of open sky over the car; `wetness` the road's; `speedKmh` the car's.
function CarWater.update(
	water: CarWater,
	model: Model?,
	intensity: number,
	exposure: number,
	wetness: number,
	speedKmh: number
)
	local rig = water.rig
	if rig and (rig.model ~= model or rig.model.Parent == nil) then
		clear(water)
		rig = nil
	end
	if model == nil or (rig == nil and intensity <= 0 and wetness <= 0) then
		return
	end
	local active: Rig = rig or build(water, model)
	water.rig = active
	local pivot = model:GetPivot()
	table.clear(water.frames)
	for _, patch in active.patches do
		table.insert(water.frames, pivot * patch.offset)
		local rate = Rules.splashes(intensity, exposure, patch.area, SPLASHES.rates)
		patch.rate = setRate(patch.emitter, patch.rate, rate)
	end
	Workspace:BulkMoveTo(active.parts, water.frames, Enum.BulkMoveMode.FireCFrameChanged)
	local spray = Rules.spray(speedKmh, wetness, SPRAY.rates)
	local speed = Units.metresToStuds(Units.kmhToMps(math.abs(speedKmh))) * SPRAY.throwBack
	local restyle = math.abs(speed - active.speed) > math.max(speed, 1) * 0.05
	for _, item in active.sprays do
		if restyle then
			item.emitter.Speed = NumberRange.new(speed * 0.8, speed)
		end
		item.rate = setRate(item.emitter, item.rate, spray * item.share)
	end
	if restyle then
		active.speed = speed
	end
end

function CarWater.destroy(water: CarWater)
	clear(water)
	water.folder:Destroy()
end

return CarWater
