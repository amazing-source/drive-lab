--!strict
--[[
	Client half of the car entry Play matrix (#40), installed in a Play session only. Runs one
	scenario (a case, a start, an abuse) through the real paths: the ProximityPrompts for what is
	done from outside, the CarAction remote (what the seated keys send) for what is done inside.
	Records every frame and returns pass or fail with the numbers. MatrixServer provides the
	fixtures and the server's own view.
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CarState = require(ReplicatedStorage.Shared.Car.CarState)
local Config = require(ReplicatedStorage.Shared.Config.CarEntry)
local DoorMark = require(ReplicatedStorage.Shared.Car.DoorMark)
local Driving = require(ReplicatedStorage.Shared.Config.Driving)
local Rules = require(ReplicatedStorage.Shared.Rules.CarEntry)

export type Start = { lateral: number, outward: number, yaw: number }
export type Scenario = { name: string, case: string, start: Start?, abuse: string? }
type Frame = {
	t: number,
	root: Vector3,
	torso: Vector3,
	seated: boolean,
	anchored: boolean,
	autoRotate: boolean,
	scale: number,
	entryClip: boolean,
	exitClip: boolean,
	character: Model,
}

local player = Players.LocalPlayer
-- Set once the server has reserved the car for this player during the current scenario: the
-- end of a cancelled or reset walk is the reservation let go after that.
local sawReservation = false
local SEATED_CASES = { CloseInside = true, OpenInside = true, ExitShut = true, ExitOpen = true }
local OPEN_DOOR = { CloseOutside = true, EnterOpen = true, CloseInside = true, ExitOpen = true }
local ENTRY_IDS = { [Config.CLIPS.OutsideOpen.seated] = true, [Config.CLIPS.GetIn.seated] = true }
local EXIT_IDS = {
	[Config.CLIPS.InsideOpen.seated] = true,
	[Config.CLIPS.GetOut.seated] = true,
	[Config.CLIPS.OutsideClose.seated] = true,
}

local Client = {}

local function car(): Model
	return CollectionService:GetTagged("DriveLabCar")[1] :: Model
end

local function seat(): BasePart
	return car():FindFirstChild("DriverSeat", true) :: BasePart
end

local function remote(): RemoteFunction
	return ReplicatedStorage:WaitForChild("_PacingRemote") :: RemoteFunction
end

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function body(): (Model, Humanoid, BasePart)
	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	while humanoid.Health <= 0 do
		character = player.CharacterAdded:Wait()
		humanoid = character:WaitForChild("Humanoid") :: Humanoid
	end
	return character, humanoid, character:WaitForChild("HumanoidRootPart") :: BasePart
end

local function waitFor(condition: () -> boolean, seconds: number): boolean
	local deadline = os.clock() + seconds
	while os.clock() < deadline do
		if condition() then
			return true
		end
		task.wait(0.05)
	end
	return condition()
end

local function playing(animator: Animator, ids: { [string]: boolean }): boolean
	for _, track in animator:GetPlayingAnimationTracks() do
		local animation = track.Animation
		if animation and ids[animation.AnimationId] and track.WeightCurrent > 0.5 then
			return true
		end
	end
	return false
end

local function prompt(name: string): ProximityPrompt
	return car():FindFirstChild(name, true) :: ProximityPrompt
end

local function press(name: string)
	local target = prompt(name)
	target:InputHoldBegin()
	task.wait()
	target:InputHoldEnd()
end

-- Studs from the body to the prompt, and how far the prompt reaches.
local function promptReach(name: string): (number, number)
	local target = prompt(name)
	local holder = target.Parent
	local _, _, root = body()
	local at = if holder and holder:IsA("Attachment")
		then holder.WorldPosition
		elseif holder and holder:IsA("BasePart") then holder.Position
		else root.Position
	return (at - root.Position).Magnitude, target.MaxActivationDistance
end

local function promptName(case: string): string
	return if case == "EnterShut" or case == "EnterOpen" then "Enter" else "Door"
end

local function send(action: string)
	local event = ReplicatedStorage:FindFirstChild("CarAction", true) :: RemoteEvent
	event:FireServer({ car = car(), action = action })
end

-- Stands the local body at `start` (the mark's frame: sideways, out from the car, turned from
-- facing it), on the ground, and waits until the server sees it there.
local function placeAt(start: Start)
	local character, humanoid, root = body()
	local mark = DoorMark.frame(seat())
	local spot = mark * CFrame.new(start.lateral, 0, start.outward) * CFrame.Angles(0, math.rad(start.yaw), 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { car(), character }
	local hit = Workspace:Raycast(spot.Position + Vector3.new(0, 6, 0), Vector3.new(0, -40, 0), params)
	local ground = if hit then hit.Position.Y else root.Position.Y - 3 * character:GetScale()
	root.CFrame = spot.Rotation + Vector3.new(spot.Position.X, ground + 3 * character:GetScale(), spot.Position.Z)
	root.AssemblyLinearVelocity = Vector3.zero
	humanoid:MoveTo(root.Position)
	local wanted = DoorMark.distance(seat(), root.Position)
	waitFor(function(): boolean
		local seen = remote():InvokeServer("state")
		return math.abs(seen.dist - wanted) < 0.3
	end, 4)
end

local function record(): ({ Frame }, () -> ())
	local frames: { Frame } = {}
	local started = os.clock()
	sawReservation = false
	local connection = RunService.Heartbeat:Connect(function()
		if car():GetAttribute("ReservedBy") == player.UserId then
			sawReservation = true
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local torso = character and character:FindFirstChild("Torso")
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		if character == nil or humanoid == nil or root == nil or torso == nil or animator == nil then
			return
		end
		table.insert(frames, {
			t = os.clock() - started,
			root = (root :: BasePart).Position,
			torso = (torso :: BasePart).Position,
			seated = humanoid.SeatPart ~= nil,
			anchored = (root :: BasePart).Anchored,
			autoRotate = humanoid.AutoRotate,
			scale = character:GetScale(),
			entryClip = playing(animator, ENTRY_IDS),
			exitClip = playing(animator, EXIT_IDS),
			character = character,
		})
	end)
	return frames, function()
		connection:Disconnect()
	end
end

local function first(frames: { Frame }, test: (Frame) -> boolean): Frame?
	for _, frame in frames do
		if test(frame) then
			return frame
		end
	end
	return nil
end

-- The largest jump of the root between two frames while standing, of the same body: what a pull
-- back to a stale server position, or a snap, looks like.
local function standingJump(frames: { Frame }): number
	local worst = 0
	for index = 2, #frames do
		local a, b = frames[index - 1], frames[index]
		if not a.seated and not b.seated and a.character == b.character then
			worst = math.max(worst, (Vector3.new(b.root.X, 0, b.root.Z) - Vector3.new(a.root.X, 0, a.root.Z)).Magnitude)
		end
	end
	return worst
end

-- The torso's jump across the frame where the body went from standing to seated (or back),
-- across the ground only: the size change moves it up or down on purpose.
local function handOverJump(frames: { Frame }): number
	local worst = 0
	for index = 2, #frames do
		local a, b = frames[index - 1], frames[index]
		if a.seated ~= b.seated and a.character == b.character then
			worst = math.max(worst, (Vector3.new(b.torso.X, 0, b.torso.Z) - Vector3.new(a.torso.X, 0, a.torso.Z)).Magnitude)
		end
	end
	return worst
end

local function hullOverlap(character: Model): boolean
	local hull = car():FindFirstChild("Hull") :: BasePart?
	if hull == nil then
		return false
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { hull }
	for _, name in { "Torso", "Head" } do
		local part = character:FindFirstChild(name) :: BasePart?
		if part and #Workspace:GetPartsInPart(part, params) > 0 then
			return true
		end
	end
	return false
end

local function phase(): Rules.Phase
	return Rules.phase(CarState.read(car()), now())
end

local function setUp(scenario: Scenario): boolean
	local door = if OPEN_DOOR[scenario.case] then "Open" else "Closed"
	remote():InvokeServer("outside", "Closed")
	waitFor(function(): boolean
		local _, humanoid = body()
		return humanoid.SeatPart == nil and car():GetAttribute("ReservedBy") == 0
	end, 9)
	if SEATED_CASES[scenario.case] then
		remote():InvokeServer("seated", door)
		return waitFor(function(): boolean
			local _, humanoid = body()
			return humanoid.SeatPart ~= nil and phase() == "Seated"
		end, 5)
	end
	remote():InvokeServer("outside", door)
	placeAt(scenario.start or { lateral = 0, outward = 4, yaw = 0 })
	return waitFor(function(): boolean
		return prompt(promptName(scenario.case)).Enabled
	end, 4)
end

local function act(scenario: Scenario)
	local case = scenario.case
	if case == "EnterShut" or case == "EnterOpen" then
		press("Enter")
		if scenario.abuse == "DoubleE" then
			task.wait(0.15)
			press("Enter")
		end
	elseif case == "OpenOutside" or case == "CloseOutside" then
		press("Door")
	elseif case == "CloseInside" or case == "OpenInside" then
		send("Door")
	else
		send("Exit")
	end
end

local function abuse(scenario: Scenario, frames: { Frame })
	local kind = scenario.abuse
	if kind == "ResetWalk" then
		task.wait(0.35)
		remote():InvokeServer("kill")
	elseif kind == "ResetSequence" then
		waitFor(function(): boolean
			local last = frames[#frames]
			return last ~= nil and (last.entryClip or last.exitClip)
		end, 8)
		task.wait(1)
		remote():InvokeServer("kill")
	elseif kind == "KeysDuring" then
		waitFor(function(): boolean
			local last = frames[#frames]
			return last ~= nil and (last.entryClip or last.exitClip)
		end, 8)
		for _, action in { "Door", "Start", "Exit", "Enter", "Door", "Cancel" } do
			task.wait(0.4)
			send(action)
		end
	end
end

local function finished(scenario: Scenario): boolean
	local _, humanoid, root = body()
	local state, at = CarState.read(car()), now()
	local case = scenario.case
	if scenario.abuse == "ResetWalk" or scenario.abuse == "WalkAway" then
		return sawReservation and state.entry == "None" and car():GetAttribute("ReservedBy") == 0
	elseif scenario.abuse == "ResetSequence" then
		return state.entry == "None" and car():GetAttribute("ReservedBy") == 0 and humanoid.SeatPart == nil
	elseif case == "EnterShut" or case == "EnterOpen" then
		return humanoid.SeatPart ~= nil and Rules.phase(state, at) == "Seated"
	elseif case == "ExitShut" or case == "ExitOpen" then
		return humanoid.SeatPart == nil and state.entry == "None"
	end
	return Rules.doorIdle(state, at) and not root.Anchored and car():GetAttribute("ReservedBy") == 0
end

local function check(scenario: Scenario, frames: { Frame }, log: { any }, notes: { string }): boolean
	local character, humanoid, root = body()
	local state, at = CarState.read(car()), now()
	local ok = true
	local function expect(condition: boolean, what: string)
		if not condition then
			ok = false
			table.insert(notes, "FAIL " .. what)
		end
	end
	local requests = 0
	for _, entry in log do
		if entry.action == "Enter" then
			requests += 1
		end
	end
	local case, kind = scenario.case, scenario.abuse
	expect(not root.Anchored, "the root is left anchored")
	expect(standingJump(frames) <= 1, string.format("a standing jump of %.2f studs", standingJump(frames)))
	if kind == "ResetWalk" or kind == "ResetSequence" or kind == "WalkAway" then
		expect(state.entry == "None", "entry state " .. state.entry)
		expect(humanoid.SeatPart == nil, "still seated")
		expect(state.door == "Closed" or state.door == "Open" or Rules.doorIdle(state, at), "door left moving")
		expect(car():GetAttribute("ReservedBy") == 0, "reservation held")
		expect(math.abs(character:GetScale() - 1) < 1e-3, string.format("scale %.3f", character:GetScale()))
		expect(humanoid.AutoRotate, "AutoRotate left off")
		return ok
	end
	if case == "EnterShut" or case == "EnterOpen" then
		expect(humanoid.SeatPart ~= nil and phase() == "Seated", "not seated")
		expect(Rules.doorClosed(state, at), "door not shut")
		expect(math.abs(character:GetScale() - Driving.DRIVER_SCALE) < 1e-3, "not at the seated size")
		if kind ~= "KeysDuring" then
			expect(requests == 1, `{requests} Enter requests reached the server`)
		end
		expect(handOverJump(frames) <= 0.4, string.format("hand-over jump %.2f studs", handOverJump(frames)))
	elseif case == "ExitShut" or case == "ExitOpen" then
		local goal = DoorMark.exitFrame(seat())
		local off = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(goal.Position.X, 0, goal.Position.Z)).Magnitude
		expect(humanoid.SeatPart == nil, "still seated")
		expect(off <= 0.35, string.format("%.2f studs from where getting out ends", off))
		expect(math.abs(character:GetScale() - 1) < 1e-3, "not at full size")
		expect(not hullOverlap(character), "overlapping the car's collision box")
		expect(state.entry == "None" and state.engine == "Off", "car state not at rest")
		expect(Rules.doorClosed(state, at), "door not shut")
		expect(humanoid.AutoRotate, "AutoRotate left off")
		expect(handOverJump(frames) <= 0.35, string.format("hand-over jump %.2f studs", handOverJump(frames)))
	elseif case == "OpenOutside" or case == "CloseOutside" or case == "CloseInside" or case == "OpenInside" then
		local open = Rules.doorOpenness(state, at)
		local wantOpen = case == "OpenOutside" or case == "OpenInside"
		expect(Rules.doorIdle(state, at), "door still moving")
		expect(if wantOpen then open >= 0.999 else open <= 0.001, string.format("door openness %.3f", open))
		if case == "OpenOutside" or case == "CloseOutside" then
			expect(humanoid.SeatPart == nil, "seated")
			expect(math.abs(character:GetScale() - 1) < 1e-3, "not at full size")
			expect(humanoid.AutoRotate, "AutoRotate left off")
			expect(car():GetAttribute("ReservedBy") == 0, "reservation held")
		else
			expect(humanoid.SeatPart ~= nil, "not seated")
		end
	end
	return ok
end

local function timings(frames: { Frame }): { [string]: number }
	local out: { [string]: number } = {}
	local mark = DoorMark.frame(seat()).Position
	local onMark = first(frames, function(frame: Frame): boolean
		return not frame.seated
			and (Vector3.new(frame.root.X, 0, frame.root.Z) - Vector3.new(mark.X, 0, mark.Z)).Magnitude <= 0.05
	end)
	local clip = first(frames, function(frame: Frame): boolean
		return frame.entryClip or frame.exitClip
	end)
	local seated = first(frames, function(frame: Frame): boolean
		return frame.seated
	end)
	local walkStart = nil
	for index = 2, #frames do
		local a, b = frames[index - 1], frames[index]
		if not b.seated and (b.root - a.root).Magnitude > 0.05 and a.character == b.character then
			walkStart = b.t
			break
		end
	end
	out.walkStart = walkStart or -1
	out.onMark = if onMark then onMark.t else -1
	out.firstClip = if clip then clip.t else -1
	out.seated = if seated then seated.t else -1
	out.deadAtMark = if onMark and clip then clip.t - onMark.t else -1
	return out
end

-- Runs a scenario in the background, for one driven by real key presses from outside.
function Client.start(scenario: Scenario)
	shared.PacingResult = nil
	task.spawn(function()
		shared.PacingResult = Client.run(scenario)
	end)
end

function Client.run(scenario: Scenario): { [string]: any }
	local result: { [string]: any } = { name = scenario.name, pass = false, notes = {} }
	if not setUp(scenario) then
		table.insert(result.notes, "FAIL set-up: the prompt or the seat never became available")
		return result
	end
	local frames, stop = record()
	local serverStart = now()
	if not SEATED_CASES[scenario.case] then
		local distance, reach = promptReach(promptName(scenario.case))
		result.promptDistance = distance
		if distance > reach then
			-- Out of the prompt's reach no player can press it: pressing anyway must change nothing.
			act(scenario)
			task.wait(2.5)
			stop()
			local _, humanoid = body()
			local state = CarState.read(car())
			result.outOfReach = true
			result.pass = not sawReservation and state.entry == "None" and humanoid.SeatPart == nil
			if not result.pass then
				table.insert(result.notes, "FAIL out of reach, yet the car reacted")
			end
			return result
		end
	end
	act(scenario)
	abuse(scenario, frames)
	local done = waitFor(function(): boolean
		return finished(scenario)
	end, 22)
	task.wait(if scenario.case == "ExitShut" or scenario.case == "ExitOpen" then 1 else 0.3)
	stop()
	local log = remote():InvokeServer("log", serverStart - 0.5)
	if not done then
		table.insert(result.notes, "FAIL did not finish within 22 s")
	end
	result.pass = check(scenario, frames, log, result.notes) and done
	result.timings = timings(frames)
	result.standingJump = standingJump(frames)
	result.handOverJump = handOverJump(frames)
	result.requests = #log
	result.frames = #frames
	return result
end

return Client
