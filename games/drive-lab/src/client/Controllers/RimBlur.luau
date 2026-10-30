--!strict
--[[
	Blurs the rims of every car on this client at speed. Each wheel gets three pieces cut from
	its own mesh (Config/RimBlur): the tyre and the rest, the sharp rim face, and a disc carrying
	the face blurred over every rotation. Below the blur nothing changes; above it the car's wheel
	is hidden on this client and the pieces stand in, the face fading out as the disc fades in
	(Rules/RimBlur). The pieces are massless, collide with nothing and hang on welds to the wheel,
	so they follow its spin, steering and travel and the physics never sees them.

	The spin comes from the car's speed and its tyre radius, not from the wheel itself: the
	wheels' welds are moved by the driver's client only, and every client sees the chassis move.
]]
local CollectionService = game:GetService("CollectionService")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CarRig = require(ReplicatedStorage.Shared.Car.CarRig)
local Catalog = require(ReplicatedStorage.Shared.Config.Cars.Catalog)
local Config = require(ReplicatedStorage.Shared.Config.RimBlur)
local Geometry = require(ReplicatedStorage.Shared.Vehicle.Geometry)
local Rules = require(ReplicatedStorage.Shared.Rules.RimBlur)
local Units = require(ReplicatedStorage.Shared.Units)

type Wheel = {
	part: BasePart,
	-- Metres.
	radius: number,
	tyre: BasePart,
	face: BasePart,
	disc: BasePart,
	shown: Rules.Layers,
}

type Car = { model: Model, chassis: BasePart, spin: Rules.Tuning, wheels: { Wheel }, owned: { Instance } }

local cars: { [Model]: Car } = {}
local waiting: { [Model]: true } = {}

local function piece(template: Instance, wheel: BasePart, scale: number): BasePart?
	local offset = template:GetAttribute(Config.OFFSET_ATTRIBUTE)
	if not template:IsA("BasePart") or typeof(offset) ~= "CFrame" then
		return nil
	end
	local copy = template:Clone()
	copy.Size = template.Size * scale
	copy.Anchored = false
	copy.Massless = true
	copy.CanCollide = false
	copy.CanQuery = false
	copy.CanTouch = false
	copy.LocalTransparencyModifier = 1
	copy.CFrame = wheel.CFrame * CFrame.new(offset.Position * scale) * offset.Rotation
	local weld = Instance.new("Weld")
	weld.Part0 = wheel
	weld.Part1 = copy
	weld.C0 = CFrame.new(offset.Position * scale) * offset.Rotation
	weld.Parent = copy
	copy.Parent = wheel
	return copy
end

local function destroy(owned: { Instance })
	for _, instance in owned do
		instance:Destroy()
	end
end

local function pieceRoot(): Instance?
	local assets = ReplicatedStorage:FindFirstChild("DriveLabAssets")
	return assets and assets:FindFirstChild(Config.ASSETS_FOLDER)
end

local function pieceSet(name: string): Instance?
	local root = pieceRoot()
	return root and root:FindFirstChild(name)
end

-- The car's pieces, or nil while its rig or its assets have not streamed in. A car with no
-- pieces in the place is never blurred.
local function attach(model: Model): Car?
	local name = model:GetAttribute("Car")
	if typeof(name) ~= "string" then
		return nil
	end
	local entry = Catalog.cars[name]
	local set = pieceSet(name)
	local chassis = model:FindFirstChild("Chassis")
	if entry == nil or set == nil or chassis == nil or not chassis:IsA("BasePart") then
		return nil
	end
	local car: Car = { model = model, chassis = chassis, spin = entry.rimBlur.spin, wheels = {}, owned = {} }
	for index, wheelName in entry.model.wheels do
		local weld = chassis:FindFirstChild(wheelName)
		local part = if weld and weld:IsA("Weld") then weld.Part1 else nil
		local folder = set:FindFirstChild(wheelName)
		local size = folder and folder:GetAttribute(Config.WHEEL_SIZE_ATTRIBUTE)
		if part == nil or folder == nil or typeof(size) ~= "Vector3" then
			destroy(car.owned)
			return nil
		end
		local scale = part.Size.Y / size.Y
		local names = Config.PIECES
		local tyre = folder:FindFirstChild(names.tyre)
		local face = folder:FindFirstChild(names.face)
		local disc = folder:FindFirstChild(names.disc)
		local tyrePiece = tyre and piece(tyre, part, scale)
		local facePiece = face and piece(face, part, scale)
		local discPiece = disc and piece(disc, part, scale)
		for _, made in { tyrePiece, facePiece, discPiece } do
			if made then
				table.insert(car.owned, made)
			end
		end
		if tyrePiece == nil or facePiece == nil or discPiece == nil then
			destroy(car.owned)
			return nil
		end
		table.insert(car.wheels, {
			part = part,
			radius = Geometry.axle(entry.physics, index).tyre.radius,
			tyre = tyrePiece,
			face = facePiece,
			disc = discPiece,
			shown = Rules.layers(0),
		})
	end
	return car
end

local function show(wheel: Wheel, layers: Rules.Layers)
	local swapped = layers.swapped
	wheel.part.LocalTransparencyModifier = if swapped then 1 else 0
	wheel.tyre.LocalTransparencyModifier = if swapped then 0 else 1
	-- A fully faded face is not drawn at all, rather than drawn invisible.
	wheel.face.LocalTransparencyModifier = if swapped and layers.face < 1 then 0 else 1
	wheel.face.Transparency = layers.face
	wheel.disc.LocalTransparencyModifier = if swapped then 0 else 1
	wheel.disc.Transparency = layers.disc
	wheel.shown = layers
end

local function release(car: Car)
	for _, wheel in car.wheels do
		if wheel.part.Parent then
			wheel.part.LocalTransparencyModifier = 0
		end
	end
	destroy(car.owned)
end

local function forget(model: Model)
	waiting[model] = nil
	local car = cars[model]
	if car then
		cars[model] = nil
		release(car)
	end
end

local function try(model: Model)
	if cars[model] or not model:HasTag(CarRig.TAG) then
		waiting[model] = nil
		return
	end
	local car = attach(model)
	if car then
		waiting[model] = nil
		cars[model] = car
	else
		waiting[model] = true
	end
end

local function streamedOut(car: Car): boolean
	for _, wheel in car.wheels do
		if wheel.part.Parent == nil then
			return true
		end
	end
	return false
end

local function update()
	for model, car in cars do
		local chassis = car.chassis
		if model.Parent == nil then
			forget(model)
			continue
		end
		if chassis.Parent == nil or streamedOut(car) then
			-- Streamed out: build again from whatever comes back.
			forget(model)
			waiting[model] = true
			continue
		end
		local studs = math.abs(chassis.AssemblyLinearVelocity:Dot(chassis.CFrame.LookVector))
		local speed = Units.studsToMetres(studs)
		for _, wheel in car.wheels do
			local layers = Rules.layers(Rules.share(car.spin, Rules.spin(speed, wheel.radius)))
			if Rules.changed(wheel.shown, layers, Config.STEP) then
				show(wheel, layers)
			end
		end
	end
end

local RimBlurController = {}

-- Builds the pieces on `model` now and shows them at `share` (0 sharp, 1 blurred), for edit-mode
-- captures; returns a function that removes them again.
function RimBlurController.preview(model: Model, share: number): () -> ()
	local car = attach(model)
	assert(car, `{model.Name} has no rim blur pieces or no rig`)
	for _, wheel in car.wheels do
		show(wheel, Rules.layers(share))
	end
	return function()
		release(car)
	end
end

function RimBlurController.start()
	local templates = pieceRoot()
	if templates then
		-- A disc's maps otherwise load the first time it shows, and it is white until they do.
		task.spawn(ContentProvider.PreloadAsync, ContentProvider, { templates })
	end
	for _, instance in CollectionService:GetTagged(CarRig.TAG) do
		if instance:IsA("Model") then
			try(instance)
		end
	end
	CollectionService:GetInstanceAddedSignal(CarRig.TAG):Connect(function(instance: Instance)
		if instance:IsA("Model") then
			try(instance)
		end
	end)
	CollectionService:GetInstanceRemovedSignal(CarRig.TAG):Connect(function(instance: Instance)
		if instance:IsA("Model") then
			forget(instance)
		end
	end)
	RunService.Heartbeat:Connect(update)
	task.spawn(function()
		while true do
			task.wait(Config.RETRY_SECONDS)
			for model in waiting do
				if model.Parent == nil then
					waiting[model] = nil
				else
					try(model)
				end
			end
		end
	end)
end

return RimBlurController
