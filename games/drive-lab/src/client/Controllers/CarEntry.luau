--!strict
--[[
	The local player's side of getting in and out, the driver's door and the start. A car's
	prompt walks the body to the door mark (Controllers/EntryWalk) and asks the server, which
	checks the body against its own view; the clips then play in step with the car's state
	(Rules/CarEntry), the clock every client also turns the door from, so the door stays under the
	hand, and Controllers/SeatHandOver keeps the body where it really is as it changes hands with
	the seat. Getting in asks as the final placing begins, so the round trip runs alongside it. A
	movement key during the walk gives it up, and so does a refusal: the body is left standing,
	free. Seated: the door key moves the door, the start key starts the engine, holding the exit
	key gets out (Config/Controls). Clips played on one's own character replicate to the others.
]]
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CarRig = require(ReplicatedStorage.Shared.Car.CarRig)
local CarState = require(ReplicatedStorage.Shared.Car.CarState)
local Config = require(ReplicatedStorage.Shared.Config.CarEntry)
local Controls = require(ReplicatedStorage.Shared.Config.Controls)
local DoorMark = require(ReplicatedStorage.Shared.Car.DoorMark)
local Movement = require(ReplicatedStorage.Shared.Config.Movement)
local Log = require(ReplicatedStorage.Kit.Log)
local Net = require(ReplicatedStorage.Kit.Net)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Rules = require(ReplicatedStorage.Shared.Rules.CarEntry)

local ClipPlayer = require(script.Parent.Parent.Rig.ClipPlayer)
local EntryWalk = require(script.Parent.EntryWalk)
local SeatHandOver = require(script.Parent.SeatHandOver)

type Intent = "Enter" | "Door"
type Body = SeatHandOver.Body
-- A request from outside the server has not answered yet, and the server time it was sent.
type Pending = { car: Model, intent: Intent, askedAt: number }

-- Consecutive clips of a sequence meet on the same pose; a rest pose eases in.
local CHAIN_FADE = 0
local POSE_FADE = 0.15
-- Seconds between the end of the placing on the mark and the start asked of the server: the
-- seat must not cut the placing short.
local START_MARGIN = 0.05
-- On foot, the keys that move the body (Roblox's default controls, which cannot be switched off
-- while the walk to the door runs): pressed then, they give the walk up. The left stick does too.
local WALK_AWAY_KEYS = {
	Enum.KeyCode.W,
	Enum.KeyCode.A,
	Enum.KeyCode.S,
	Enum.KeyCode.D,
	Enum.KeyCode.Up,
	Enum.KeyCode.Down,
	Enum.KeyCode.Left,
	Enum.KeyCode.Right,
	Enum.KeyCode.Space,
	Enum.KeyCode.ButtonA,
}

-- The door's own motions that play a clip on the body, from inside and from outside.
local INSIDE: { [string]: Config.ClipName } = { InsideOpen = "InsideOpen", InsideClose = "InsideClose" }

-- Every clip a body may play here, loaded when it spawns: a clip played before its asset has
-- loaded has no pose for its first frames.
local PRELOAD: { string } = { Config.SEATED_POSE, Movement.ANIMATIONS.idle.id }
for _, clip in Config.CLIPS do
	table.insert(PRELOAD, clip.seated)
	if clip.standing then
		table.insert(PRELOAD, clip.standing)
	end
end

local log = Log.scope("CarEntry")
local localPlayer = Players.LocalPlayer
local body: Body? = nil
-- Walking to a car's door; a movement key pressed meanwhile gives the walk up.
local walking = false
local walkedAway = false
local pending: Pending? = nil
local exitHeld: { key: Enum.KeyCode, since: number }? = nil
-- The car the body was getting out of on its last frame in the seat.
local exiting: Model? = nil
-- Whether this frame's clips were chosen with the body in a seat.
local posedSeated = false

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function send(car: Model, action: Rules.Action, at: number?)
	Net.send(Remotes.CAR_ACTION, { car = car, action = action, at = at })
end

local function seatedCar(): Model?
	local current = body
	local seat = current and current.humanoid.SeatPart
	local model = seat and seat.Parent
	return if model and model:IsA("Model") and model:HasTag(CarRig.TAG) then model else nil
end

-- The car the body is being seated in, while an entry waits for the server.
local function entering(): Model?
	local request = pending
	return if request and request.intent == "Enter" then request.car else nil
end

local function reservedForMe(car: Model): boolean
	return car:GetAttribute(Config.ATTRIBUTES.RESERVED_BY) == localPlayer.UserId
end

-- `stoppable`: a movement key ends it too.
local function walker(current: Body, stoppable: boolean): EntryWalk.Walk
	return {
		humanoid = current.humanoid,
		root = current.root,
		going = function(): boolean
			return body == current and not (stoppable and walkedAway)
		end,
	}
end

-- The server reserves the car for the player who pressed; that arrives a round trip after the
-- press, possibly after a short walk has ended.
local function awaitReservation(current: Body, car: Model): boolean
	local deadline = os.clock() + Config.REFUSED_SECONDS
	while body == current and not walkedAway and os.clock() < deadline do
		if reservedForMe(car) then
			return true
		end
		task.wait()
	end
	return false
end

-- Walks to the mark and asks, if the car's state allows it. Nil once asked, else why it gave up.
local function approach(current: Body, car: Model, intent: Intent): string?
	local seat = car:FindFirstChild("DriverSeat")
	local hull = car:FindFirstChild("Hull")
	if current.humanoid.SeatPart ~= nil then
		return "already seated"
	elseif seat == nil or not seat:IsA("BasePart") then
		return "no driver's seat"
	end
	local state, at = CarState.read(car), now()
	if
		not (if intent == "Enter" then Rules.canEnter(state, at) else Rules.canMoveDoor(state, at, 0, false))
	then
		return `the car's state does not allow it (entry {state.entry}, door {state.door})`
	end
	local outcome =
		EntryWalk.toMark(walker(current, true), seat, if hull and hull:IsA("BasePart") then hull else nil)
	if outcome ~= "Arrived" then
		return `the walk {string.lower(outcome)}`
	elseif not awaitReservation(current, car) then
		return "the server held the car for no one"
	end
	local mark = DoorMark.frame(seat)
	local seconds = EntryWalk.placeSeconds(current.root, mark)
	pending = { car = car, intent = intent, askedAt = now() }
	send(car, intent, now() + seconds + START_MARGIN)
	EntryWalk.place(walker(current, false), mark, seconds)
	return nil
end

local function onPrompt(car: Model, intent: Intent)
	local current = body
	if walking or pending ~= nil or current == nil then
		return
	end
	walking, walkedAway = true, false
	local gaveUp = approach(current, car, intent)
	walking = false
	if gaveUp == nil or body ~= current then
		return
	end
	log.debug(`{intent} at {car:GetFullName()} given up: {gaveUp}`)
	EntryWalk.release(walker(current, false), false)
	if reservedForMe(car) then
		send(car, "Cancel")
	end
end

local function clipId(name: Config.ClipName, standing: boolean): string
	local clip = Config.CLIPS[name]
	return if standing then clip.standing or "" else clip.seated
end

local function seatedClips(current: Body, car: Model, at: number)
	local state = CarState.read(car)
	if exiting == car and state.entry == "None" then
		-- The exit is over but the seat has not let go yet: the last exit frame stays held, or a
		-- rest pose fading in would drag the body back toward the seat as it is placed outside.
		return
	end
	local phase = Rules.phase(state, at)
	if phase == "Entering" or phase == "Exiting" then
		local step, into = Rules.stepAt(Rules.steps(state.entry, state.entryDoorOpen), at - state.entryAt)
		if step then
			ClipPlayer.set(current.clips, clipId(step.clip, false), into, CHAIN_FADE, step.duration)
		end
		return
	end
	local inside: Config.ClipName? = INSIDE[state.door]
	if inside ~= nil and at - state.doorAt < Config.CLIPS[inside].duration then
		ClipPlayer.set(current.clips, clipId(inside, false), at - state.doorAt, CHAIN_FADE)
		return
	end
	ClipPlayer.set(current.clips, Config.SEATED_POSE, nil, POSE_FADE)
end

-- Ends a request: the body is free again. `seated`: the seat's weld holds it.
local function finishPending(current: Body, seated: boolean)
	pending = nil
	EntryWalk.release(walker(current, false), seated)
end

-- A request the server let go of without acting on it, or never answered, was refused.
local function refused(request: Pending, state: Rules.State, at: number): boolean
	if at - request.askedAt > Config.ARRIVAL_WAIT + Config.REFUSED_SECONDS then
		return true
	end
	return not reservedForMe(request.car) and state.entry ~= "Enter"
end

local function standingClips(current: Body, at: number)
	local request = pending
	if request == nil then
		SeatHandOver.clearStanding(current)
		return
	end
	local state = CarState.read(request.car)
	if request.intent == "Enter" then
		if refused(request, state, at) then
			finishPending(current, false)
		end
		SeatHandOver.clearStanding(current)
		return
	end
	local door = Rules.outsideRequest(state, at, request.askedAt)
	if door.clip then
		-- The standing clip leans the body into the car's collision box to reach the door; held
		-- at the mark, physics cannot push it away.
		current.root.Anchored = true
		ClipPlayer.set(current.clips, clipId(door.clip, true), door.into, POSE_FADE)
		return
	end
	if door.finished or refused(request, state, at) then
		finishPending(current, false)
	end
	SeatHandOver.clearStanding(current)
end

local function update()
	SeatHandOver.beginFrame()
	local current = body
	if current == nil then
		return
	end
	local at = now()
	local car = SeatHandOver.seatedIn(current, entering())
	posedSeated = car ~= nil
	-- After the placing, getting in: on the mark until the seat's weld arrives.
	local awaitingWeld = not walking and SeatHandOver.holdForSeat(current, entering())
	SeatHandOver.collide(current, SeatHandOver.collision(current, car, pending ~= nil or walking))
	if car and pending then
		-- The seat holds the body: the entry is the server's now.
		finishPending(current, true)
	end
	if car then
		-- Kept once set: the car's state can read None a frame before its seat lets go.
		local entry = CarState.read(car).entry
		if entry == "Exit" then
			exiting = car
		elseif entry == "Enter" then
			exiting = nil
			SeatHandOver.seatedSize(current)
		end
		seatedClips(current, car, at)
		local held = exitHeld
		if held and Rules.exitHeld(os.clock() - held.since) then
			exitHeld = nil
			send(car, "Exit")
		end
		return
	end
	exitHeld = nil
	local leaving = exiting
	if leaving then
		exiting = nil
		SeatHandOver.standUp(current, leaving)
		return
	end
	if not awaitingWeld then
		SeatHandOver.keepStanding(current)
	end
	standingClips(current, at)
end

local function afterAnimation()
	local current = body
	if current then
		SeatHandOver.guardFrame(current, posedSeated, entering(), exiting)
	end
end

local function onInputBegan(input: InputObject)
	if UserInputService:GetFocusedTextBox() ~= nil then
		return
	end
	local key = input.KeyCode
	if walking and table.find(WALK_AWAY_KEYS, key) then
		walkedAway = true
		return
	end
	local car = seatedCar()
	if car == nil then
		return
	end
	if table.find(Controls.DOOR, key) then
		send(car, "Door")
	elseif table.find(Controls.START_ENGINE, key) then
		send(car, "Start")
	elseif table.find(Controls.EXIT, key) then
		exitHeld = { key = key, since = os.clock() }
	end
end

local function onInputChanged(input: InputObject)
	if
		walking
		and input.KeyCode == Enum.KeyCode.Thumbstick1
		and input.Position.Magnitude > Controls.STICK_DEADZONE
	then
		walkedAway = true
	end
end

local function onCharacter(character: Model)
	if body then
		ClipPlayer.destroy(body.clips)
	end
	body, walking, pending, exiting = nil, false, nil, nil
	SeatHandOver.reset()
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart
	local animator = humanoid:WaitForChild("Animator") :: Animator
	if character.Parent == nil or localPlayer.Character ~= character then
		return
	end
	local clips = ClipPlayer.new(animator)
	ClipPlayer.preload(clips, PRELOAD, { [Config.SEATED_POSE] = true, [Movement.ANIMATIONS.idle.id] = true })
	body = { character = character, humanoid = humanoid, root = root, clips = clips }
	humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
		local inCar = seatedCar() ~= nil
		-- Jumping would leave the seat; Space is the handbrake and leaving is the exit key's.
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, not inCar)
	end)
end

local Controller = {}

function Controller.start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		local model = prompt:FindFirstAncestorOfClass("Model")
		if player ~= localPlayer or model == nil or not model:HasTag(CarRig.TAG) then
			return
		end
		if prompt.Name == "Enter" or prompt.Name == "Door" then
			task.spawn(onPrompt, model, prompt.Name :: Intent)
		end
	end)
	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputChanged:Connect(onInputChanged)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local held = exitHeld
		if held and input.KeyCode == held.key then
			exitHeld = nil
		end
	end)
	RunService.PreAnimation:Connect(update)
	RunService.PreSimulation:Connect(afterAnimation)
	if localPlayer.Character then
		task.spawn(onCharacter, localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(onCharacter)
end

return Controller
