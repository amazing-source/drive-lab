--!strict
--[[
	Getting in and out of cars, their drivers' doors and starting them, on the server: the only
	writer of each car's state (Car/CarState), which every client turns into the same body
	animation, door angle and start-up (Rules/CarEntry). A prompt holds the seat or the door for
	one player while their client walks them to the door mark; the client then asks, and the
	request is checked against the rules and against where this server sees the character, which
	lags the client's own view by the network: a request from outside waits for that view to reach
	the mark. The body changes size only where this server knows where it is: down in the step
	that seats it, back up in the step that puts it outside after getting out. Scaling a body the
	client is walking would move it back to where this server last saw it.
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CarRig = require(ReplicatedStorage.Shared.Car.CarRig)
local CarState = require(ReplicatedStorage.Shared.Car.CarState)
local Catalog = require(ReplicatedStorage.Shared.Config.Cars.Catalog)
local Contract = require(ReplicatedStorage.Shared.Config.Cars.Contract)
local Config = require(ReplicatedStorage.Shared.Config.CarEntry)
local DoorMark = require(ReplicatedStorage.Shared.Car.DoorMark)
local Log = require(ReplicatedStorage.Kit.Log)
local Net = require(ReplicatedStorage.Kit.Net)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Rules = require(ReplicatedStorage.Shared.Rules.CarEntry)
local Units = require(ReplicatedStorage.Shared.Units)

local CarBody = require(script.Parent.Parent.CarBody)

type Intent = "Enter" | "Door"
-- `character` is the body that pressed: a reservation ends with it. `asked` once its request
-- has arrived: a repeat of it is ignored.
type Reservation = { player: Player, character: Model, intent: Intent, at: number, asked: boolean }
type Car = {
	model: Model,
	entry: Catalog.Entry,
	seat: Seat,
	chassis: BasePart,
	enterPrompt: ProximityPrompt,
	doorPrompt: ProximityPrompt,
	reservation: Reservation?,
	-- The character in the seat, remembered so it can be resized once it has left.
	occupant: Model?,
}
-- `at` is the server time the client asked an entry to start; nil for the other actions.
type Request = { car: Model, action: Rules.Action, at: number? }

local ATTRIBUTE = Config.ATTRIBUTES
local ACTION_LIMIT = { perSecond = 4, burst = 6 }
local PROMPT_LIMIT = { perSecond = 2, burst = 3 }
-- Studs past the prompt distance allowed for a character still moving when it pressed.
local DISTANCE_SLACK = 2
-- Seconds past a standing door clip's end its body still goes through the car's box here: this
-- server poses the body from its client's animation, behind it by the network.
local CLIP_THROUGH_MARGIN = 0.5
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

local function now(): number
	return Workspace:GetServerTimeNow()
end

-- The delay a sequence's start allows for its state to reach `player`: its measured round trip,
-- twice the one-way delay (for jitter and a resent packet), and a margin.
local function oneWay(player: Player): number
	return player:GetNetworkPing() + Config.LATENCY_MARGIN
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

local function setScale(player: Player, to: number)
	local character, _, root = body(player)
	if character and root then
		CarBody.scaleAboutRoot(character, root, to)
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
	return DoorMark.distance(car.entry.door, car.seat, root.Position) <= Config.MARK_TOLERANCE
end

local function release(car: Car)
	car.reservation = nil
	car.model:SetAttribute(ATTRIBUTE.RESERVED_BY, 0)
end

local function reservedFor(car: Car, player: Player, intent: Intent): boolean
	local reservation = car.reservation
	return reservation ~= nil
		and reservation.player == player
		and reservation.intent == intent
		and reservation.character == player.Character
end

-- Claims the reservation for its one request; false if it is not this player's or was claimed.
local function claim(car: Car, player: Player, intent: Intent): boolean
	local reservation = car.reservation
	if reservation == nil or reservation.asked or not reservedFor(car, player, intent) then
		return false
	end
	reservation.asked = true
	return true
end

-- Waits, at most ARRIVAL_WAIT, for this server's view of the player to reach the mark while the
-- reservation holds; the client stops there before this server can see it.
local function awaitArrival(car: Car, player: Player, intent: Intent): boolean
	local deadline = now() + Config.ARRIVAL_WAIT
	while reservedFor(car, player, intent) do
		local _, _, root = body(player)
		if root == nil then
			return false
		end
		if atMark(car, root) then
			return true
		end
		if now() > deadline then
			return false
		end
		RunService.Heartbeat:Wait()
	end
	return false
end

-- A sequence that ends other than as authored (the occupant left, died or never sat): the door
-- settles at its nearer rest and the engine stops.
local function cutShort(car: Car, at: number)
	local state = CarState.read(car.model)
	CarState.write(car.model, {
		entry = "None",
		entryAt = at,
		entryDoorOpen = false,
		door = Rules.nearestRest(car.entry, state, at),
		doorAt = at,
		engine = "Off",
		engineAt = at,
	})
end

local function onPrompt(car: Car, player: Player, intent: Intent)
	if not Net.allow(player, "CarPrompt", PROMPT_LIMIT) or car.reservation ~= nil then
		return
	end
	local character, humanoid, root = body(player)
	if character == nil or humanoid == nil or root == nil or humanoid.SeatPart ~= nil then
		return
	end
	if
		DoorMark.distance(car.entry.door, car.seat, root.Position)
		> Config.PROMPT_DISTANCE + DISTANCE_SLACK
	then
		return
	end
	local state, at = CarState.read(car.model), now()
	local allowed = if intent == "Enter"
		then Rules.canEnter(car.entry, state, at)
		else Rules.canMoveDoor(car.entry, state, at, speedKmh(car), false)
	if not allowed then
		return
	end
	car.reservation = { player = player, character = character, intent = intent, at = at, asked = false }
	car.model:SetAttribute(ATTRIBUTE.RESERVED_AT, at)
	car.model:SetAttribute(ATTRIBUTE.RESERVED_BY, player.UserId)
end

-- At the entry's start: the body takes the seated size and the root goes to the seat, where the
-- first clip's frame shows it standing on the mark, as the client placed it. Anything that
-- changed since the request cuts the entry short.
local function seat(car: Car, player: Player, startedAt: number)
	local state = CarState.read(car.model)
	if state.entry ~= "Enter" or state.entryAt ~= startedAt then
		return
	end
	local character, humanoid, root = body(player)
	if
		character == nil
		or humanoid == nil
		or root == nil
		or humanoid.SeatPart ~= nil
		or car.seat.Occupant ~= nil
	then
		cutShort(car, now())
		return
	end
	-- The client has stopped the body on the mark; resized there in the same step as the weld.
	CarBody.resizeOn(
		car.model,
		character,
		root,
		DoorMark.frame(car.entry.door, car.seat),
		Contract.driverScale(car.entry)
	)
	car.seat:Sit(humanoid)
end

local function enter(car: Car, player: Player, request: Request)
	if not claim(car, player, "Enter") then
		return
	end
	local arrived = awaitArrival(car, player, "Enter")
	local _, humanoid = body(player)
	local state, at = CarState.read(car.model), now()
	if not arrived or humanoid == nil or not reservedFor(car, player, "Enter") then
		if reservedFor(car, player, "Enter") then
			release(car)
		end
		return
	end
	release(car)
	if car.seat.Occupant ~= nil or humanoid.SeatPart ~= nil or not Rules.canEnter(car.entry, state, at) then
		return
	end
	local startAt = Rules.entryStart(at, request.at, oneWay(player))
	-- State first, for the whole sequence's timing. The seat goes as early as the client allows,
	-- at the time it asked, when its placing on the mark has ended (sooner, the body never reached
	-- the mark: 0.2 to 0.3 studs off at the hand-over, measured with no network simulation), so
	-- its weld reaches the client before the sequence starts and the first clip holds its first
	-- frame until then. Sent later, it arrived after the start and the client showed the clip
	-- already under way (measured: 0.42 to 0.45 studs in one frame, poor network).
	local seatAt = Rules.entryStart(at, request.at, 0)
	CarState.write(car.model, {
		entry = "Enter",
		entryAt = startAt,
		entryDoorOpen = Rules.doorOpenness(car.entry, state, at) >= 0.5,
		door = "Closed",
		doorAt = startAt,
		engine = "Off",
		engineAt = state.engineAt,
	})
	task.delay(seatAt - at, seat, car, player, startAt)
end

local function moveDoor(car: Car, player: Player, request: Request)
	local inside = driver(car) == player
	if not inside then
		if not claim(car, player, "Door") then
			return
		end
		local arrived = awaitArrival(car, player, "Door")
		if reservedFor(car, player, "Door") then
			release(car)
		end
		if not arrived then
			return
		end
	end
	local state, at = CarState.read(car.model), now()
	if not Rules.canMoveDoor(car.entry, state, at, speedKmh(car), inside) then
		return
	end
	local clip: Config.ClipName = Rules.doorClip(car.entry, state, at, inside)
	-- From where the client can show it from its start (as an entry's start, Rules/CarEntry).
	local startAt = Rules.entryStart(at, request.at, oneWay(player))
	local character = player.Character
	if not inside and character then
		-- The clip leans the body into the car's box to reach the door, and this server, which
		-- moves the parked car, pushed the car away from it (measured: 1.14 studs over OutsideOpen).
		CarBody.passThrough(
			character,
			startAt - at + car.entry.door.clips[clip].duration + CLIP_THROUGH_MARGIN
		)
	end
	car.model:SetAttribute(ATTRIBUTE.DOOR_AT, startAt)
	car.model:SetAttribute(ATTRIBUTE.DOOR, clip)
end

local function start(car: Car, player: Player, _request: Request)
	local state, at = CarState.read(car.model), now()
	if driver(car) == player and Rules.canStart(car.entry, state, at) then
		car.model:SetAttribute(ATTRIBUTE.ENGINE_AT, at)
		car.model:SetAttribute(ATTRIBUTE.ENGINE, "On")
	end
end

-- The player walked away or gave up before asking: their hold on the car ends.
local function cancel(car: Car, player: Player, _request: Request)
	local reservation = car.reservation
	if reservation and reservation.player == player then
		release(car)
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
	local character, humanoid, root = body(player)
	if character == nil or humanoid == nil or root == nil or car.seat.Occupant ~= humanoid then
		return
	end
	CarBody.leaveSeat(car.model, player, character)
	local weld = car.seat:FindFirstChild("SeatWeld")
	if weld then
		weld:Destroy()
	end
	humanoid.Sit = false
	-- The client, which owns the body, puts it standing where the last clip frame shows it
	-- (Controllers/SeatHandOver): a placement from here alone does not take on that client
	-- (measured). It regains its size on that same spot.
	CarBody.resizeOn(car.model, character, root, DoorMark.exitFrame(car.entry.door, car.seat), 1)
end

local function exit(car: Car, player: Player, _request: Request)
	local state, at = CarState.read(car.model), now()
	if driver(car) ~= player or not Rules.canExit(car.entry, state, at, speedKmh(car)) then
		return
	end
	local doorOpen = Rules.doorOpenness(car.entry, state, at) >= 0.5
	-- As an entry's start: where the client shows the exit from its first frame.
	local startAt = Rules.entryStart(at, nil, oneWay(player))
	CarState.write(car.model, {
		entry = "Exit",
		entryAt = startAt,
		entryDoorOpen = doorOpen,
		door = "Closed",
		doorAt = startAt,
		engine = "Off",
		engineAt = at,
	})
	task.delay(
		startAt - at + Rules.length(Rules.steps(car.entry, "Exit", doorOpen)),
		finishExit,
		car,
		player,
		startAt
	)
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
	if previous then
		CarBody.leaveSeat(car.model, Players:GetPlayerFromCharacter(previous), previous)
	end
	local at = now()
	if CarState.read(car.model).entry ~= "None" then
		cutShort(car, at)
	end
	local player = if previous then Players:GetPlayerFromCharacter(previous) else nil
	if player and player.Character == previous then
		setScale(player, 1)
	end
end

local HANDLERS: { [Rules.Action]: (Car, Player, Request) -> () } = {
	Enter = enter,
	Exit = exit,
	Door = moveDoor,
	Start = start,
	Cancel = cancel,
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
	local asked = fields.at
	return { car = model, action = action, at = if typeof(asked) == "number" then asked else nil }
end

local function updateCar(car: Car, at: number)
	local reservation = car.reservation
	if
		reservation
		and (
			at - reservation.at > Config.RESERVE_SECONDS
			or reservation.player.Parent == nil
			or reservation.player.Character ~= reservation.character
			or body(reservation.player) == nil
		)
	then
		release(car)
	end
	local state = CarState.read(car.model)
	local free = car.reservation == nil
	car.enterPrompt.Enabled = free and Rules.canEnter(car.entry, state, at)
	car.doorPrompt.Enabled = free and Rules.canMoveDoor(car.entry, state, at, speedKmh(car), false)
	local text = if Rules.doorOpenness(car.entry, state, at) >= 0.5 then "Close door" else "Open door"
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
	local entry = Catalog.of(model)
	local rig = if entry then CarRig.find(model, entry.model) else nil
	if rig == nil or entry == nil then
		log.warn(`{model:GetFullName()} is tagged but not rigged; no entry for it`)
		return
	end
	local enterPrompt = rig.prompt
	enterPrompt.Name = "Enter"
	enterPrompt.ActionText = "Get in"
	enterPrompt.MaxActivationDistance = Config.PROMPT_DISTANCE
	local car: Car = {
		model = model,
		entry = entry,
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
			HANDLERS[request.action](cars[request.car], player, request)
		end
	)
	for _, model in CollectionService:GetTagged(CarRig.TAG) do
		setup(model)
	end
	CollectionService:GetInstanceAddedSignal(CarRig.TAG):Connect(setup)
	RunService.Heartbeat:Connect(function()
		local at = now()
		for _, car in cars do
			updateCar(car, at)
		end
	end)
end

return Service
