--!strict
--[[
	Exhaust flames for a car: a jet and a fireball out of each outlet and a flash of light,
	fired by Controllers/CarAudio with every pop it plays, so sight and sound land together. The
	emitters are built on a car's first pop, on its rear light clusters (the outlets are placed
	from the clusters' whole boxes, the model binding's exhaust), and go with the car.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Binding = require(ReplicatedStorage.Shared.Config.Cars.Binding)
local Config = require(ReplicatedStorage.Shared.Config.ExhaustFlames)
local Units = require(ReplicatedStorage.Shared.Units)

type Outlet = { jet: ParticleEmitter, fireball: ParticleEmitter, flash: PointLight }

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

local function build(model: Model, exhaust: Binding.Exhaust): { Outlet }?
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
		local attachment = Instance.new("Attachment")
		attachment.Name = "ExhaustOutlet"
		attachment.CFrame = left.CFrame:ToObjectSpace(CFrame.lookAt(at, at + direction))
		attachment.Parent = left

		local jet = emitter(attachment, Config.JET_TEXTURE)
		jet.Orientation = Enum.ParticleOrientation.VelocityParallel
		jet.Lifetime = range(Config.JET.lifetime)
		jet.Speed = range(Config.JET.speed)
		jet.Size = NumberSequence.new(Config.JET.size.from, Config.JET.size.to)
		jet.SpreadAngle = Vector2.new(6, 6)
		jet.Brightness = 2

		local fireball = emitter(attachment, Config.FIREBALL_TEXTURE)
		fireball.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2
		fireball.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
		fireball.Lifetime = range(Config.FIREBALL.lifetime)
		fireball.Speed = range(Config.FIREBALL.speed)
		fireball.Size = NumberSequence.new(Config.FIREBALL.size.from, Config.FIREBALL.size.to)
		fireball.Rotation = NumberRange.new(0, 360)
		fireball.SpreadAngle = Vector2.new(15, 15)
		fireball.Brightness = 1.5
		fireball.Color = ColorSequence.new(Config.FIREBALL.hot, Config.FIREBALL.cool)

		local flash = Instance.new("PointLight")
		flash.Range = Config.FLASH.range
		flash.Brightness = Config.FLASH.brightness
		flash.Color = Config.FLASH.color
		flash.Shadows = false
		flash.Enabled = false
		flash.Parent = attachment

		table.insert(outlets, { jet = jet, fireball = fireball, flash = flash })
	end
	return outlets
end

local ExhaustFlames = {}

-- One pop out of the car's outlets; strength 0 to 1 scales how much flame.
function ExhaustFlames.burst(model: Model, exhaust: Binding.Exhaust, strength: number)
	local found: { Outlet }? = outletsOf[model] or build(model, exhaust)
	if found == nil then
		return
	end
	local outlets: { Outlet } = found
	outletsOf[model] = outlets
	local share = math.clamp(strength, 0, 1)
	local count = math.round(Config.JET.count.from + (Config.JET.count.to - Config.JET.count.from) * share)
	local stamp = os.clock()
	for _, outlet in outlets do
		outlet.jet:Emit(count)
		outlet.fireball:Emit(if share > 0.5 then 2 else 1)
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
