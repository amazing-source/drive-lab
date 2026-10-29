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
local Driving = require(ReplicatedStorage.Shared.Config.Driving)
local Movement = require(ReplicatedStorage.Shared.Config.Movement)

local ClipPlayer = require(script.Parent.Parent.Rig.ClipPlayer)

export type Body = { character: Model, humanoid: Humanoid, root: BasePart, clips: ClipPlayer.ClipPlayer }
-- How the body collides with a car's collision box: as any character, its head going through
-- (at the door), or all of it going through (in the seat).
export type Collision = "Free" | "AtDoor" | "Seated"

-- R6 standing: the root's centre three studs above the feet, times the scale.
local ROOT_HEIGHT = 3
-- Seconds after getting out during which the body is put back where it was placed if something
-- other than the player moves it.
local HOLD_OUT = 0.6
-- Studs in one frame toward the seat, getting in before the weld: more than a walk covers, so
-- the server moved the root.
local DISPLACED = 0.6
local MOVED = 0.05
local SCALE_EPSILON = 1e-4
-- Studs past the car's box that count as clear of it, and seconds at most a body the seat let go of
-- goes through the box (as CarBody on the server).
local CLEAR_OF_BOX = 1
local LEFT_SEAT_THROUGH = 2
local SIT, IDLE = Movement.ANIMATIONS.sit.id, Movement.ANIMATIONS.idle.id

local heldWeld: Weld? = nil
local heldRoot: BasePart? = nil
local placedOut: { car: Model, at: Vector3, untilClock: number }? = nil
local standingUp = false
-- The body's size last standing frame: a change plants the feet again.
local lastScale: number? = nil
-- Where the root stood last standing frame, and whether it is held there for the seat's weld.
local lastStanding: CFrame? = nil
local holding = false
-- The car whose seat last held the body, and when.
local leftCar: Model? = nil
local leftAt = 0

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

-- The car whose seat's weld holds the body.
function SeatHandOver.seatedIn(current: Body, entering: Model?): Model?
	local seat = seatOf(current, entering)
	local model = seat and seat.Parent
	if seat and weldHolds(current, seat) and model and model:IsA("Model") and model:HasTag(CarRig.TAG) then
		return model
	end
	return nil
end

-- Getting into `entering`, before this client has the seat's weld. The server seats the body and
-- the root's new place can reach this client first, in the seat or part way there (measured: 3.9
-- studs in, with no weld and the full size, so no pose matched it): the root is put back where it
-- stood, posed standing, every frame until the weld arrives and the seated clips take it. It is
-- not anchored: a weld that joins an anchored root pulls the car to it (measured: 8.7 studs).
-- True while it holds.
function SeatHandOver.holdForSeat(current: Body, entering: Model?): boolean
	local root, spot = current.root, lastStanding
	local seat = entering and entering:FindFirstChild("DriverSeat")
	if spot and seat and seat:IsA("BasePart") and not weldHolds(current, seat) then
		local towardSeat = flat(spot.Position - seat.Position).Magnitude
			- flat(root.Position - seat.Position).Magnitude
		if holding or towardSeat > DISPLACED then
			holding = true
			root.CFrame = spot
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			local scale = current.character:GetScale()
			if lastScale ~= nil and scale ~= lastScale then
				plantFeet(current, scale)
				lastScale = scale
				lastStanding = root.CFrame
			end
			return true
		end
	else
		holding = false
	end
	return false
end

-- Seated after getting in, the body has the driver's size. The server sets it before the seat's
-- weld, and should the weld reach this client first the size is set here too, about the root as
-- the server sets it: the seated clips hold the torso up to 5 studs from the root, so at the
-- wrong size it would be drawn up to 0.9 studs off (measured: 0.76 with the size a frame late).
function SeatHandOver.seatedSize(current: Body)
	local character = current.character
	if math.abs(character:GetScale() - Driving.DRIVER_SCALE) <= SCALE_EPSILON then
		return
	end
	local primary = character.PrimaryPart
	character.PrimaryPart = current.root
	character:ScaleTo(Driving.DRIVER_SCALE)
	character.PrimaryPart = primary
end

-- At the start of a frame: what was held for the last one is let go, now that the clips follow it.
-- The root first: a weld enabled on an anchored root would pull the car to it.
function SeatHandOver.beginFrame()
	local weld, root = heldWeld, heldRoot
	heldWeld, heldRoot = nil, nil
	if root then
		root.Anchored = false
	end
	if weld then
		weld.Enabled = true
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

local function clearOfBox(current: Body, car: Model): boolean
	local hull = car:FindFirstChild("Hull")
	if hull == nil or not hull:IsA("BasePart") then
		return true
	end
	for _, name in { "HumanoidRootPart", "Torso" } do
		local part = current.character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			local at = hull.CFrame:PointToObjectSpace(part.Position)
			if
				math.abs(at.X) <= hull.Size.X / 2 + CLEAR_OF_BOX
				and math.abs(at.Z) <= hull.Size.Z / 2 + CLEAR_OF_BOX
			then
				return false
			end
		end
	end
	return true
end

-- How the body collides this frame. `car`: the car whose seat holds it. A body the seat let go of
-- other than by getting out is still inside the car's box, and while this client still moves the
-- car it threw the car off the body (measured: 1 to 1.8 studs up): it goes through the box until
-- it is clear of it, for LEFT_SEAT_THROUGH seconds at most.
function SeatHandOver.collision(current: Body, car: Model?, atDoor: boolean): Collision
	if car then
		leftCar, leftAt = car, os.clock()
		return "Seated"
	end
	local left = leftCar
	if left and os.clock() - leftAt < LEFT_SEAT_THROUGH and not clearOfBox(current, left) then
		return "Seated"
	end
	leftCar = nil
	return if atDoor then "AtDoor" else "Free"
end

-- On foot, HeadLook turns the head toward the camera, and from the door mark the turned head's box
-- reaches into the car's collision box (measured: 0.53 studs, pushing the body 0.47 off the mark;
-- the torso clears it by 0.15). The Humanoid sets the head colliding again every frame (measured),
-- so it goes through the box by its collision group instead, from the walk to the door until the
-- body is free again. In the seat the torso is inside the box too: there the whole body goes
-- through it, so the frame the seat lets go of it pushes nothing.
-- Every frame, part by part: the server sets these groups on its own view of the body too
-- (CarBody), and its writes reach this client.
function SeatHandOver.collide(current: Body, mode: Collision)
	for _, part in current.character:GetChildren() do
		if part:IsA("BasePart") then
			local through = mode == "Seated" or (mode == "AtDoor" and part.Name == "Head")
			local group = if through then CarRig.DOOR_GROUP else CarRig.CHARACTER_GROUP
			if part.CollisionGroup ~= group then
				part.CollisionGroup = group
			end
		end
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

-- The first frame off the seat after getting out. The server lets go of the body, but this client
-- owns its physics and finds the root where the seat left it, inside the car: the server's own
-- placement does not take (measured: then pushed 3.7 studs out). And Locomotion's idle only
-- starts after this frame's animation, so Roblox's sit, under the exit clip all along, would
-- show for a frame and blend out (measured: a leg 2.5 studs off): a copy of the idle holds the
-- body for that frame.
function SeatHandOver.standUp(current: Body, car: Model)
	placedOut = nil
	placeOut(current, car)
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
	lastStanding = current.root.CFrame
end

-- Off the seat a held exit clip ends at once: the body is where the clip showed it. The idle
-- copy of a stand-up fades out as Locomotion's own fades in.
function SeatHandOver.clearStanding(current: Body)
	ClipPlayer.set(current.clips, nil, nil, if standingUp then Movement.FADE else 0)
	standingUp = false
end

function SeatHandOver.reset()
	heldWeld, heldRoot, placedOut, standingUp, lastScale = nil, nil, nil, false, nil
	lastStanding, holding, leftCar = nil, false, nil
end

return table.freeze(SeatHandOver)
