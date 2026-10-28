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
local placedOut: { car: Model, at: Vector3, scale: number, untilClock: number }? = nil
local standingUp = false

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

-- The car whose seat holds the body: its seat weld holds the root, or, getting into `entering` or
-- with the humanoid already told it sits, the server has put the root in the seat before the weld
-- reached this client (measured: the body drawn in the seat for a frame, 5 studs from where the
-- clip shows it).
function SeatHandOver.seatedIn(current: Body, entering: Model?): Model?
	local seat = seatOf(current, entering)
	if seat == nil then
		return nil
	end
	local weld = seat:FindFirstChild("SeatWeld")
	local welded = weld ~= nil and weld:IsA("Weld") and weld.Part1 == current.root
	local seating = entering ~= nil or current.humanoid.SeatPart == seat
	local carried = seating and flat(current.root.Position - seat.Position).Magnitude < IN_SEAT
	if not welded and not carried then
		return nil
	end
	local model = seat.Parent
	return if model and model:IsA("Model") and model:HasTag(CarRig.TAG) then model else nil
end

-- At the start of a frame: a weld held off last frame takes the root again, now that the clips
-- follow it.
function SeatHandOver.beginFrame()
	local weld = heldWeld
	if weld then
		heldWeld = nil
		weld.Enabled = true
	end
end

-- Before physics: a seat weld that arrived after this frame's clips were chosen (`posed` false)
-- would move the root into the seat with the body still posed standing. Held off for the frame.
function SeatHandOver.holdLateWeld(current: Body, posed: boolean, entering: Model?)
	if posed then
		return
	end
	local seat = seatOf(current, entering)
	local weld = seat and seat:FindFirstChild("SeatWeld")
	if weld and weld:IsA("Weld") and weld.Part1 == current.root and weld.Enabled then
		weld.Enabled = false
		heldWeld = weld
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
	placedOut = { car = car, at = current.root.Position, scale = scale, untilClock = untilClock }
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
	ClipPlayer.set(current.clips, IDLE, nil, 0)
	standingUp = true
end

-- Every standing frame: for a moment after getting out, a late size change or a late write from
-- the server that moves the body, while the player is not moving it, puts it back.
function SeatHandOver.keepOut(current: Body)
	local out = placedOut
	if out == nil then
		return
	end
	if os.clock() > out.untilClock or current.humanoid.MoveDirection.Magnitude > 0.1 then
		placedOut = nil
		return
	end
	local moved = flat(current.root.Position - out.at).Magnitude > MOVED
	if moved or current.character:GetScale() ~= out.scale then
		placeOut(current, out.car)
	end
end

-- Off the seat a held exit clip ends at once: the body is where the clip showed it. The idle
-- copy of a stand-up fades out as Locomotion's own fades in.
function SeatHandOver.clearStanding(current: Body)
	ClipPlayer.set(current.clips, nil, nil, if standingUp then Movement.FADE else 0)
	standingUp = false
end

function SeatHandOver.reset()
	heldWeld, placedOut, standingUp = nil, nil, false
end

return table.freeze(SeatHandOver)
