--!strict
--[[
	Exhaust flames for a car: a jet and a fireball out of each outlet and a flash of light,
	fired by Controllers/CarAudio with every pop it plays, so sight and sound land together. The
	emitters are built on a car's first pop, on its rear light clusters (the outlets are placed
	from them, Config/ExhaustFlames), and go with the car.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

local function build(model: Model): { Outlet }?
	local left = model:FindFirstChild("Light_RearLeft", true)
	local right = model:FindFirstChild("Light_RearRight", true)
	if left == nil or right == nil or not left:IsA("BasePart") or not right:IsA("BasePart") then
		return nil
	end
	local axes = left.CFrame
	local middle = (left.Position + right.Position) / 2
	local spot = Config.OUTLETS
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
function ExhaustFlames.burst(model: Model, strength: number)
	local found: { Outlet }? = outletsOf[model] or build(model)
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
