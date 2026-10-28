--!strict
--[[
	The local player's side of getting in and out, the driver's door and the start. A car's
	prompt walks the body to the door mark and asks the server; the body's clips then play in
	step with the car's state (Rules/CarEntry), the clock every client also turns the door
	from, so the door stays under the hand. Seated: the door key moves the door, the start key
	starts the engine, holding the exit key gets out (Config/Controls). Clips played on one's
	own character replicate to the other players.
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

-- Studs from the mark that count as arrived.
local ARRIVED = 0.6
local POLL_SECONDS = 0.05
-- Seconds a refused request waits before the controls come back.
local REFUSED_SECONDS = 1.5
-- Consecutive clips of a sequence meet on the same pose; a rest pose eases in.
local CHAIN_FADE = 0
local POSE_FADE = 0.15

-- The door's own motions that play a clip on the body, from inside and from outside.
local INSIDE: { [string]: Config.ClipName } = { InsideOpen = "InsideOpen", InsideClose = "InsideClose" }
local OUTSIDE: { [string]: Config.ClipName } = { OutsideOpen = "OutsideOpen", OutsideClose = "OutsideClose" }

local localPlayer = Players.LocalPlayer
local body: Body? = nil
local busy = false
-- A door the local player is moving from outside, and the server time it asked.
local outsideDoor: { car: Model, askedAt: number }? = nil
local exitHeld: { key: Enum.KeyCode, since: number }? = nil
local controls: Controller? = nil

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function send(car: Model, action: Rules.Action)
	Net.send(Remotes.CAR_ACTION, { car = car, action = action })
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

local function waitArrival(current: Body, car: Model, seat: BasePart)
	local started = os.clock()
	while body == current and os.clock() - started < Config.APPROACH_SECONDS do
		if DoorMark.distance(seat, current.root.Position) <= ARRIVED then
			return
		end
		if os.clock() - started > REFUSED_SECONDS / 3 and not reservedForMe(car) then
			return
		end
		task.wait(POLL_SECONDS)
	end
end

-- Walks to the mark, faces the seat, waits for the body to reach the seated size when getting
-- in, then asks. The controls stay off until the seat or the door's clip gives them back.
local function approach(car: Model, intent: Intent)
	local current = body
	local seat = car:FindFirstChild("DriverSeat")
	if
		busy
		or current == nil
		or current.humanoid.SeatPart ~= nil
		or seat == nil
		or not seat:IsA("BasePart")
	then
		return
	end
	busy = true
	setControls(false)
	local mark = DoorMark.frame(seat)
	current.humanoid:MoveTo(Vector3.new(mark.Position.X, current.root.Position.Y, mark.Position.Z))
	waitArrival(current, car, seat)
	if body == current and reservedForMe(car) then
		local position = current.root.Position
		current.root.CFrame = CFrame.lookAt(position, position + mark.LookVector)
		if intent == "Enter" then
			local reservedAt = car:GetAttribute(Config.ATTRIBUTES.RESERVED_AT)
			local ready = (if typeof(reservedAt) == "number" then reservedAt else 0) + Config.SCALE_SECONDS
			while body == current and now() < ready do
				task.wait(POLL_SECONDS)
			end
		else
			-- The door clip leans the body into the car's collision box to reach the door;
			-- held at the mark, physics cannot push it away.
			current.root.Anchored = true
			outsideDoor = { car = car, askedAt = now() }
		end
		send(car, intent)
	end
	busy = false
	task.delay(REFUSED_SECONDS, function()
		if seatedCar() == nil and outsideDoor == nil then
			setControls(true)
		end
	end)
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
			ClipPlayer.set(current.clips, clipId(step.clip, false), into, CHAIN_FADE)
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

local function standingClips(current: Body, at: number)
	local pending = outsideDoor
	if pending == nil then
		-- Off the seat a held exit clip ends at once: the server put the root where it showed the body.
		ClipPlayer.set(current.clips, nil, nil, 0)
		return
	end
	local state = CarState.read(pending.car)
	local outside: Config.ClipName? = OUTSIDE[state.door]
	local mine = outside ~= nil and state.doorAt >= pending.askedAt - 1
	if outside ~= nil and mine and at - state.doorAt < clipLength(outside) then
		ClipPlayer.set(current.clips, clipId(outside, true), at - state.doorAt, POSE_FADE)
		return
	end
	if mine or now() - pending.askedAt > REFUSED_SECONDS then
		outsideDoor = nil
		current.root.Anchored = false
		setControls(true)
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
		if held and os.clock() - held.since >= Config.EXIT_HOLD_SECONDS then
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
	body, busy, outsideDoor = nil, false, nil
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
		if inCar then
			setControls(true)
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
			task.spawn(approach, model, prompt.Name :: Intent)
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
