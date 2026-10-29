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
	-- The root before this frame's physics, after the game's own frame code moved it.
	before: Vector3,
	torso: Vector3,
	seated: boolean,
	anchored: boolean,
	autoRotate: boolean,
	scale: number,
	entryClip: boolean,
	exitClip: boolean,
	doorClip: boolean,
	-- A dead body falls apart as Roblox's death does: its frames are no jump of the game's.
	dead: boolean,
	-- The driver's seat this frame: the car can move, and the mark and exit spot move with it.
	seat: CFrame,
	character: Model,
}

local player = Players.LocalPlayer
-- Set once the server has reserved the car for this player during the current scenario: the
-- end of a cancelled or reset walk is the reservation let go after that.
local sawReservation = false
local SEATED_CASES = { CloseInside = true, OpenInside = true, ExitShut = true, ExitOpen = true }
local OPEN_DOOR = { CloseOutside = true, EnterOpen = true, CloseInside = true, ExitOpen = true }
local ENTRY_IDS = { [Config.CLIPS.OutsideOpen.seated] = true, [Config.CLIPS.GetIn.seated] = true }
local DOOR_IDS = {
	[Config.CLIPS.OutsideOpen.standing or ""] = true,
	[Config.CLIPS.OutsideClose.standing or ""] = true,
	[Config.CLIPS.InsideOpen.seated] = true,
	[Config.CLIPS.InsideClose.seated] = true,
}
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
local function placeAt(start: Start): boolean
	local character, humanoid, root = body()
	-- The fixture's size change reaches this client late; a placement before it would be moved.
	waitFor(function(): boolean
		return math.abs(character:GetScale() - 1) < 1e-3
	end, 4)
	local mark = DoorMark.frame(seat())
	local spot = mark * CFrame.new(start.lateral, 0, start.outward) * CFrame.Angles(0, math.rad(start.yaw), 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { car(), character }
	local hit = Workspace:Raycast(spot.Position + Vector3.new(0, 6, 0), Vector3.new(0, -40, 0), params)
	local ground = if hit then hit.Position.Y else root.Position.Y - 3 * character:GetScale()
	local goal = spot.Rotation
		+ Vector3.new(spot.Position.X, ground + 3 * character:GetScale(), spot.Position.Z)
	local wanted = DoorMark.distance(seat(), goal.Position)
	-- Placed again until both this client and the server see the body there and it stays.
	for _ = 1, 5 do
		root.CFrame = goal
		root.AssemblyLinearVelocity = Vector3.zero
		humanoid:MoveTo(goal.Position)
		waitFor(function(): boolean
			local seen = remote():InvokeServer("state")
			return math.abs(seen.dist - wanted) < 0.3
		end, 4)
		task.wait(0.3)
		local off =
			Vector3.new(root.Position.X - goal.Position.X, 0, root.Position.Z - goal.Position.Z).Magnitude
		if off < 0.1 then
			return true
		end
	end
	return false
end

local function record(): ({ Frame }, () -> ())
	local frames: { Frame } = {}
	local started = os.clock()
	sawReservation = false
	local before = Vector3.zero
	local beforeConnection = RunService.PreSimulation:Connect(function()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			before = root.Position
		end
	end)
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
		local weld = seat():FindFirstChild("SeatWeld")
		local welded = weld ~= nil and weld:IsA("Weld") and weld.Part1 == root
		table.insert(frames, {
			t = os.clock() - started,
			root = (root :: BasePart).Position,
			before = before,
			torso = (torso :: BasePart).Position,
			-- Seated by the weld itself, as the game's own clips decide it.
			seated = welded,
			anchored = (root :: BasePart).Anchored,
			autoRotate = humanoid.AutoRotate,
			scale = character:GetScale(),
			entryClip = playing(animator, ENTRY_IDS),
			exitClip = playing(animator, EXIT_IDS),
			doorClip = playing(animator, DOOR_IDS),
			dead = humanoid.Health <= 0,
			seat = seat().CFrame,
			character = character,
		})
	end)
	return frames, function()
		connection:Disconnect()
		beforeConnection:Disconnect()
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
		if not a.seated and not b.seated and a.character == b.character and not b.dead then
			worst = math.max(
				worst,
				(Vector3.new(b.root.X, 0, b.root.Z) - Vector3.new(a.root.X, 0, a.root.Z)).Magnitude
			)
		end
	end
	return worst
end

-- The largest move of the torso in one frame, of the same body: what the eye sees jump. The
-- clips move it at most 0.18 studs a frame at 60 fps (GetIn, from the bakes), a walk 0.21.
local function torsoJump(frames: { Frame }): number
	local worst = 0
	for index = 2, #frames do
		local a, b = frames[index - 1], frames[index]
		if a.character == b.character and not b.dead then
			worst = math.max(
				worst,
				(Vector3.new(b.torso.X, 0, b.torso.Z) - Vector3.new(a.torso.X, 0, a.torso.Z)).Magnitude
			)
		end
	end
	return worst
end

-- The frames round the torso's largest one-frame move, for a failure's diagnosis: time, how far
-- the torso and root moved into that frame, seated, anchored, scale and the clip playing.
local function worstWindow(frames: { Frame }): string
	local worst, at = 0, 0
	for index = 2, #frames do
		local a, b = frames[index - 1], frames[index]
		local moved = (Vector3.new(b.torso.X, 0, b.torso.Z) - Vector3.new(a.torso.X, 0, a.torso.Z)).Magnitude
		if a.character == b.character and not b.dead and moved > worst then
			worst, at = moved, index
		end
	end
	if at == 0 then
		return ""
	end
	local lines = {}
	local fromSeat = seat().CFrame:ToObjectSpace(DoorMark.frame(seat()))
	for index = math.max(2, at - 6), math.min(#frames, at + 3) do
		local a, b = frames[index - 1], frames[index]
		local clip = if b.entryClip
			then "entry"
			elseif b.exitClip then "exit"
			elseif b.doorClip then "door"
			else "-"
		local rel = (b.seat * fromSeat):PointToObjectSpace(b.root)
		table.insert(
			lines,
			string.format(
				"%s%d t=%.3f torso=%.2f root=%.2f phys=%.2f mark=(%.2f,%.2f) seated=%s anch=%s scale=%.3f %s",
				if index == at then ">" else " ",
				index,
				b.t,
				(Vector3.new(b.torso.X, 0, b.torso.Z) - Vector3.new(a.torso.X, 0, a.torso.Z)).Magnitude,
				(Vector3.new(b.root.X, 0, b.root.Z) - Vector3.new(a.root.X, 0, a.root.Z)).Magnitude,
				(Vector3.new(b.root.X, 0, b.root.Z) - Vector3.new(b.before.X, 0, b.before.Z)).Magnitude,
				rel.X,
				rel.Z,
				tostring(b.seated),
				tostring(b.anchored),
				b.scale,
				clip
			)
		)
	end
	return table.concat(lines, "\n")
end

-- The torso's jump across the frame where the body went from standing to seated (or back),
-- across the ground only: the size change moves it up or down on purpose.
local function handOverJump(frames: { Frame }): number
	local worst = 0
	for index = 2, #frames do
		local a, b = frames[index - 1], frames[index]
		if a.seated ~= b.seated and a.character == b.character and not b.dead then
			worst = math.max(
				worst,
				(Vector3.new(b.torso.X, 0, b.torso.Z) - Vector3.new(a.torso.X, 0, a.torso.Z)).Magnitude
			)
		end
	end
	return worst
end

-- Where getting out ends: the branch's exit frame, or the mark on main (which has none).
local function exitSpot(): CFrame
	local exitFrame = (DoorMark :: any).exitFrame
	return if exitFrame then exitFrame(seat()) else DoorMark.frame(seat())
end

-- The exit spot where the car stood on `frame`.
local function exitSpotAt(frame: Frame): CFrame
	return frame.seat * seat().CFrame:ToObjectSpace(exitSpot())
end

local function standUpIndex(frames: { Frame }): number?
	for index = 2, #frames do
		if frames[index - 1].seated and not frames[index].seated then
			return index
		end
	end
	return nil
end

-- The root's offset across the ground from where getting out ends, from the first frame off the
-- seat: at that frame, a few after, and the last, with the time and the size.
local function exitTrace(frames: { Frame }): string
	local start = standUpIndex(frames)
	if start == nil then
		return "never stood up"
	end
	local picks = {}
	for _, offset in { 0, 1, 2, 3, 5, 10, 20, 40, 80 } do
		if start + offset <= #frames then
			table.insert(picks, start + offset)
		end
	end
	table.insert(picks, #frames)
	local parts = {}
	local first = exitSpotAt(frames[start])
	for _, index in picks do
		local frame = frames[index]
		local spot = exitSpotAt(frame)
		local rel = spot:PointToObjectSpace(frame.root)
		local moved = (spot.Position - first.Position) * Vector3.new(1, 0, 1)
		table.insert(
			parts,
			string.format(
				"+%d t=%.2f off=(%.2f,%.2f) car moved %.2f s=%.3f",
				index - start,
				frame.t,
				rel.X,
				rel.Z,
				moved.Magnitude,
				frame.scale
			)
		)
	end
	return table.concat(parts, " | ")
end

-- How far the root moved, standing, from the first frame off the seat to the last frame: what
-- the car's collision box pushing the body would show.
local function drift(frames: { Frame }): number
	for index = 2, #frames do
		if frames[index - 1].seated and not frames[index].seated then
			local a, b = frames[index].root, frames[#frames].root
			return (Vector3.new(b.X, 0, b.Z) - Vector3.new(a.X, 0, a.Z)).Magnitude
		end
	end
	return 0
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
	if not placeAt(scenario.start or { lateral = 0, outward = 4, yaw = 0 }) then
		return false
	end
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

-- The body is still being walked or held by the entry's own code.
local function walkingOrHeld(humanoid: Humanoid): boolean
	return not humanoid.AutoRotate
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
	-- A door case ends once the door rests where it was asked to go and the body is free.
	local open = Rules.doorOpenness(state, at)
	local wantOpen = case == "OpenOutside" or case == "OpenInside"
	local reached = if wantOpen then open >= 0.999 else open <= 0.001
	return reached
		and Rules.doorIdle(state, at)
		and not root.Anchored
		and car():GetAttribute("ReservedBy") == 0
		and (case == "CloseInside" or case == "OpenInside" or not walkingOrHeld(humanoid))
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
	expect(
		torsoJump(frames) <= 0.5,
		string.format("the torso jumped %.2f studs in one frame", torsoJump(frames))
	)
	if kind == "ResetWalk" or kind == "ResetSequence" or kind == "WalkAway" then
		expect(state.entry == "None", "entry state " .. state.entry)
		expect(humanoid.SeatPart == nil, "still seated")
		expect(
			state.door == "Closed" or state.door == "Open" or Rules.doorIdle(state, at),
			"door left moving"
		)
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
		-- Where the body stood up against where getting out ends, both where the car was then: the
		-- car itself can move afterwards (reported apart, as carAfterExit).
		local start = standUpIndex(frames)
		local off = math.huge
		if start then
			local frame = frames[start]
			local spot = exitSpotAt(frame)
			off = (Vector3.new(frame.root.X, 0, frame.root.Z) - Vector3.new(
				spot.Position.X,
				0,
				spot.Position.Z
			)).Magnitude
		end
		expect(humanoid.SeatPart == nil, "still seated")
		expect(off <= 0.35, string.format("stood up %.2f studs from where getting out ends", off))
		expect(math.abs(character:GetScale() - 1) < 1e-3, "not at full size")
		expect(not hullOverlap(character), "overlapping the car's collision box")
		expect(state.entry == "None" and state.engine == "Off", "car state not at rest")
		expect(Rules.doorClosed(state, at), "door not shut")
		expect(humanoid.AutoRotate, "AutoRotate left off")
		expect(handOverJump(frames) <= 0.35, string.format("hand-over jump %.2f studs", handOverJump(frames)))
		expect(drift(frames) <= 0.1, string.format("pushed %.2f studs after getting out", drift(frames)))
	elseif
		case == "OpenOutside"
		or case == "CloseOutside"
		or case == "CloseInside"
		or case == "OpenInside"
	then
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
			and (Vector3.new(frame.root.X, 0, frame.root.Z) - Vector3.new(mark.X, 0, mark.Z)).Magnitude
				<= 0.05
	end)
	local clip = first(frames, function(frame: Frame): boolean
		return frame.entryClip or frame.exitClip or frame.doorClip
	end)
	local lastExit = nil
	for _, frame in frames do
		if frame.exitClip then
			lastExit = frame.t
		end
	end
	local standing = nil
	for index = 2, #frames do
		if frames[index - 1].seated and not frames[index].seated then
			standing = frames[index].t
		end
	end
	out.exitEndToStanding = if lastExit and standing then standing - lastExit else -1
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
	if scenario.abuse == "WalkAway" then
		-- Driven from outside: the movement key is a real key press sent with the go.
		shared.PacingGo = false
		shared.PacingReady = true
		waitFor(function(): boolean
			return shared.PacingGo == true
		end, 90)
		shared.PacingReady = false
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
	result.torsoJump = torsoJump(frames)
	result.handOverJump = handOverJump(frames)
	result.requests = #log
	local seen = {}
	for _, entry in log do
		table.insert(seen, string.format("%s at %.2f", entry.action, entry.dist))
	end
	result.serverSaw = table.concat(seen, ", ")
	result.drift = drift(frames)
	result.frames = #frames
	local start = standUpIndex(frames)
	if start and (scenario.case == "ExitShut" or scenario.case == "ExitOpen") then
		local a, b = exitSpotAt(frames[start]).Position, exitSpot().Position
		result.carAfterExit = (Vector3.new(b.X, 0, b.Z) - Vector3.new(a.X, 0, a.Z)).Magnitude
	end
	-- How far the car itself moved during the scenario (the fixtures park it before each one).
	result.carMoved = remote():InvokeServer("state").carMoved
	if not result.pass then
		result.window = worstWindow(frames)
	end
	if scenario.case == "ExitShut" or scenario.case == "ExitOpen" then
		result.exitTrace = exitTrace(frames)
	end
	return result
end

return Client
