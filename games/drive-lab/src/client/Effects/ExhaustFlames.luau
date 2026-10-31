--!strict
--[[
	Exhaust flames for a car: a jet and a fireball out of each outlet and a flash of light,
	fired by Controllers/CarAudio with the pops it plays, so sight and sound land together
	(Rules/ExhaustFlames decides which pops and how much). The emitters are built on a car's first
	flame and go with the car: at the outlets its model binding gives (exhaustOutlets, on the
	chassis, each along its own axis), or else on its rear light clusters (the binding's exhaust,
	the outlets placed from the clusters' whole boxes).
]]
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Binding = require(ReplicatedStorage.Shared.Config.Cars.Binding)
local CarLights = require(ReplicatedStorage.Shared.Config.CarLights)
local Config = require(ReplicatedStorage.Shared.Config.ExhaustFlames)
local Lamps = require(ReplicatedStorage.Shared.Rules.CarLights)
local Rules = require(ReplicatedStorage.Shared.Rules.ExhaustFlames)
local Units = require(ReplicatedStorage.Shared.Units)

type Outlet = { jet: ParticleEmitter, fireball: ParticleEmitter, flash: PointLight }

local JET_BRIGHTNESS = 2
local FIREBALL_BRIGHTNESS = 1.5

local outletsOf: { [Model]: { Outlet } } = setmetatable({}, { __mode = "k" }) :: any
local flashes: { [PointLight]: number } = {}

local function range(value: { from: number, to: number }): NumberRange
	return NumberRange.new(value.from, value.to)
end

local function emitter(parent: Attachment, texture: string): ParticleEmitter
	local particles = Instance.new("ParticleEmitter")
	particles.Texture = texture
	particles.Rate = 0
	particles.EmissionDirection = Enum.NormalId.Front
	particles.LightEmission = 1
	particles.LightInfluence = 0
	particles.LockedToPart = true
	particles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.6, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	particles.Parent = parent
	return particles
end

-- A rear light cluster is cut into its lamps (tools/blender/split_lights.py): Light_RearLeft is
-- its housing and Light_RearLeft_<Lamp> the rest. The outlets were measured from the whole
-- cluster's box, the union of its pieces, in the housing's axes (all pieces share them).
local function clusterCentre(model: Model, housing: BasePart): Vector3
	local prefix = housing.Name .. "_"
	local low, high = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, piece in model:GetDescendants() do
		if piece:IsA("BasePart") and (piece == housing or string.sub(piece.Name, 1, #prefix) == prefix) then
			local centre = housing.CFrame:PointToObjectSpace(piece.Position)
			low = low:Min(centre - piece.Size / 2)
			high = high:Max(centre + piece.Size / 2)
		end
	end
	return housing.CFrame:PointToWorldSpace((low + high) / 2)
end

local function makeOutlet(attachment: Attachment): Outlet
	local jet = emitter(attachment, Config.JET_TEXTURE)
	jet.Orientation = Enum.ParticleOrientation.VelocityParallel
	jet.Lifetime = range(Config.JET.lifetime)
	jet.Speed = range(Config.JET.speed)
	jet.Size = NumberSequence.new(Config.JET.size.from, Config.JET.size.to)
	jet.SpreadAngle = Vector2.new(6, 6)
	jet.Brightness = JET_BRIGHTNESS

	local fireball = emitter(attachment, Config.FIREBALL_TEXTURE)
	fireball.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2
	fireball.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	fireball.Lifetime = range(Config.FIREBALL.lifetime)
	fireball.Speed = range(Config.FIREBALL.speed)
	fireball.Size = NumberSequence.new(Config.FIREBALL.size.from, Config.FIREBALL.size.to)
	fireball.Rotation = NumberRange.new(0, 360)
	fireball.SpreadAngle = Vector2.new(15, 15)
	fireball.Brightness = FIREBALL_BRIGHTNESS
	fireball.Color = ColorSequence.new(Config.FIREBALL.hot, Config.FIREBALL.cool)

	local flash = Instance.new("PointLight")
	flash.Range = Config.FLASH.range
	flash.Brightness = Config.FLASH.brightness
	flash.Color = Config.FLASH.color
	flash.Shadows = false
	flash.Enabled = false
	flash.Parent = attachment

	return { jet = jet, fireball = fireball, flash = flash }
end

local function newAttachment(parent: BasePart, frame: CFrame): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = "ExhaustOutlet"
	attachment.CFrame = frame
	attachment.Parent = parent
	return attachment
end

local function fromClusters(model: Model, exhaust: Binding.Exhaust): { Outlet }?
	local left = model:FindFirstChild(exhaust.left, true)
	local right = model:FindFirstChild(exhaust.right, true)
	if left == nil or right == nil or not left:IsA("BasePart") or not right:IsA("BasePart") then
		return nil
	end
	local axes = left.CFrame
	local middle = (clusterCentre(model, left) + clusterCentre(model, right)) / 2
	local spot = exhaust.outlet
	local direction = (-axes.LookVector + axes.UpVector * Config.RISE).Unit
	local outlets = {}
	for _, side in { -1, 1 } do
		local at = middle
			+ axes.RightVector * Units.metresToStuds(side * spot.right)
			- axes.LookVector * Units.metresToStuds(spot.back)
			+ axes.UpVector * Units.metresToStuds(spot.up)
		local frame = left.CFrame:ToObjectSpace(CFrame.lookAt(at, at + direction))
		table.insert(outlets, makeOutlet(newAttachment(left, frame)))
	end
	return outlets
end

-- Each outlet's centre is metres from the centre of mass in the car frame, before the body was
-- raised, as the rig places the chassis.
local function fromOutlets(model: Model, binding: Binding.CarModel, rise: number): { Outlet }?
	local chassis = model.PrimaryPart
	local list = binding.exhaustOutlets
	if chassis == nil or list == nil then
		return nil
	end
	local outlets = {}
	for _, spec in list do
		local centre = spec.centre
		local at = Vector3.new(centre.right, centre.up + binding.bodyRaise, -centre.forward)
			* Units.metresToStuds(1)
		local way = Rules.direction(spec.axis, rise)
		local frame = CFrame.lookAt(at, at + Vector3.new(way.x, way.y, way.z))
		table.insert(outlets, makeOutlet(newAttachment(chassis, frame)))
	end
	return outlets
end

local function build(model: Model, binding: Binding.CarModel, flames: Rules.CarFlames?): { Outlet }?
	if binding.exhaustOutlets then
		return fromOutlets(model, binding, if flames then flames.rise else Config.RISE)
	end
	local exhaust = binding.exhaust
	return if exhaust then fromClusters(model, exhaust) else nil
end

-- How bright this car's flames are drawn now; in full, always, for a car without its own flames.
local function visibility(flames: Rules.CarFlames?): number
	if flames == nil then
		return 1
	end
	local daylight = Lamps.daylight(Lighting.Brightness, CarLights.NIGHT_BRIGHTNESS, CarLights.DAY_BRIGHTNESS)
	return Rules.visibility(daylight, flames.dayShare)
end

local ExhaustFlames = {}

-- One flame out of the car's outlets; `strength` (0 to 1, Rules/ExhaustFlames.share) scales how
-- much.
function ExhaustFlames.burst(
	model: Model,
	binding: Binding.CarModel,
	strength: number,
	flames: Rules.CarFlames?
)
	local found: { Outlet }? = outletsOf[model] or build(model, binding, flames)
	if found == nil then
		return
	end
	local outlets: { Outlet } = found
	outletsOf[model] = outlets
	local share = math.clamp(strength, 0, 1)
	local count = math.round(Config.JET.count.from + (Config.JET.count.to - Config.JET.count.from) * share)
	local fireballs = Rules.fireballs(share, if flames then flames.fireballFrom else 0)
	local seen = visibility(flames)
	local stamp = os.clock()
	for _, outlet in outlets do
		if flames then
			outlet.jet.Brightness = JET_BRIGHTNESS * seen
			outlet.fireball.Brightness = FIREBALL_BRIGHTNESS * seen
			outlet.flash.Brightness = Config.FLASH.brightness * seen
		end
		outlet.jet:Emit(count)
		if fireballs == 0 then
			continue
		end
		outlet.fireball:Emit(fireballs)
		outlet.flash.Enabled = true
		flashes[outlet.flash] = stamp
		-- The flash goes out after its moment unless a later pop has lit it again.
		task.delay(Config.FLASH.seconds, function()
			if flashes[outlet.flash] == stamp then
				outlet.flash.Enabled = false
				flashes[outlet.flash] = nil
			end
		end)
	end
end

return ExhaustFlames
