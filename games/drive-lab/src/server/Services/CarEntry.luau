--!strict
--[[
	Getting in and out of cars, their drivers' doors and starting them, on the server: the only
	writer of each car's state (Car/CarState), which every client turns into the same body
	animation, door angle and start-up (Rules/CarEntry). A prompt holds the seat or the door for
	one player while their client walks them to the door mark; the client then asks, and the
	request is checked against the rules and where the character stands. The body changes
	between its own size and the seated size here, eased, so every player sees one smooth
	change instead of a jump.
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CarRig = require(ReplicatedStorage.Shared.Car.CarRig)
local CarState = require(ReplicatedStorage.Shared.Car.CarState)
local Catalog = require(ReplicatedStorage.Shared.Config.Cars.Catalog)
local Config = require(ReplicatedStorage.Shared.Config.CarEntry)
local DoorMark = require(ReplicatedStorage.Shared.Car.DoorMark)
local Driving = require(ReplicatedStorage.Shared.Config.Driving)
local Log = require(ReplicatedStorage.Kit.Log)
local Net = require(ReplicatedStorage.Kit.Net)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Rules = require(ReplicatedStorage.Shared.Rules.CarEntry)
local Units = require(ReplicatedStorage.Shared.Units)

type Intent = "Enter" | "Door"
type Reservation = { player: Player, intent: Intent, at: number }
type Car = {
	model: Model,
	seat: Seat,
	chassis: BasePart,
	enterPrompt: ProximityPrompt,
	doorPrompt: ProximityPrompt,
	reservation: Reservation?,
	-- The character in the seat, remembered so it can be resized once it has left.
	occupant: Model?,
}
type Resize = { character: Model, from: number, to: number, at: number }
type Request = { car: Model, action: Rules.Action }

local ATTRIBUTE = Config.ATTRIBUTES
local ACTION_LIMIT = { perSecond = 4, burst = 6 }
local PROMPT_LIMIT = { perSecond = 2, burst = 3 }
-- R6 standing: two studs of leg and half the torso under the root's centre, times the scale.
local ROOT_HEIGHT = 3
-- Studs past the prompt distance allowed for a character still moving when it pressed.
local DISTANCE_SLACK = 2
local SCALE_EPSILON = 1e-3
local REST: Rules.State = {
	entry = "None",
	entryAt = 0,
	entryDoorOpen = false,
	door = "Closed",
	doorAt = 0,
	engine = "Off",
	engineAt = 0,
}

local log = Log.scope("CarEntry")
local cars: { [Model]: Car } = {}
local resizes: { [Player]: Resize } = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function body(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if
		character == nil
		or humanoid == nil
		or humanoid.Health <= 0
		or root == nil
		or not root:IsA("BasePart")
	then
		return nil, nil, nil
	end
	return character, humanoid, root
end

local function resize(player: Player, to: number)
	local character = player.Character
	if character and math.abs(character:GetScale() - to) > SCALE_EPSILON then
		resizes[player] = { character = character, from = character:GetScale(), to = to, at = now() }
	end
end

local function speedKmh(car: Car): number
	return Units.mpsToKmh(Units.studsToMetres(car.chassis.AssemblyLinearVelocity.Magnitude))
end

local function driver(car: Car): Player?
	local occupant = car.seat.Occupant
	return if occupant then Players:GetPlayerFromCharacter(occupant.Parent) else nil
end

local function atMark(car: Car, root: BasePart): boolean
	return DoorMark.distance(car.seat, root.Position) <= Config.MARK_TOLERANCE
end

local function release(car: Car)
	car.reservation = nil
	car.model:SetAttribute(ATTRIBUTE.RESERVED_BY, 0)
end

-- The root's frame standing on the ground at the mark.
local function standingFrame(car: Car, scale: number): CFrame
	local mark = DoorMark.frame(car.seat)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { car.model }
	-- Passes through characters, as the wheels' rays do.
	params.CollisionGroup = CarRig.RAY_GROUP
	local hit = Workspace:Raycast(mark.Position + Vector3.new(0, 4, 0), Vector3.new(0, -30, 0), params)
	local height = if hit then hit.Position.Y + ROOT_HEIGHT * scale else mark.Position.Y
	return mark.Rotation + Vector3.new(mark.Position.X, height, mark.Position.Z)
end

local function onPrompt(car: Car, player: Player, intent: Intent)
	if not Net.allow(player, "CarPrompt", PROMPT_LIMIT) or car.reservation ~= nil then
		return
	end
	local _, humanoid, root = body(player)
	if humanoid == nil or root == nil or humanoid.SeatPart ~= nil then
		return
	end
	if DoorMark.distance(car.seat, root.Position) > Config.PROMPT_DISTANCE + DISTANCE_SLACK then
		return
	end
	local state, at = CarState.read(car.model), now()
	local allowed = if intent == "Enter"
		then Rules.canEnter(state, at)
		else Rules.canMoveDoor(state, at, speedKmh(car), false)
	if not allowed then
		return
	end
	car.reservation = { player = player, intent = intent, at = at }
	car.model:SetAttribute(ATTRIBUTE.RESERVED_AT, at)
	car.model:SetAttribute(ATTRIBUTE.RESERVED_BY, player.UserId)
	if intent == "Enter" then
		resize(player, Driving.DRIVER_SCALE)
	end
end

local function reservedFor(car: Car, player: Player, intent: Intent): boolean
	local reservation = car.reservation
	return reservation ~= nil and reservation.player == player and reservation.intent == intent
end

local function enter(car: Car, player: Player)
	local character, humanoid, root = body(player)
	local state, at = CarState.read(car.model), now()
	if character == nil or humanoid == nil or root == nil or not reservedFor(car, player, "Enter") then
		return
	end
	if car.seat.Occupant ~= nil or not atMark(car, root) or not Rules.canEnter(state, at) then
		return
	end
	release(car)
	-- The clips are authored at the seated size; a client that asked early is snapped to it.
	resizes[player] = nil
	if math.abs(character:GetScale() - Driving.DRIVER_SCALE) > SCALE_EPSILON then
		character:ScaleTo(Driving.DRIVER_SCALE)
	end
	-- State first: a client seeing the seat before the state would play nothing.
	CarState.write(car.model, {
		entry = "Enter",
		entryAt = at,
		entryDoorOpen = Rules.doorOpenness(state, at) >= 0.5,
		door = "Closed",
		doorAt = at,
		engine = "Off",
		engineAt = state.engineAt,
	})
	car.seat:Sit(humanoid)
end

local function moveDoor(car: Car, player: Player)
	local state, at = CarState.read(car.model), now()
	local inside = driver(car) == player
	if inside then
		if not Rules.canMoveDoor(state, at, speedKmh(car), true) then
			return
		end
	else
		local _, _, root = body(player)
		if root == nil or not reservedFor(car, player, "Door") or not atMark(car, root) then
			return
		end
		if not Rules.canMoveDoor(state, at, speedKmh(car), false) then
			return
		end
		release(car)
	end
	car.model:SetAttribute(ATTRIBUTE.DOOR_AT, at)
	car.model:SetAttribute(ATTRIBUTE.DOOR, Rules.doorClip(state, at, inside))
end

local function start(car: Car, player: Player)
	local state, at = CarState.read(car.model), now()
	if driver(car) == player and Rules.canStart(state, at) then
		car.model:SetAttribute(ATTRIBUTE.ENGINE_AT, at)
		car.model:SetAttribute(ATTRIBUTE.ENGINE, "On")
	end
end

local function finishExit(car: Car, player: Player, startedAt: number)
	local state = CarState.read(car.model)
	if state.entry ~= "Exit" or state.entryAt ~= startedAt then
		return
	end
	CarState.write(car.model, {
		entry = "None",
		entryAt = state.entryAt,
		entryDoorOpen = false,
		door = "Closed",
		doorAt = state.doorAt,
		engine = "Off",
		engineAt = state.engineAt,
	})
	local character, humanoid = body(player)
	if character == nil or humanoid == nil or car.seat.Occupant ~= humanoid then
		return
	end
	local weld = car.seat:FindFirstChild("SeatWeld")
	if weld then
		weld:Destroy()
	end
	humanoid.Sit = false
	character:PivotTo(standingFrame(car, character:GetScale()))
	resize(player, 1)
end

local function exit(car: Car, player: Player)
	local state, at = CarState.read(car.model), now()
	if driver(car) ~= player or not Rules.canExit(state, at, speedKmh(car)) then
		return
	end
	local doorOpen = Rules.doorOpenness(state, at) >= 0.5
	CarState.write(car.model, {
		entry = "Exit",
		entryAt = at,
		entryDoorOpen = doorOpen,
		door = "Closed",
		doorAt = at,
		engine = "Off",
		engineAt = at,
	})
	task.delay(Rules.length(Rules.steps("Exit", doorOpen)), finishExit, car, player, at)
end

-- Anyone leaving the seat other than through a finished exit (a reset, a death, a player
-- leaving) cuts the sequence short: the door settles, the engine stops, the body regains its size.
local function onOccupant(car: Car)
	local occupant = car.seat.Occupant
	if occupant then
		car.occupant = occupant.Parent :: Model?
		return
	end
	local previous = car.occupant
	car.occupant = nil
	local state, at = CarState.read(car.model), now()
	if state.entry ~= "None" then
		CarState.write(car.model, {
			entry = "None",
			entryAt = at,
			entryDoorOpen = false,
			door = Rules.nearestRest(state, at),
			doorAt = at,
			engine = "Off",
			engineAt = at,
		})
	end
	local player = if previous then Players:GetPlayerFromCharacter(previous) else nil
	if player and resizes[player] == nil then
		resize(player, 1)
	end
end

local HANDLERS: { [Rules.Action]: (Car, Player) -> () } = {
	Enter = enter,
	Exit = exit,
	Door = moveDoor,
	Start = start,
}

local function parseRequest(payload: unknown): Request?
	if typeof(payload) ~= "table" then
		return nil
	end
	local fields = payload :: { [unknown]: unknown }
	local model = fields.car
	local action: Rules.Action? = Rules.parseAction(fields.action)
	if action == nil or typeof(model) ~= "Instance" or not model:IsA("Model") or cars[model] == nil then
		return nil
	end
	return { car = model, action = action }
end

local function updateSizes(at: number)
	for player, job in resizes do
		if job.character.Parent == nil or player.Character ~= job.character then
			resizes[player] = nil
			continue
		end
		local done = at - job.at >= Config.SCALE_SECONDS
		local scale = if done then job.to else Rules.scale(job.from, job.to, at - job.at)
		if
			math.abs(job.character:GetScale() - scale) > SCALE_EPSILON
			or (done and job.character:GetScale() ~= scale)
		then
			job.character:ScaleTo(scale)
		end
		if done then
			resizes[player] = nil
		end
	end
end

local function updateCar(car: Car, at: number)
	local reservation = car.reservation
	if reservation and (at - reservation.at > Config.RESERVE_SECONDS or reservation.player.Parent == nil) then
		release(car)
		local _, humanoid = body(reservation.player)
		if reservation.intent == "Enter" and humanoid and humanoid.SeatPart == nil then
			resize(reservation.player, 1)
		end
	end
	local state = CarState.read(car.model)
	local free = car.reservation == nil
	car.enterPrompt.Enabled = free and Rules.canEnter(state, at)
	car.doorPrompt.Enabled = free and Rules.canMoveDoor(state, at, speedKmh(car), false)
	local text = if Rules.doorOpenness(state, at) >= 0.5 then "Close door" else "Open door"
	if car.doorPrompt.ActionText ~= text then
		car.doorPrompt.ActionText = text
	end
end

local function doorPrompt(model: Model, beside: ProximityPrompt): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Door"
	prompt.ActionText = "Open door"
	prompt.ObjectText = model.Name
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = Config.PROMPT_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = beside.Parent
	return prompt
end

local function setup(model: Instance)
	if not model:IsA("Model") or cars[model] ~= nil then
		return
	end
	local name = model:GetAttribute("Car")
	local entry = if typeof(name) == "string" then Catalog[name] else nil
	local rig = if entry then CarRig.find(model, entry.model) else nil
	if rig == nil then
		log.warn(`{model:GetFullName()} is tagged but not rigged; no entry for it`)
		return
	end
	local enterPrompt = rig.prompt
	enterPrompt.Name = "Enter"
	enterPrompt.ActionText = "Get in"
	enterPrompt.MaxActivationDistance = Config.PROMPT_DISTANCE
	local car: Car = {
		model = model,
		seat = rig.seat,
		chassis = rig.chassis,
		enterPrompt = enterPrompt,
		doorPrompt = doorPrompt(model, enterPrompt),
		reservation = nil,
		occupant = nil,
	}
	CarState.write(model, REST)
	model:SetAttribute(ATTRIBUTE.RESERVED_BY, 0)
	model:SetAttribute(ATTRIBUTE.RESERVED_AT, 0)
	cars[model] = car
	car.enterPrompt.Triggered:Connect(function(player: Player)
		onPrompt(car, player, "Enter")
	end)
	car.doorPrompt.Triggered:Connect(function(player: Player)
		onPrompt(car, player, "Door")
	end)
	car.seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		onOccupant(car)
	end)
end

local Service = {}

function Service.start()
	Net.onServerEvent(
		Remotes.CAR_ACTION,
		ACTION_LIMIT,
		parseRequest,
		function(player: Player, request: Request)
			HANDLERS[request.action](cars[request.car], player)
		end
	)
	for _, model in CollectionService:GetTagged(CarRig.TAG) do
		setup(model)
	end
	CollectionService:GetInstanceAddedSignal(CarRig.TAG):Connect(setup)
	RunService.Heartbeat:Connect(function()
		local at = now()
		updateSizes(at)
		for _, car in cars do
			updateCar(car, at)
		end
	end)
end

return Service
