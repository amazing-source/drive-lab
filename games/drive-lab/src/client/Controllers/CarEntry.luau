--!strict
--[[
	The local player's side of getting in and out, the driver's door and the start. A car's
	prompt walks the body to the door mark (Controllers/EntryWalk) and asks the server, which
	checks the body against its own view; the clips then play in step with the car's state
	(Rules/CarEntry), the clock every client also turns the door from, so the door stays under the
	hand. Getting in asks as the final placing begins, so the round trip runs alongside it. A
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
local Net = require(ReplicatedStorage.Kit.Net)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Rules = require(ReplicatedStorage.Shared.Rules.CarEntry)

local ClipPlayer = require(script.Parent.Parent.Rig.ClipPlayer)
local EntryWalk = require(script.Parent.EntryWalk)

type Intent = "Enter" | "Door"
type Body = { character: Model, humanoid: Humanoid, root: BasePart, clips: ClipPlayer.ClipPlayer }
-- A request from outside the server has not answered yet, and the server time it was sent.
type Pending = { car: Model, intent: Intent, askedAt: number }

-- Consecutive clips of a sequence meet on the same pose; a rest pose eases in.
local CHAIN_FADE = 0
local POSE_FADE = 0.15
local SIT, IDLE = Movement.ANIMATIONS.sit.id, Movement.ANIMATIONS.idle.id
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

-- Every clip a body may play here, loaded when it spawns.
local PRELOAD: { string } = { Config.SEATED_POSE, IDLE }
for _, clip in Config.CLIPS do
	table.insert(PRELOAD, clip.seated)
	if clip.standing then
		table.insert(PRELOAD, clip.standing)
	end
end

local localPlayer = Players.LocalPlayer
local body: Body? = nil
-- Walking to a car's door; a movement key pressed meanwhile gives the walk up.
local walking = false
local walkedAway = false
local pending: Pending? = nil
local exitHeld: { key: Enum.KeyCode, since: number }? = nil
-- The car the body was getting out of on its last frame in the seat; then, for a moment after it
-- stood up, the car and the size the body was placed at.
local exiting: Model? = nil
local standingUp = false
local placedOut: { car: Model, scale: number, untilClock: number }? = nil
-- Whether this frame's clips were chosen with the body in a seat, and a seat weld held off for
-- the rest of a frame in which it arrived too late for them.
local posedSeated = false
local heldWeld: Weld? = nil
-- Seconds between the end of the placing on the mark and the start asked of the server: the
-- seat must not cut the placing short.
local START_MARGIN = 0.05

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

-- The car whose seat holds the body, by the seat weld itself: the weld can reach this client a
-- frame before or after Humanoid.SeatPart (measured: a body drawn 5 studs off for a frame), and
-- the clips must follow where the root really is.
local function weldedCar(): Model?
	local current = body
	if current == nil then
		return nil
	end
	local seat: Instance? = current.humanoid.SeatPart
	local request = pending
	if seat == nil and request and request.intent == "Enter" then
		seat = request.car:FindFirstChild("DriverSeat")
	end
	local weld = seat and seat:FindFirstChild("SeatWeld")
	if weld == nil or not weld:IsA("Weld") or weld.Part1 ~= current.root then
		return nil
	end
	local model = (seat :: Instance).Parent
	return if model and model:IsA("Model") and model:HasTag(CarRig.TAG) then model else nil
end

local function reservedForMe(car: Model): boolean
	return car:GetAttribute(Config.ATTRIBUTES.RESERVED_BY) == localPlayer.UserId
end

-- On foot, HeadLook turns the head toward the camera, and the turned head's box reaches past the
-- car's collision box from the door mark (measured: 0.53 studs inside it, pushing the body 0.48
-- off the mark; the torso clears it by 0.16). So the head stops colliding, on this client, from
-- the walk to the door until the body is clear of the car again.
local function headClear(current: Body, clear: boolean)
	local head = current.character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		head.CanCollide = not clear
	end
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

-- Walks to the mark and asks, if the car's state allows it. False when it gave up.
local function approach(current: Body, car: Model, intent: Intent): boolean
	local seat = car:FindFirstChild("DriverSeat")
	local hull = car:FindFirstChild("Hull")
	if current.humanoid.SeatPart ~= nil or seat == nil or not seat:IsA("BasePart") then
		return false
	end
	local state, at = CarState.read(car), now()
	if
		not (if intent == "Enter" then Rules.canEnter(state, at) else Rules.canMoveDoor(state, at, 0, false))
	then
		return false
	end
	local outcome =
		EntryWalk.toMark(walker(current, true), seat, if hull and hull:IsA("BasePart") then hull else nil)
	if outcome ~= "Arrived" or not awaitReservation(current, car) then
		return false
	end
	local mark = DoorMark.frame(seat)
	local seconds = EntryWalk.placeSeconds(current.root, mark)
	pending = { car = car, intent = intent, askedAt = now() }
	send(car, intent, if intent == "Enter" then now() + seconds + START_MARGIN else nil)
	EntryWalk.place(walker(current, false), mark, seconds)
	return true
end

local function onPrompt(car: Model, intent: Intent)
	local current = body
	if walking or pending ~= nil or current == nil then
		return
	end
	walking, walkedAway = true, false
	headClear(current, true)
	local asked = approach(current, car, intent)
	walking = false
	if asked or body ~= current then
		return
	end
	EntryWalk.release(walker(current, false))
	headClear(current, false)
	if reservedForMe(car) then
		send(car, "Cancel")
	end
end

local function clipLength(name: Config.ClipName): number
	return Config.CLIPS[name].duration
end

local function clipId(name: Config.ClipName, standing: boolean): string
	local clip = Config.CLIPS[name]
	return if standing then clip.standing or "" else clip.seated
end

local function seatedClips(current: Body, car: Model, at: number)
	local state = CarState.read(car)
	local phase = Rules.phase(state, at)
	if phase == "Entering" or phase == "Exiting" then
		local step, into = Rules.stepAt(Rules.steps(state.entry, state.entryDoorOpen), at - state.entryAt)
		if step then
			ClipPlayer.set(current.clips, clipId(step.clip, false), into, CHAIN_FADE, step.duration)
		end
		return
	end
	local inside: Config.ClipName? = INSIDE[state.door]
	if inside ~= nil and at - state.doorAt < clipLength(inside) then
		ClipPlayer.set(current.clips, clipId(inside, false), at - state.doorAt, CHAIN_FADE)
		return
	end
	ClipPlayer.set(current.clips, Config.SEATED_POSE, nil, POSE_FADE)
end

-- Ends a request from outside: the body is free again; standing outside, its head collides again.
local function finishPending(current: Body)
	pending = nil
	EntryWalk.release(walker(current, false))
	if current.humanoid.SeatPart == nil then
		headClear(current, false)
	end
end

-- Getting out ends on a standing frame, and Locomotion's idle only starts after this frame's
-- animation (it runs on Heartbeat): Roblox's sit, under the exit clip all along, would show for
-- a frame and blend out (measured: a leg 2.5 studs off). A copy of the idle holds the body for
-- that frame, then fades out as Locomotion's own fades in.
-- R6 standing: the root's centre three studs above the feet, times the scale.
local ROOT_HEIGHT = 3
-- Seconds after getting out during which a late size change re-plants the feet.
local SETTLE_OUT = 0.6

-- Getting out ends with the server letting go of the body, but this client owns its physics, and
-- the root it finds is where the seat weld left it, inside the car (measured: 1.8 studs from the
-- seat, then pushed out 3.7 studs); the server's own placement does not take. So the client puts
-- it standing where the exit's last clip frame shows it.
local function placeOut(current: Body, car: Model)
	local seat = car:FindFirstChild("DriverSeat")
	if seat == nil or not seat:IsA("BasePart") then
		return
	end
	local spot = DoorMark.exitFrame(seat)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { car, current.character }
	local hit = Workspace:Raycast(spot.Position + Vector3.new(0, 4, 0), Vector3.new(0, -30, 0), params)
	local scale = current.character:GetScale()
	local height = if hit then hit.Position.Y + ROOT_HEIGHT * scale else spot.Position.Y
	current.root.CFrame = spot.Rotation + Vector3.new(spot.Position.X, height, spot.Position.Z)
	current.root.AssemblyLinearVelocity = Vector3.zero
	current.root.AssemblyAngularVelocity = Vector3.zero
	current.humanoid:MoveTo(current.root.Position)
	headClear(current, false)
	placedOut = { car = car, scale = scale, untilClock = os.clock() + SETTLE_OUT }
end

local function standUp(current: Body)
	for _, track in current.clips.animator:GetPlayingAnimationTracks() do
		local animation = track.Animation
		if animation and animation.AnimationId == SIT then
			track:Stop(0)
		end
	end
	ClipPlayer.set(current.clips, IDLE, nil, 0)
	standingUp = true
end

-- A request the server let go of without acting on it, or never answered, was refused.
local function refused(request: Pending, state: Rules.State, at: number): boolean
	if at - request.askedAt > Config.ARRIVAL_WAIT + Config.REFUSED_SECONDS then
		return true
	end
	return not reservedForMe(request.car) and state.entry ~= "Enter"
end

-- Off the seat a held exit clip ends at once: the server put the root where it showed the body.
local function clearStanding(current: Body)
	ClipPlayer.set(current.clips, nil, nil, if standingUp then Movement.FADE else 0)
	standingUp = false
end

local function standingClips(current: Body, at: number)
	local request = pending
	if request == nil then
		clearStanding(current)
		return
	end
	local state = CarState.read(request.car)
	if request.intent == "Enter" then
		if refused(request, state, at) then
			finishPending(current)
		end
		clearStanding(current)
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
		finishPending(current)
	end
	clearStanding(current)
end

local function update()
	local weld = heldWeld
	if weld then
		heldWeld = nil
		weld.Enabled = true
	end
	local current = body
	if current == nil then
		return
	end
	local at = now()
	local car = weldedCar()
	posedSeated = car ~= nil
	if car then
		-- Kept once set: the car's state can read None a frame before its seat lets go.
		local entry = CarState.read(car).entry
		if entry == "Exit" then
			exiting = car
		elseif entry == "Enter" then
			exiting = nil
		end
		seatedClips(current, car, at)
		local held = exitHeld
		if held and Rules.exitHeld(os.clock() - held.since) then
			exitHeld = nil
			send(car, "Exit")
		end
	else
		exitHeld = nil
		local leaving = exiting
		if leaving then
			exiting = nil
			placeOut(current, leaving)
			standUp(current)
			return
		end
		local out = placedOut
		if out and os.clock() < out.untilClock and current.character:GetScale() ~= out.scale then
			placeOut(current, out.car)
		elseif out and os.clock() >= out.untilClock then
			placedOut = nil
		end
		standingClips(current, at)
	end
end

-- A seat weld that reached this client after this frame's clips were chosen would move the root
-- into the seat with the body still posed standing: one frame of the body drawn in the car
-- (measured: 5 studs). It is held off for the rest of that frame; the next frame's clip and the
-- weld then agree.
local function holdLateWeld()
	local current = body
	if current == nil or posedSeated then
		return
	end
	local request = pending
	local seat: Instance? = current.humanoid.SeatPart
		or (if request and request.intent == "Enter" then request.car:FindFirstChild("DriverSeat") else nil)
	local weld = seat and seat:FindFirstChild("SeatWeld")
	if weld and weld:IsA("Weld") and weld.Part1 == current.root and weld.Enabled then
		weld.Enabled = false
		heldWeld = weld
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
	body, walking, pending, exiting, standingUp, placedOut = nil, false, nil, nil, false, nil
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart
	local animator = humanoid:WaitForChild("Animator") :: Animator
	if character.Parent == nil or localPlayer.Character ~= character then
		return
	end
	local clips = ClipPlayer.new(animator)
	ClipPlayer.preload(clips, PRELOAD, { [Config.SEATED_POSE] = true, [IDLE] = true })
	body = { character = character, humanoid = humanoid, root = root, clips = clips }
	humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
		local inCar = seatedCar() ~= nil
		-- Jumping would leave the seat; Space is the handbrake and leaving is the exit key's.
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, not inCar)
		local current = body
		if inCar and current and current.humanoid == humanoid then
			finishPending(current)
		end
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
	RunService.PreSimulation:Connect(holdLateWeld)
	if localPlayer.Character then
		task.spawn(onCharacter, localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(onCharacter)
end

return Controller
