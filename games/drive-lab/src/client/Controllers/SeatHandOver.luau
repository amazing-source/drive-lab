--!strict
--[[
	The moments the local body changes hands between standing and a car's seat, for
	Controllers/CarEntry. The seat weld, Humanoid.SeatPart and the root's position written by the
	server can each reach this client in a different frame (measured in Play), so the clips follow
	where the root really is, a weld that arrives too late in a frame is held off for it, and after
	getting out this client, which owns the body's physics, puts the body where the last clip frame
	shows it and keeps it there for a moment against the server's own late writes.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CarRig = require(ReplicatedStorage.Shared.Car.CarRig)
local DoorMark = require(ReplicatedStorage.Shared.Car.DoorMark)
local Movement = require(ReplicatedStorage.Shared.Config.Movement)

local ClipPlayer = require(script.Parent.Parent.Rig.ClipPlayer)

export type Body = { character: Model, humanoid: Humanoid, root: BasePart, clips: ClipPlayer.ClipPlayer }

-- R6 standing: the root's centre three studs above the feet, times the scale.
local ROOT_HEIGHT = 3
-- Seconds after getting out during which the body is put back where it was placed if something
-- other than the player moves it.
local HOLD_OUT = 0.6
-- Studs: a root this close to a seat, across the ground, during an entry is in it, weld or not.
local IN_SEAT = 0.5
local MOVED = 0.05
local SIT, IDLE = Movement.ANIMATIONS.sit.id, Movement.ANIMATIONS.idle.id

local heldWeld: Weld? = nil
local heldRoot: BasePart? = nil
local placedOut: { car: Model, at: Vector3, untilClock: number }? = nil
local standingUp = false
-- The body's size last standing frame: a change plants the feet again.
local lastScale: number? = nil

local SeatHandOver = {}

local function flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function seatOf(current: Body, entering: Model?): BasePart?
	local seat: Instance? = current.humanoid.SeatPart
	if seat == nil and entering then
		seat = entering:FindFirstChild("DriverSeat")
	end
	return if seat and seat:IsA("BasePart") then seat else nil
end

local function weldHolds(current: Body, seat: BasePart): boolean
	local weld = seat:FindFirstChild("SeatWeld")
	return weld ~= nil and weld:IsA("Weld") and weld.Part1 == current.root
end

-- The car whose seat holds the body, and whether its weld does: getting into `entering`, the
-- server can put the root in the seat before the weld reaches this client (measured: the body
-- drawn in the seat for a frame, 5 studs from where the clip shows it).
function SeatHandOver.seatedIn(current: Body, entering: Model?): (Model?, boolean)
	local seat = seatOf(current, entering)
	if seat == nil then
		return nil, false
	end
	local welded = weldHolds(current, seat)
	local carried = entering ~= nil and flat(current.root.Position - seat.Position).Magnitude < IN_SEAT
	local model = seat.Parent
	if (welded or carried) and model and model:IsA("Model") and model:HasTag(CarRig.TAG) then
		return model, welded
	end
	return nil, false
end

-- At the start of a frame: what was held for the last one is let go, now that the clips follow it.
function SeatHandOver.beginFrame()
	local weld, root = heldWeld, heldRoot
	heldWeld, heldRoot = nil, nil
	if weld then
		weld.Enabled = true
	end
	if root then
		root.Anchored = false
	end
end

-- Before physics, for a seat that changed after this frame's clips were chosen. A weld that
-- arrived (`posed` false) would move the root into the seat with the body still posed standing:
-- it is held off for the frame. Getting out of `leaving`, a weld that went would let the root
-- move under the seated clips (measured: the torso 1.1 studs off for a frame): the root is held.
function SeatHandOver.guardFrame(current: Body, posed: boolean, entering: Model?, leaving: Model?)
	if not posed then
		local seat = seatOf(current, entering)
		local weld = seat and seat:FindFirstChild("SeatWeld")
		if weld and weld:IsA("Weld") and weld.Part1 == current.root and weld.Enabled then
			weld.Enabled = false
			heldWeld = weld
		end
		return
	end
	local seat = if leaving then leaving:FindFirstChild("DriverSeat") else nil
	local root = current.root
	if seat and seat:IsA("BasePart") and not weldHolds(current, seat) and not root.Anchored then
		root.Anchored = true
		heldRoot = root
	end
end

-- On foot, HeadLook turns the head toward the camera, and the turned head's box reaches past the
-- car's collision box from the door mark (measured: 0.53 studs inside it, pushing the body 0.48
-- off the mark; the torso clears it by 0.16). So the head stops colliding, on this client, from
-- the walk to the door until the body is clear of the car again.
function SeatHandOver.headClear(current: Body, clear: boolean)
	local head = current.character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		head.CanCollide = not clear
	end
end

-- Puts the body standing at the end of getting out, on the ground, still.
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
	local untilClock = if placedOut then placedOut.untilClock else os.clock() + HOLD_OUT
	placedOut = { car = car, at = current.root.Position, untilClock = untilClock }
	lastScale = scale
end

-- The server changes the body's size about its root (Services/CarEntry), which leaves the feet
-- in or above the ground: the root is set back above the ground for the new size.
local function plantFeet(current: Body, scale: number)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { current.character }
	local root = current.root
	local hit = Workspace:Raycast(root.Position, Vector3.new(0, -2 * ROOT_HEIGHT, 0), params)
	if hit then
		root.CFrame += Vector3.new(0, hit.Position.Y + ROOT_HEIGHT * scale - root.Position.Y, 0)
	end
end

-- The first frame off the seat after getting out. The server lets go of the body, but this client
-- owns its physics and finds the root where the seat left it, inside the car: the server's own
-- placement does not take (measured: then pushed 3.7 studs out). And Locomotion's idle only
-- starts after this frame's animation, so Roblox's sit, under the exit clip all along, would
-- show for a frame and blend out (measured: a leg 2.5 studs off): a copy of the idle holds the
-- body for that frame.
function SeatHandOver.standUp(current: Body, car: Model)
	placedOut = nil
	placeOut(current, car)
	SeatHandOver.headClear(current, false)
	for _, track in current.clips.animator:GetPlayingAnimationTracks() do
		local animation = track.Animation
		if animation and animation.AnimationId == SIT then
			track:Stop(0)
		end
	end
	-- An exit clip still fading would pose the body against the root's new place.
	ClipPlayer.stopAll(current.clips)
	ClipPlayer.set(current.clips, IDLE, nil, 0)
	standingUp = true
end

-- Every standing frame: the feet are planted again in the frame a new size arrives, and for a
-- moment after getting out, a late write from the server that moves the body while the player
-- is not moving it puts it back where it was placed.
function SeatHandOver.keepStanding(current: Body)
	local out = placedOut
	if out and (os.clock() > out.untilClock or current.humanoid.MoveDirection.Magnitude > 0.1) then
		placedOut, out = nil, nil
	end
	local scale = current.character:GetScale()
	local resized = lastScale ~= nil and scale ~= lastScale
	lastScale = scale
	if out and (resized or flat(current.root.Position - out.at).Magnitude > MOVED) then
		placeOut(current, out.car)
	elseif resized then
		plantFeet(current, scale)
	end
end

-- Off the seat a held exit clip ends at once: the body is where the clip showed it. The idle
-- copy of a stand-up fades out as Locomotion's own fades in.
function SeatHandOver.clearStanding(current: Body)
	ClipPlayer.set(current.clips, nil, nil, if standingUp then Movement.FADE else 0)
	standingUp = false
end

function SeatHandOver.reset()
	heldWeld, heldRoot, placedOut, standingUp, lastScale = nil, nil, nil, false, nil
end

return table.freeze(SeatHandOver)
