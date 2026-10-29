--!strict
--[[
	Rigs every car in the place and decides who simulates it. While someone drives, the driver's
	client owns the assembly and runs the physics, so the car answers the controls without a
	round trip; the server only keeps the car inside a speed envelope, since a client that owns
	a body can put it anywhere. While a car stands empty the server runs it, handbrake on.
]]
local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CarRig = require(ReplicatedStorage.Shared.Car.CarRig)
local Catalog = require(ReplicatedStorage.Shared.Config.Cars.Catalog)
local Driving = require(ReplicatedStorage.Shared.Config.Driving)
local Interface = require(ReplicatedStorage.Shared.Vehicle.Interface)
local Log = require(ReplicatedStorage.Kit.Log)
local VehicleRunner = require(ReplicatedStorage.Shared.Car.VehicleRunner)

type Car = {
	rig: CarRig.Rig,
	entry: Catalog.Entry,
	-- The server's own simulation, while nobody drives.
	runner: VehicleRunner.Runner?,
	driver: Player?,
	-- Parts made massless while their character sits in the car.
	carried: { BasePart },
	reclaimedUntil: number,
}

local log = Log.scope("Cars")
local cars: { Car } = {}

local PARKED: Interface.DriverInput = {
	throttle = 0,
	brake = 0,
	steer = 0,
	handbrake = 1,
	shiftUp = false,
	shiftDown = false,
	gearboxMode = "auto",
	drivingMode = "Strada",
	assists = { abs = true, tc = true, esc = true },
}

local function setupCollisionGroups()
	PhysicsService:RegisterCollisionGroup(CarRig.RAY_GROUP)
	PhysicsService:RegisterCollisionGroup(CarRig.CHARACTER_GROUP)
	PhysicsService:CollisionGroupSetCollidable(CarRig.RAY_GROUP, CarRig.CHARACTER_GROUP, false)
	PhysicsService:RegisterCollisionGroup(CarRig.DOOR_GROUP)
	PhysicsService:CollisionGroupSetCollidable(CarRig.RAY_GROUP, CarRig.DOOR_GROUP, false)
	PhysicsService:CollisionGroupSetCollidable("Default", CarRig.DOOR_GROUP, false)
	local function enlist(part: Instance)
		if part:IsA("BasePart") then
			part.CollisionGroup = CarRig.CHARACTER_GROUP
		end
	end
	local function onCharacter(character: Model)
		for _, part in character:GetDescendants() do
			enlist(part)
		end
		character.DescendantAdded:Connect(enlist)
	end
	local function onPlayer(player: Player)
		if player.Character then
			onCharacter(player.Character)
		end
		player.CharacterAdded:Connect(onCharacter)
	end
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
end

-- A seated character is welded into the car's assembly; its mass would change the car the
-- vehicle model assumes, so it rides massless.
local function carry(car: Car, character: Model?)
	for _, part in car.carried do
		part.Massless = false
	end
	table.clear(car.carried)
	if character == nil then
		return
	end
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") and not part.Massless then
			part.Massless = true
			table.insert(car.carried, part)
		end
	end
end

-- Services/CarEntry seats the driver, and sets their size down before and back after.
local function park(car: Car)
	carry(car, nil)
	car.driver = nil
	car.rig.model:SetAttribute("DriverUserId", 0)
	car.rig.chassis:SetNetworkOwner(nil)
	car.runner = VehicleRunner.new(car.rig, car.entry.physics)
end

local function hand(car: Car, player: Player)
	carry(car, player.Character)
	car.runner = nil
	car.driver = player
	car.rig.model:SetAttribute("DriverUserId", player.UserId)
	VehicleRunner.release(car.rig)
	car.rig.chassis:SetNetworkOwner(player)
end

local function onOccupant(car: Car)
	local occupant = car.rig.seat.Occupant
	local player = occupant and Players:GetPlayerFromCharacter(occupant.Parent)
	if player then
		hand(car, player)
	else
		park(car)
	end
end

local function rig(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local name = model:GetAttribute("Car")
	local entry = if typeof(name) == "string" then Catalog[name] else nil
	if entry == nil then
		log.warn(`{model:GetFullName()} has no known "Car" attribute`)
		return
	end
	local car: Car = {
		rig = CarRig.build(model, entry.physics, entry.model),
		entry = entry,
		runner = nil,
		driver = nil,
		carried = {},
		reclaimedUntil = 0,
	}
	park(car)
	car.rig.seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		onOccupant(car)
	end)
	table.insert(cars, car)
end

-- A driven car outside the envelope goes back to the server for a moment, slowed to the
-- limit: the driver feels a hitch, not a kick.
local function guard(car: Car)
	local driver = car.driver
	if driver == nil then
		return
	end
	local now = os.clock()
	if now < car.reclaimedUntil then
		return
	end
	if car.rig.chassis:GetNetworkOwner() ~= driver then
		car.rig.chassis:SetNetworkOwner(driver)
	end
	local velocity = car.rig.chassis.AssemblyLinearVelocity
	local speed = velocity.Magnitude
	if speed == speed and speed <= Driving.MAX_SPEED then
		return
	end
	log.warn(`{driver.Name}'s car left its envelope at {speed} studs/s`)
	car.rig.chassis:SetNetworkOwner(nil)
	car.rig.chassis.AssemblyLinearVelocity = if speed == speed
		then velocity.Unit * Driving.MAX_SPEED
		else Vector3.zero
	car.reclaimedUntil = now + Driving.RECLAIM_SECONDS
end

local function update(dt: number)
	for _, car in cars do
		local runner = car.runner
		if runner then
			VehicleRunner.step(runner, PARKED, dt)
			VehicleRunner.animate(runner, dt)
		else
			guard(car)
		end
	end
end

local Service = {}

function Service.start()
	setupCollisionGroups()
	for _, model in CollectionService:GetTagged(Driving.SPAWN_TAG) do
		rig(model)
	end
	RunService.PreSimulation:Connect(update)
end

return Service
