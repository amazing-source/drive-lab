--!strict
--[[
	Walks the local character to a car's door mark for Controllers/CarEntry and places it there.
	Round the car's collision box (Rules/ApproachPath) to a point in front of the mark, turned
	there to face the car while clear of it, then straight in without turning. Humanoid:MoveTo is
	aimed past each point, since it stops 0.76 to 0.92 studs short of its target (measured in
	Play), and stopped on the point by asking it to walk to where the body already is. A leg that
	stops closing in is blocked, and the walk tries again from where the body stands. The movement
	keys cannot be switched off here, so the caller's `going` ends the walk when the player moves.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ApproachPath = require(ReplicatedStorage.Shared.Rules.ApproachPath)
local Config = require(ReplicatedStorage.Shared.Config.CarEntry)
local DoorMark = require(ReplicatedStorage.Shared.Car.DoorMark)
local Rules = require(ReplicatedStorage.Shared.Rules.CarEntry)

-- `going` is asked every frame: false ends the walk where the body stands.
export type Walk = { humanoid: Humanoid, root: BasePart, going: () -> boolean }
export type Outcome = "Arrived" | "Stopped" | "Blocked"

local APPROACH = Config.APPROACH
-- Studs past a point MoveTo is aimed at: more than it ever stops short.
local PAST = 2

local EntryWalk = {}

local function flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function halt(walk: Walk)
	walk.humanoid:MoveTo(walk.root.Position)
end

function EntryWalk.turn(from: CFrame, to: CFrame): number
	local a, b = flat(from.LookVector), flat(to.LookVector)
	if a.Magnitude < 1e-3 or b.Magnitude < 1e-3 then
		return 0
	end
	return math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1))
end

-- Walks to `point`, stopping on it (`stopOn`) or turning for the next one within `within`.
local function leg(walk: Walk, point: Vector3, within: number, stopOn: boolean, deadline: number): Outcome
	local root, humanoid = walk.root, walk.humanoid
	local best, bestAt, step = math.huge, os.clock(), 0
	while true do
		if not walk.going() then
			halt(walk)
			return "Stopped"
		end
		local toward = flat(point - root.Position)
		local distance = toward.Magnitude
		if distance <= within or (stopOn and distance <= step) then
			if stopOn then
				halt(walk)
			end
			return "Arrived"
		end
		if distance < best - APPROACH.progress then
			best, bestAt = distance, os.clock()
		elseif os.clock() - bestAt > APPROACH.stallSeconds or os.clock() > deadline then
			halt(walk)
			return "Blocked"
		end
		humanoid:MoveTo(root.Position + toward.Unit * (distance + PAST))
		step = flat(root.AssemblyLinearVelocity).Magnitude * task.wait()
	end
end

-- Moves and turns the body onto `goal` (its height kept), eased, still. Not anchored: getting in,
-- the seat's weld can arrive meanwhile, and a weld that joins an anchored root pulls the car to it.
function EntryWalk.place(walk: Walk, goal: CFrame, seconds: number)
	local root = walk.root
	local from = root.CFrame
	local target = goal.Rotation + Vector3.new(goal.Position.X, from.Position.Y, goal.Position.Z)
	local started = os.clock()
	halt(walk)
	while walk.going() and walk.humanoid.SeatPart == nil do
		local share = Rules.settleShare(os.clock() - started, seconds)
		root.CFrame = from:Lerp(target, share)
		-- Else the root keeps the walk's velocity and slides on with it (measured: 0.05 studs).
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		if share >= 1 then
			break
		end
		task.wait()
	end
	halt(walk)
end

-- Seconds to place the body on `goal` from where it stands.
function EntryWalk.placeSeconds(root: BasePart, goal: CFrame): number
	return Rules.settleSeconds(
		flat(goal.Position - root.Position).Magnitude,
		EntryWalk.turn(root.CFrame, goal)
	)
end

-- Turns on the spot to face as `facing` does.
local function squareUp(walk: Walk, facing: CFrame)
	local here = facing.Rotation + walk.root.Position
	EntryWalk.place(walk, here, EntryWalk.placeSeconds(walk.root, here))
end

-- The waypoints round the car's collision box to `goal`.
local function around(walk: Walk, hull: BasePart?, goal: Vector3): { Vector3 }
	if hull == nil then
		return { goal }
	end
	local frame = hull.CFrame
	local here = frame:PointToObjectSpace(walk.root.Position)
	local there = frame:PointToObjectSpace(goal)
	local hx, hz = hull.Size.X / 2 + APPROACH.margin, hull.Size.Z / 2 + APPROACH.margin
	local points: { Vector3 } = {}
	for _, point in ApproachPath.find({ x = here.X, z = here.Z }, { x = there.X, z = there.Z }, hx, hz) do
		table.insert(points, frame:PointToWorldSpace(Vector3.new(point.x, here.Y, point.z)))
	end
	return points
end

local function attempt(walk: Walk, mark: CFrame, hull: BasePart?, deadline: number): Outcome
	local here = mark:PointToObjectSpace(walk.root.Position)
	local plan = Rules.approachPlan(here.X, here.Z, EntryWalk.turn(walk.root.CFrame, mark))
	if plan == "Settle" then
		return "Arrived"
	end
	if plan == "LineUp" then
		local points = around(walk, hull, (mark * CFrame.new(0, 0, APPROACH.lineUp)).Position)
		for index, point in points do
			local last = index == #points
			local outcome: Outcome =
				leg(walk, point, if last then APPROACH.arrived else APPROACH.pass, last, deadline)
			if outcome ~= "Arrived" then
				return outcome
			end
		end
	end
	if EntryWalk.turn(walk.root.CFrame, mark) > APPROACH.lineUpAngle / 2 then
		squareUp(walk, mark)
	end
	local stop = mark * CFrame.new(0, 0, APPROACH.short)
	local left = stop:PointToObjectSpace(walk.root.Position)
	if left.Z <= APPROACH.arrived and math.abs(left.X) <= APPROACH.arrived then
		-- Already there or nearer the mark: the placing covers the rest.
		return "Arrived"
	end
	walk.humanoid.AutoRotate = false
	local outcome: Outcome = leg(walk, stop.Position, APPROACH.arrived, true, deadline)
	walk.humanoid.AutoRotate = true
	return outcome
end

-- Walks to the door's mark in front of `seat`, round `hull` when it is in the way. Arrived means within
-- APPROACH.reach of the mark, for the caller to place the body on it.
function EntryWalk.toMark(walk: Walk, door: Config.Door, seat: BasePart, hull: BasePart?): Outcome
	local mark = DoorMark.frame(door, seat)
	local deadline = os.clock() + Config.APPROACH_SECONDS
	for _ = 1, APPROACH.tries do
		local outcome: Outcome = attempt(walk, mark, hull, deadline)
		if outcome ~= "Blocked" then
			return outcome
		end
	end
	return if DoorMark.distance(door, seat, walk.root.Position) <= APPROACH.reach
		then "Arrived"
		else "Blocked"
end

-- Gives the body back to the player: free, turning with its walk, and when standing, with no
-- walk target left behind (a seated humanoid would keep one for when it stands). `seated`: a
-- seat's weld holds the body, which Humanoid.SeatPart can say a frame late.
function EntryWalk.release(walk: Walk, seated: boolean)
	walk.root.Anchored = false
	walk.humanoid.AutoRotate = true
	if not seated and walk.humanoid.SeatPart == nil then
		halt(walk)
	end
end

return table.freeze(EntryWalk)
