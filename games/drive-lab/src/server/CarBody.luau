--!strict
--[[
	The player's body on the server as it changes hands with a car's seat, for Services/CarEntry:
	where its root goes, its size, and whether it goes through cars' collision boxes. The client
	owns the body's physics, so a placement made here does not take there on its own (measured in
	Play); what is done here keeps this server's view of the body from moving the client's or
	the car.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CarRig = require(ReplicatedStorage.Shared.Car.CarRig)

-- R6 standing: two studs of leg and half the torso under the root's centre, times the scale.
local ROOT_HEIGHT = 3
local SCALE_EPSILON = 1e-3
-- Seconds a body that left a seat goes through the car's box here past a round trip, and at most;
-- how often it is checked for being clear; studs past the box that count as clear of it.
local LEAVE_THROUGH_SECONDS = 0.5
local LEAVE_THROUGH_LONGEST = 5
local THROUGH_POLL = 0.1
local CLEAR_OF_BOX = 1

-- The bodies going through cars' boxes on this server, each with the token of the call that set it.
local throughFor: { [Model]: {} } = {}

local CarBody = {}

-- Moves the character so its root lands on `frame`. Its pivot is not its root (an R6 player
-- character pivots on its head, measured in Play).
local function placeRoot(character: Model, root: BasePart, frame: CFrame)
	character:PivotTo(frame * root.CFrame:ToObjectSpace(character:GetPivot()))
end

-- Scales about the root, which keeps its place. Scaling about the character's own pivot (an R6
-- player's head) moves the root, and that write reaches the client that owns the body, from this
-- server's late view of it (measured in Play: pulled back 0.45 to 4 studs). The client plants the
-- feet again when the size arrives (Controllers/SeatHandOver).
function CarBody.scaleAboutRoot(character: Model, root: BasePart, to: number)
	if math.abs(character:GetScale() - to) <= SCALE_EPSILON then
		return
	end
	local primary = character.PrimaryPart
	character.PrimaryPart = root
	character:ScaleTo(to)
	character.PrimaryPart = primary
end

-- The root's frame standing on the ground under `spot`, beside `car`.
local function standingFrame(car: Model, spot: CFrame, scale: number): CFrame
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { car }
	-- Passes through characters, as the wheels' rays do.
	params.CollisionGroup = CarRig.RAY_GROUP
	local hit = Workspace:Raycast(spot.Position + Vector3.new(0, 4, 0), Vector3.new(0, -30, 0), params)
	local height = if hit then hit.Position.Y + ROOT_HEIGHT * scale else spot.Position.Y
	return spot.Rotation + Vector3.new(spot.Position.X, height, spot.Position.Z)
end

-- Gives the body standing on `spot` the size `to`. This server's view of the root may be behind
-- the client's (measured: 0.45 studs on the mark; still in the seat getting out) and a size change
-- writes the body from that view to the client, so the root is put on `spot` first, then scaled
-- about, then set at the new size's height, where the client puts it too.
function CarBody.resizeOn(car: Model, character: Model, root: BasePart, spot: CFrame, to: number)
	placeRoot(character, root, standingFrame(car, spot, character:GetScale()))
	CarBody.scaleAboutRoot(character, root, to)
	placeRoot(character, root, standingFrame(car, spot, to))
end

local function collisionGroup(character: Model, group: string)
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = group
		end
	end
end

-- On this server the body goes through cars' collision boxes (CarRig.DOOR_GROUP) for `seconds`,
-- then for as long as `clear` says it is not out yet, up to `longest`; a later call for the same
-- body takes over. Its client sets its own view of the body itself (Controllers/SeatHandOver).
function CarBody.passThrough(character: Model, seconds: number, clear: (() -> boolean)?, longest: number?)
	local token = {}
	throughFor[character] = token
	collisionGroup(character, CarRig.DOOR_GROUP)
	task.spawn(function()
		local started = os.clock()
		while character.Parent ~= nil and throughFor[character] == token do
			local elapsed = os.clock() - started
			if elapsed >= (longest or seconds) or (elapsed >= seconds and (clear == nil or clear())) then
				break
			end
			task.wait(THROUGH_POLL)
		end
		if throughFor[character] == token then
			throughFor[character] = nil
			if character.Parent ~= nil then
				collisionGroup(character, CarRig.CHARACTER_GROUP)
			end
		end
	end)
end

-- The body has left `car`'s seat. This server still poses it from the seated clips for a few
-- frames, and the body its client sends stays in the seat until that client's own placement
-- outside arrives, a round trip later: both put the torso inside the car's box, and this server,
-- which moves the parked car again, throws the car off it (measured: lifted 1.56 studs with the
-- body placed out in the same step, 9.5 studs and rolled 76 degrees with it left in the seat). So
-- the body goes through the box for a round trip and more, then until this server sees it clear.
function CarBody.leaveSeat(car: Model, player: Player?, character: Model)
	local hull = car:FindFirstChild("Hull")
	local function outside(name: string): boolean
		local part = character:FindFirstChild(name)
		if hull == nil or not hull:IsA("BasePart") or part == nil or not part:IsA("BasePart") then
			return true
		end
		local at = hull.CFrame:PointToObjectSpace(part.Position)
		return math.abs(at.X) > hull.Size.X / 2 + CLEAR_OF_BOX
			or math.abs(at.Z) > hull.Size.Z / 2 + CLEAR_OF_BOX
	end
	local roundTrip = if player then 2 * player:GetNetworkPing() else 0
	CarBody.passThrough(character, LEAVE_THROUGH_SECONDS + roundTrip, function(): boolean
		return outside("HumanoidRootPart") and outside("Torso")
	end, LEAVE_THROUGH_LONGEST)
end

return table.freeze(CarBody)
