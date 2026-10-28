--!strict
--[[
	The driver's door and the START flap of every car on this client, turned from the car's
	replicated entry state and the server's clock (Rules/CarEntry), so every client shows the
	same door at the same moment, late joiners too. The door's latch and shut sound from its outer
	panel. The door's pull strap turns with it, hanging, or runs to the driver's animated palm
	while a clip closes the door by it (Rules/DoorStrap). Writes nothing but the two hinge welds'
	C0, the strap weld's C0 and its part's Size, and the sounds it plays.
]]
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CarEntry = require(ReplicatedStorage.Shared.Config.CarEntry)
local CarRig = require(ReplicatedStorage.Shared.Car.CarRig)
local CarState = require(ReplicatedStorage.Shared.Car.CarState)
local Catalog = require(ReplicatedStorage.Shared.Config.Cars.Catalog)
local Config = require(ReplicatedStorage.Shared.Config.CarDoor)
local Entry = require(ReplicatedStorage.Shared.Rules.CarEntry)
local DoorStrap = require(ReplicatedStorage.Shared.Rules.DoorStrap)
local Hinge = require(ReplicatedStorage.Shared.Rules.Hinge)
local SVJModel = require(ReplicatedStorage.Shared.Config.Cars.SVJModel)
local Units = require(ReplicatedStorage.Shared.Units)

-- The strap in the chassis's space, in studs: where it is sewn and the card's facing with the
-- door shut, the hinge it turns about, and what was last written.
type Strap = {
	weld: Weld,
	part: BasePart,
	top: Hinge.Vector,
	facing: Hinge.Vector,
	pivot: Hinge.Vector,
	axis: Hinge.Vector,
	shape: DoorStrap.Shape,
	grab: number,
	width: number,
	thickness: number,
	-- The last pose written: its far end and length; nil before the first.
	tip: Vector3?,
	length: number,
}

type Car = {
	rig: CarRig.Rig,
	openAngle: number,
	panel: BasePart?,
	doorAngle: number,
	flapAngle: number,
	-- The door's openness Config.LEAD seconds ahead at the last frame; nil before the first.
	ahead: number?,
	strap: Strap?,
}

-- Seconds between looks for cars whose door has not streamed in yet.
local SCAN_SECONDS = 1
-- Seconds a one-shot outlives its region before it is removed anyway.
local SOUND_GRACE = 0.5

local cars: { [Model]: Car } = {}
local sinceScan = math.huge

local function chassisPoint(point: Hinge.CarPoint, raise: number): Hinge.Vector
	local v = Hinge.chassis({ forward = point.forward, right = point.right, up = point.up + raise })
	return { x = Units.metresToStuds(v.x), y = Units.metresToStuds(v.y), z = Units.metresToStuds(v.z) }
end

local function strapOf(rig: CarRig.Rig, binding: SVJModel.CarModel): Strap?
	local door = binding.door
	local strap = door and door.strap
	local weld = rig.strap
	local part = weld and weld.Part1
	if door == nil or strap == nil or weld == nil or part == nil then
		return nil
	end
	local hang = table.create(#strap.hang)
	for index, row in strap.hang do
		hang[index] = { angle = row.angle, length = Units.metresToStuds(row.length) }
	end
	return {
		weld = weld,
		part = part,
		top = chassisPoint(strap.top, binding.bodyRaise),
		facing = Hinge.chassis(strap.facing),
		pivot = chassisPoint(door.pivot, binding.bodyRaise),
		axis = Hinge.chassis(door.axis),
		shape = { length = Units.metresToStuds(strap.length), lean = strap.lean, hang = hang },
		grab = strap.grab,
		width = part.Size.X,
		thickness = part.Size.Z,
		tip = nil,
		length = part.Size.Y,
	}
end

local function track(model: Instance)
	if not model:IsA("Model") or cars[model] then
		return
	end
	local name = model:GetAttribute("Car")
	local entry = if typeof(name) == "string" then Catalog[name] else nil
	local binding = entry and entry.model
	if binding == nil or (binding.door == nil and binding.flap == nil) then
		return
	end
	local rig = CarRig.find(model, binding)
	-- A car whose door or flap has not streamed in yet is picked up on a later scan.
	if rig == nil or (binding.door and rig.door == nil) or (binding.flap and rig.flap == nil) then
		return
	end
	-- The server rigged a strap whose part has not streamed in yet: picked up on a later scan.
	if
		binding.door
		and binding.door.strap
		and rig.strap == nil
		and rig.chassis:FindFirstChild(CarRig.STRAP_WELD)
	then
		return
	end
	local panel = if binding.door then model:FindFirstChild(binding.door.parts[1], true) else nil
	cars[model] = {
		rig = rig,
		openAngle = if binding.door then binding.door.openAngle else 0,
		panel = if panel and panel:IsA("BasePart") then panel else nil,
		doorAngle = 0,
		flapAngle = 0,
		ahead = nil,
		strap = strapOf(rig, binding),
	}
end

local function play(panel: BasePart, region: Config.Region)
	local sound = Instance.new("Sound")
	sound.Name = "DoorSound"
	sound.SoundId = Config.SOUND_ID
	sound.PlaybackRegionsEnabled = true
	sound.PlaybackRegion = NumberRange.new(region.from, region.to)
	sound.Volume = Config.VOLUME
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = Config.ROLL_OFF.from
	sound.RollOffMaxDistance = Config.ROLL_OFF.to
	sound.Parent = panel
	sound:Play()
	local function remove()
		sound:Destroy()
	end
	sound.Ended:Once(remove)
	task.delay(region.to - region.from + SOUND_GRACE, remove)
end

local function poseDoor(car: Car, door: Weld, state: Entry.State, now: number)
	local angle = Hinge.angle(Entry.doorOpenness(state, now), car.openAngle)
	if angle ~= car.doorAngle then
		door.C0 = car.rig.doorRest * CFrame.Angles(angle, 0, 0)
		car.doorAngle = angle
	end
	local ahead = Entry.doorOpenness(state, now + Config.LEAD)
	local sound = if car.ahead ~= nil then Hinge.sound(car.ahead, ahead) else nil
	car.ahead = ahead
	if sound and car.panel and Config.SOUND_ID ~= "" then
		play(car.panel, if sound == "Latch" then Config.LATCH else Config.SHUT)
	end
end

-- The driver's animated palm in the chassis's space, while a character sits in the seat.
local function palmOf(rig: CarRig.Rig): Hinge.Vector?
	local occupant = rig.seat.Occupant
	local character = occupant and occupant.Parent
	local arm = character and character:FindFirstChild(Config.STRAP.ARM)
	if arm == nil or not arm:IsA("BasePart") then
		return nil
	end
	local offset = Config.STRAP.PALM * arm.Size
	local palm = rig.chassis.CFrame:PointToObjectSpace(arm.CFrame:PointToWorldSpace(offset))
	return { x = palm.X, y = palm.Y, z = palm.Z }
end

local function vector(v: Hinge.Vector): Vector3
	return Vector3.new(v.x, v.y, v.z)
end

local function poseStrap(car: Car, strap: Strap, state: Entry.State, now: number)
	local angle = car.doorAngle
	local palm = if DoorStrap.held(DoorStrap.clip(state, now), angle, strap.grab)
		then palmOf(car.rig)
		else nil
	local top = Hinge.rotate(strap.top, strap.pivot, strap.axis, angle)
	local facing = Hinge.rotate(strap.facing, { x = 0, y = 0, z = 0 }, strap.axis, angle)
	local pose = DoorStrap.pose(strap.shape, top, facing, angle, palm)
	local from = vector(top)
	local down = vector(pose.direction)
	local tip = from + down * pose.length
	local epsilon = Config.STRAP.EPSILON
	if
		strap.tip
		and (tip - strap.tip).Magnitude < epsilon
		and math.abs(pose.length - strap.length) < epsilon
	then
		return
	end
	-- The part's -Y runs down the strap and its Z (the faces' normal) is as near the card's facing
	-- as that allows, as tools/blender/hero_car_door_strap.py builds it.
	local up = -down
	local out = vector(facing)
	out = out - up * out:Dot(up)
	if out.Magnitude < 1e-6 then
		out = up:Cross(Vector3.xAxis)
	end
	out = out.Unit
	strap.weld.C0 = CFrame.fromMatrix(from + down * (pose.length / 2), up:Cross(out), up, out)
	if math.abs(pose.length - strap.length) >= epsilon or strap.tip == nil then
		strap.part.Size = Vector3.new(strap.width, pose.length, strap.thickness)
		strap.length = pose.length
	end
	strap.tip = tip
end

local function poseFlap(car: Car, flap: Weld, state: Entry.State, now: number)
	local angle = Hinge.angle(Entry.flapOpenness(state, now), CarEntry.STARTUP.flapAngle)
	if angle ~= car.flapAngle then
		flap.C0 = car.rig.flapRest * CFrame.Angles(angle, 0, 0)
		car.flapAngle = angle
	end
end

local function update(dt: number)
	sinceScan += dt
	if sinceScan >= SCAN_SECONDS then
		sinceScan = 0
		for _, model in CollectionService:GetTagged(CarRig.TAG) do
			track(model)
		end
	end
	local now = Workspace:GetServerTimeNow()
	for model, car in cars do
		if model.Parent == nil or car.rig.chassis.Parent == nil then
			cars[model] = nil
			continue
		end
		local state = CarState.read(model)
		local door, flap = car.rig.door, car.rig.flap
		if door then
			poseDoor(car, door, state, now)
		end
		if car.strap then
			poseStrap(car, car.strap, state, now)
		end
		if flap then
			poseFlap(car, flap, state, now)
		end
	end
end

local Controller = {}

function Controller.start()
	CollectionService:GetInstanceAddedSignal(CarRig.TAG):Connect(track)
	-- Before the frame is drawn, so the door and the hand that holds it move in the same frame.
	RunService.PreRender:Connect(update)
end

return Controller
