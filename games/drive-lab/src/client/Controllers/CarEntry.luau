--!strict
--[[
	The local player's side of getting in and out, the driver's door and the start. A car's
	prompt walks the body to the door mark, in front of it first when coming from the side so it
	walks in facing the car, then places it exactly on the mark and asks the server; the body's
	clips then play in step with the car's state (Rules/CarEntry), the clock every client also
	turns the door from, so the door stays under the hand. Getting in asks as the placing begins,
	for the moment it ends, so the round trip runs alongside it. Seated: the door key moves the
	door, the start key starts the engine, holding the exit key gets out (Config/Controls). Clips
	played on one's own character replicate to the other players.
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
local Net = require(ReplicatedStorage.Kit.Net)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Rules = require(ReplicatedStorage.Shared.Rules.CarEntry)

local ClipPlayer = require(script.Parent.Parent.Rig.ClipPlayer)

type Intent = "Enter" | "Door"
type Body = { character: Model, humanoid: Humanoid, root: BasePart, clips: ClipPlayer.ClipPlayer }
type Controller = { Enable: (Controller) -> (), Disable: (Controller) -> () }

local APPROACH = Config.APPROACH
-- A walk counts as stopped once the body has moved slower than this (studs a second) for
-- STALL_FRAMES frames in a row, after its first STALL_GRACE seconds.
local STALL_SPEED = 0.5
local STALL_FRAMES = 4
local STALL_GRACE = 0.15
-- Consecutive clips of a sequence meet on the same pose; a rest pose eases in.
local CHAIN_FADE = 0
local POSE_FADE = 0.15

-- The door's own motions that play a clip on the body, from inside and from outside.
local INSIDE: { [string]: Config.ClipName } = { InsideOpen = "InsideOpen", InsideClose = "InsideClose" }

local localPlayer = Players.LocalPlayer
local body: Body? = nil
local busy = false
-- A door the local player is moving from outside, and the server time it asked.
local outsideDoor: { car: Model, askedAt: number }? = nil
-- The server time an entry the local player asked for starts; the body waits on the mark,
-- controls off, until the server seats it.
local entryStartAt: number? = nil
local exitHeld: { key: Enum.KeyCode, since: number }? = nil
local controls: Controller? = nil

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function send(car: Model, action: Rules.Action, at: number?)
	Net.send(Remotes.CAR_ACTION, { car = car, action = action, at = at })
end

local function flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function seatedCar(): Model?
	local current = body
	local seat = current and current.humanoid.SeatPart
	local model = seat and seat.Parent
	return if model and model:IsA("Model") and model:HasTag(CarRig.TAG) then model else nil
end

-- Roblox's default PlayerModule, which is untyped: its controls, to hold the body still.
local function setControls(enabled: boolean)
	if controls == nil then
		local scripts = localPlayer:FindFirstChildOfClass("PlayerScripts")
		local module = scripts and scripts:FindFirstChild("PlayerModule")
		if module == nil or not module:IsA("ModuleScript") then
			return
		end
		controls = ((require :: any)(module) :: any):GetControls()
	end
	local current = controls :: Controller
	if enabled then
		current:Enable()
	else
		current:Disable()
	end
end

local function reservedForMe(car: Model): boolean
	return car:GetAttribute(Config.ATTRIBUTES.RESERVED_BY) == localPlayer.UserId
end

-- Frees a body held on the mark and gives the controls back.
local function letGo(current: Body)
	current.root.Anchored = false
	setControls(true)
end

-- Walks toward `target` until within `within` studs, stopped, refused or out of time. False if
-- the walk was given up (the body changed, or the server never reserved the car).
local function walkTo(current: Body, car: Model, target: Vector3, within: number, started: number): boolean
	local humanoid, root = current.humanoid, current.root
	humanoid:MoveTo(Vector3.new(target.X, root.Position.Y, target.Z))
	local legStarted, slow = os.clock(), 0
	while body == current do
		local elapsed = os.clock() - started
		if elapsed > Config.APPROACH_SECONDS then
			return false
		end
		if elapsed > Config.REFUSED_SECONDS / 3 and not reservedForMe(car) then
			return false
		end
		if flat(target - root.Position).Magnitude <= within then
			return true
		end
		slow = if flat(root.AssemblyLinearVelocity).Magnitude < STALL_SPEED then slow + 1 else 0
		if os.clock() - legStarted > STALL_GRACE and slow >= STALL_FRAMES then
			return true
		end
		task.wait()
	end
	return false
end

-- Moves and turns the held body onto `goal` (its height kept), eased; stops if a seat takes it.
local function settle(current: Body, goal: CFrame, seconds: number)
	local root = current.root
	local from = root.CFrame
	local target = goal.Rotation + Vector3.new(goal.Position.X, from.Position.Y, goal.Position.Z)
	local started = os.clock()
	while body == current and current.humanoid.SeatPart == nil do
		local share = Rules.settleShare(os.clock() - started, seconds)
		root.CFrame = from:Lerp(target, share)
		if share >= 1 then
			return
		end
		task.wait()
	end
end

local function turnBetween(from: CFrame, to: CFrame): number
	local a, b = flat(from.LookVector), flat(to.LookVector)
	if a.Magnitude < 1e-3 or b.Magnitude < 1e-3 then
		return 0
	end
	return math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1))
end

-- Walks to the mark, lined up in front of it when coming from the side, places the body on it
-- exactly, and asks. The controls stay off until the seat or the door's clip gives them back.
local function approach(car: Model, intent: Intent): boolean
	local current = body
	local seat = car:FindFirstChild("DriverSeat")
	if current == nil or current.humanoid.SeatPart ~= nil or seat == nil or not seat:IsA("BasePart") then
		return false
	end
	local started = os.clock()
	local mark = DoorMark.frame(seat)
	if DoorMark.distance(seat, current.root.Position) > APPROACH.arrived then
		if Rules.linesUpFirst(DoorMark.offset(seat, current.root.Position)) then
			local lineUp = (mark * CFrame.new(0, 0, APPROACH.lineUp)).Position
			if not walkTo(current, car, lineUp, APPROACH.reach, started) then
				return false
			end
		end
		if not walkTo(current, car, mark.Position, APPROACH.arrived, started) then
			return false
		end
	end
	local root = current.root
	local distance = DoorMark.distance(seat, root.Position)
	if body ~= current or not reservedForMe(car) or distance > APPROACH.reach then
		return false
	end
	-- Held, physics cannot push the body off the mark: turning there sweeps the torso into the
	-- car's collision box, and the door clips lean it in to reach the door.
	root.Anchored = true
	local seconds = Rules.settleSeconds(distance, turnBetween(root.CFrame, mark))
	if intent == "Enter" then
		entryStartAt = now() + seconds
		send(car, "Enter", entryStartAt)
		settle(current, mark, seconds)
		-- Facing the car on the mark the body clears its collision box. A root still held when
		-- the seat welds it would pull the car onto itself.
		root.Anchored = false
	else
		settle(current, mark, seconds)
		outsideDoor = { car = car, askedAt = now() }
		send(car, "Door")
	end
	-- Ends the walk where the body now stands, so a refused request leaves it standing still.
	current.humanoid:MoveTo(root.Position)
	return true
end

local function onPrompt(car: Model, intent: Intent)
	local current = body
	if busy or current == nil then
		return
	end
	busy = true
	setControls(false)
	local asked = approach(car, intent)
	busy = false
	if not asked and body == current then
		letGo(current)
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

-- Ends a door request from outside: frees the body held at the mark and gives the controls back.
local function finishOutside(current: Body)
	outsideDoor = nil
	letGo(current)
end

local function standingClips(current: Body, at: number)
	local startAt = entryStartAt
	if startAt and at > startAt + Config.REFUSED_SECONDS then
		-- The server never seated us: refused.
		entryStartAt = nil
		letGo(current)
	end
	local pending = outsideDoor
	if pending == nil then
		-- Off the seat a held exit clip ends at once: the server put the root where it showed the body.
		ClipPlayer.set(current.clips, nil, nil, 0)
		return
	end
	local request = Rules.outsideRequest(CarState.read(pending.car), at, pending.askedAt)
	if request.clip then
		ClipPlayer.set(current.clips, clipId(request.clip, true), request.into, POSE_FADE)
		return
	end
	if request.finished then
		finishOutside(current)
	end
	ClipPlayer.set(current.clips, nil, nil, 0)
end

local function update()
	local current = body
	if current == nil then
		return
	end
	local at = now()
	local car = seatedCar()
	if car then
		seatedClips(current, car, at)
		local held = exitHeld
		if held and Rules.exitHeld(os.clock() - held.since) then
			exitHeld = nil
			send(car, "Exit")
		end
	else
		exitHeld = nil
		standingClips(current, at)
	end
end

local function onInputBegan(input: InputObject)
	local car = seatedCar()
	if car == nil or UserInputService:GetFocusedTextBox() ~= nil then
		return
	end
	local key = input.KeyCode
	if table.find(Controls.DOOR, key) then
		send(car, "Door")
	elseif table.find(Controls.START_ENGINE, key) then
		send(car, "Start")
	elseif table.find(Controls.EXIT, key) then
		exitHeld = { key = key, since = os.clock() }
	end
end

local function onCharacter(character: Model)
	if body then
		ClipPlayer.destroy(body.clips)
	end
	body, busy, outsideDoor, entryStartAt = nil, false, nil, nil
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart
	local animator = humanoid:WaitForChild("Animator") :: Animator
	if character.Parent == nil or localPlayer.Character ~= character then
		return
	end
	body = { character = character, humanoid = humanoid, root = root, clips = ClipPlayer.new(animator) }
	humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
		local inCar = seatedCar() ~= nil
		-- Jumping would leave the seat; Space is the handbrake and leaving is the exit key's.
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, not inCar)
		local current = body
		if not inCar or current == nil or current.humanoid ~= humanoid then
			return
		end
		entryStartAt = nil
		if outsideDoor ~= nil then
			finishOutside(current)
		else
			letGo(current)
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
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local held = exitHeld
		if held and input.KeyCode == held.key then
			exitHeld = nil
		end
	end)
	RunService.PreAnimation:Connect(update)
	if localPlayer.Character then
		task.spawn(onCharacter, localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(onCharacter)
end

return Controller
