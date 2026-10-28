--!strict
--[[
	Turns an imported car model into a physical one, and finds the pieces again on any side.

	The whole mass sits in one invisible box at the centre of mass, sized so Roblox's inertia
	for it equals the config's yaw, pitch and roll inertia; every visible part is welded on
	massless. The vehicle model predicts the chassis inside each frame from config.mass and
	yawInertia, so the engine's body has to agree with them. Wheels and calipers hang on Welds
	whose C0 the runner moves; the suspension itself is forces, not constraints.
]]
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Geometry = require("../Vehicle/Geometry")
local SVJModel = require("../Config/Cars/SVJModel")
local Types = require("../Config/Cars/Types")
local Units = require("../Units")

export type Rig = {
	model: Model,
	chassis: BasePart,
	-- Top of each wheel's travel, Geometry order.
	mounts: { Attachment },
	force: VectorForce,
	torque: Torque,
	wheels: { Weld },
	calipers: { { Weld } },
	-- Each weld's C0 at design ride height, straight ahead.
	wheelRest: { CFrame },
	caliperRest: { { CFrame } },
	-- Turns about its C0's Z axis (the column, toward the driver); nil on a model without one.
	steeringWheel: Weld?,
	steeringWheelRest: CFrame,
	seat: Seat,
	prompt: ProximityPrompt,
}

local TAG = "DriveLabCar"

local CarRig = {
	TAG = TAG,
	-- Wheel rays travel in RAY_GROUP, which the server makes pass through CHARACTER_GROUP.
	RAY_GROUP = "DriveLabWheelRays",
	CHARACTER_GROUP = "DriveLabCharacters",
}

-- Box edges (studs) whose solid-box inertia matches the car's: I = m (a^2 + b^2) / 12.
local function inertiaBox(car: Types.CarConfig): Vector3
	local function squared(sum: number, other: number): number
		return math.max(0.01, sum - other)
	end
	local yaw, pitch, roll =
		12 * car.yawInertia / car.mass, 12 * car.pitchInertia / car.mass, 12 * car.rollInertia / car.mass
	local half = (yaw + pitch + roll) / 2
	-- Car axes: width (right), height (up), length (forward). Yaw spins about up, so it
	-- involves width and length; pitch about right (height, length); roll about forward.
	local width = math.sqrt(squared(half, pitch))
	local height = math.sqrt(squared(half, yaw))
	local length = math.sqrt(squared(half, roll))
	return Vector3.new(Units.metresToStuds(width), Units.metresToStuds(height), Units.metresToStuds(length))
end

local function carSpace(position: { forward: number, right: number }, up: number): Vector3
	return Vector3.new(
		Units.metresToStuds(position.right),
		Units.metresToStuds(up),
		-Units.metresToStuds(position.forward)
	)
end

local function findPart(model: Model, name: string): BasePart
	local part = model:FindFirstChild(name, true)
	assert(part and part:IsA("BasePart"), `{model:GetFullName()} has no part named {name}`)
	return part
end

local function newPart(className: string, name: string, size: Vector3, cframe: CFrame): BasePart
	local part = Instance.new(className) :: BasePart
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	return part
end

local function weld(part0: BasePart, part1: BasePart): Weld
	local joint = Instance.new("Weld")
	joint.Name = part1.Name
	joint.Part0 = part0
	joint.Part1 = part1
	joint.C0 = part0.CFrame:ToObjectSpace(part1.CFrame)
	joint:SetAttribute("RestC0", joint.C0)
	joint.Parent = part0
	return joint
end

-- Imports are real scale; the world is Units.WORLD_SCALE times bigger. Scales the model to it and
-- sets the tyres back on whatever is under the car.
local function scaleToWorld(model: Model, binding: SVJModel.CarModel)
	if math.abs(model:GetScale() - Units.WORLD_SCALE) > 1e-3 then
		model:ScaleTo(Units.WORLD_SCALE)
	end
	local frame, size = model:GetBoundingBox()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model }
	local floor = Workspace:Raycast(frame.Position, Vector3.new(0, -(size.Y + 50), 0), params)
	if floor == nil then
		return
	end
	local lowest = math.huge
	for _, name in binding.wheels do
		local wheel = findPart(model, name)
		lowest = math.min(lowest, wheel.Position.Y - wheel.Size.Y / 2)
	end
	model:PivotTo(model:GetPivot() + Vector3.new(0, floor.Position.Y - lowest, 0))
end

-- Lifts every part but the wheels and calipers off the wheels, where the model sits its body
-- too low; the wheels stay on the ground, so the physics is unchanged.
local function raiseBody(model: Model, binding: SVJModel.CarModel)
	local lift = Vector3.new(0, Units.metresToStuds(binding.bodyRaise), 0)
	local fixed: { [BasePart]: true } = {}
	for index, name in binding.wheels do
		fixed[findPart(model, name)] = true
		for _, caliper in binding.calipers[index] do
			fixed[findPart(model, caliper)] = true
		end
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and not fixed[part] then
			part.CFrame += lift
		end
	end
end

-- The steering wheel hangs on a Weld whose C0 is its pivot, the column axis, in chassis space;
-- C1 is the pivot in the part's own space, so turning C0 about its Z turns the wheel in place.
local function weldSteeringWheel(chassis: BasePart, wheel: BasePart, lift: number)
	local joint = Instance.new("Weld")
	joint.Name = wheel.Name
	joint.Part0 = chassis
	joint.Part1 = wheel
	-- Raised along the car's up, the column's adjustment; the hands follow the rest pose.
	joint.C0 = CFrame.new(0, Units.metresToStuds(lift), 0) * chassis.CFrame:ToObjectSpace(wheel:GetPivot())
	joint.C1 = wheel.PivotOffset
	joint:SetAttribute("RestC0", joint.C0)
	joint.Parent = chassis
end

local function rigFrame(model: Model, binding: SVJModel.CarModel, car: Types.CarConfig): (CFrame, number)
	local wheels = table.create(4)
	for index, name in binding.wheels do
		wheels[index] = findPart(model, name)
	end
	local front = (wheels[1].Position + wheels[2].Position) / 2
	local rear = (wheels[3].Position + wheels[4].Position) / 2
	local ground = 0
	for _, wheel in wheels do
		ground += (wheel.Position.Y - wheel.Size.Y / 2) / 4
	end
	local forward = Vector3.new(front.X - rear.X, 0, front.Z - rear.Z).Unit
	local along = rear + (front - rear) * car.frontWeightShare
	local centre = Vector3.new(along.X, ground + Units.metresToStuds(car.cgHeight), along.Z)
	local wheelbase = Units.studsToMetres((front - rear).Magnitude)
	assert(
		math.abs(wheelbase - car.wheelbase) < 0.05,
		`{model.Name}: modelled wheelbase {wheelbase} m, config {car.wheelbase} m`
	)
	return CFrame.lookAt(centre, centre + forward, Vector3.yAxis), ground
end

local function addMounts(chassis: BasePart, car: Types.CarConfig): { Attachment }
	local mounts = table.create(4)
	local travel = car.suspension.travel
	for wheel, position in Geometry.wheelPositions(car) do
		-- The wheel centre sits one rolling radius up at design ride height; the mount is the
		-- top of its travel, (travel - static compression) above that.
		local radius = Geometry.axle(car, wheel).tyre.radius
		local up = radius - car.cgHeight + (travel - car.suspension.staticCompression)
		local mount = Instance.new("Attachment")
		mount.Name = `Mount{wheel}`
		mount.Position = carSpace(position, up)
		mount.Parent = chassis
		mounts[wheel] = mount
	end
	return mounts
end

local function addHull(model: Model, chassis: BasePart, ground: number, clearance: number)
	local frame, size = model:GetBoundingBox()
	local bottom = ground + Units.metresToStuds(clearance)
	local top = frame.Position.Y + size.Y / 2
	local centre = chassis.CFrame:PointToObjectSpace(frame.Position)
	local hull = newPart(
		"Part",
		"Hull",
		Vector3.new(size.X, top - bottom, size.Z),
		chassis.CFrame * CFrame.new(centre.X, (top + bottom) / 2 - chassis.Position.Y, centre.Z)
	)
	hull.CanCollide = true
	hull.Massless = true
	hull.Parent = model
	weld(chassis, hull)
end

local function addSeat(model: Model, chassis: BasePart, binding: SVJModel.CarModel): (Seat, ProximityPrompt)
	-- The seat rides with the raised body.
	local offset = carSpace(binding.seat, binding.seat.up + binding.bodyRaise)
	local seat =
		newPart("Seat", "DriverSeat", Vector3.new(1.6, 0.4, 1.6), chassis.CFrame * CFrame.new(offset)) :: Seat
	seat.Massless = true
	seat.Parent = model
	weld(chassis, seat)
	-- The door sits outboard of the seat; the prompt rides on it.
	local door = Instance.new("Attachment")
	door.Name = "DriverDoor"
	door.Position = Vector3.new(-Units.metresToStuds(0.9), 0.5, 0)
	door.Parent = seat
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Drive"
	prompt.ObjectText = model.Name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = door
	return seat, prompt
end

-- A screen over the cluster's static image, for the live display (Controllers/Cluster): a hair
-- toward the driver so it covers the image, its Back face toward the driver.
local function addClusterScreen(model: Model, chassis: BasePart, binding: SVJModel.CarModel)
	local cluster = binding.cluster
	local offset = carSpace(cluster, cluster.up + binding.bodyRaise)
		+ Vector3.new(0, 0, Units.metresToStuds(0.003))
	local screen = newPart(
		"Part",
		"ClusterScreen",
		Vector3.new(Units.metresToStuds(cluster.width), Units.metresToStuds(cluster.height), 0.05),
		chassis.CFrame * CFrame.new(offset) * CFrame.Angles(-cluster.tilt, 0, 0)
	)
	screen.Massless = true
	screen.Parent = model
	weld(chassis, screen)
end

-- Server, once per car: builds the rig in place. Returns the rig.
function CarRig.build(model: Model, car: Types.CarConfig, binding: SVJModel.CarModel): Rig
	assert(model:FindFirstChild("Chassis") == nil, `{model:GetFullName()} is already rigged`)
	scaleToWorld(model, binding)
	raiseBody(model, binding)
	local frame, ground = rigFrame(model, binding, car)
	local box = inertiaBox(car)
	local chassis = newPart("Part", "Chassis", box, frame)
	local volume = box.X * box.Y * box.Z
	chassis.CustomPhysicalProperties = PhysicalProperties.new(Units.kgToMass(car.mass) / volume, 0, 0, 0, 0)
	-- The mass box must stay the assembly's root, also once a seated character joins it.
	chassis.RootPriority = 127
	chassis.Parent = model
	model.PrimaryPart = chassis

	local centre = Instance.new("Attachment")
	centre.Name = "CentreOfMass"
	centre.Parent = chassis
	local force = Instance.new("VectorForce")
	force.Attachment0 = centre
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	force.Force = Vector3.zero
	force.Parent = chassis
	local torque = Instance.new("Torque")
	torque.Attachment0 = centre
	torque.RelativeTo = Enum.ActuatorRelativeTo.World
	torque.Torque = Vector3.zero
	torque.Parent = chassis
	addMounts(chassis, car)

	local moving: { [BasePart]: true } = {}
	local steeringWheel = model:FindFirstChild(binding.steeringWheel, true)
	if steeringWheel and steeringWheel:IsA("BasePart") then
		moving[steeringWheel] = true
		weldSteeringWheel(chassis, steeringWheel, binding.steeringWheelLift)
	end
	for index, name in binding.wheels do
		moving[findPart(model, name)] = true
		for _, caliper in binding.calipers[index] do
			moving[findPart(model, caliper)] = true
		end
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= chassis then
			part.Massless = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			if moving[part] and part ~= steeringWheel then
				weld(chassis, part)
			elseif not moving[part] then
				local joint = Instance.new("WeldConstraint")
				joint.Part0 = chassis
				joint.Part1 = part
				joint.Parent = part
			end
		end
	end
	addHull(model, chassis, ground, binding.hullClearance)
	addSeat(model, chassis, binding)
	addClusterScreen(model, chassis, binding)

	model:SetAttribute("DriverUserId", 0)
	CollectionService:AddTag(model, TAG)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end
	return CarRig.find(model, binding) :: Rig
end

-- Either side: the rig's pieces, or nil while they have not all streamed in.
function CarRig.find(model: Model, binding: SVJModel.CarModel): Rig?
	local chassis = model:FindFirstChild("Chassis")
	local seat = model:FindFirstChild("DriverSeat")
	if chassis == nil or not chassis:IsA("BasePart") or seat == nil or not seat:IsA("Seat") then
		return nil
	end
	local force = chassis:FindFirstChildOfClass("VectorForce")
	local torque = chassis:FindFirstChildOfClass("Torque")
	local door = seat:FindFirstChild("DriverDoor")
	local prompt = door and door:FindFirstChildOfClass("ProximityPrompt")
	if force == nil or torque == nil or prompt == nil then
		return nil
	end
	local mounts = table.create(4)
	local wheels, wheelRest = table.create(4), table.create(4)
	local calipers, caliperRest = table.create(4), table.create(4)
	for index, name in binding.wheels do
		local mount = chassis:FindFirstChild(`Mount{index}`)
		local wheel = chassis:FindFirstChild(name)
		local rest = wheel and wheel:GetAttribute("RestC0")
		if mount == nil or not mount:IsA("Attachment") or wheel == nil or not wheel:IsA("Weld") then
			return nil
		end
		if typeof(rest) ~= "CFrame" then
			return nil
		end
		mounts[index], wheels[index], wheelRest[index] = mount, wheel, rest
		local list, rests = {}, {}
		for _, caliperName in binding.calipers[index] do
			local caliper = chassis:FindFirstChild(caliperName)
			local caliperRestC0 = caliper and caliper:GetAttribute("RestC0")
			if caliper == nil or not caliper:IsA("Weld") or typeof(caliperRestC0) ~= "CFrame" then
				return nil
			end
			table.insert(list, caliper)
			table.insert(rests, caliperRestC0)
		end
		calipers[index], caliperRest[index] = list, rests
	end
	local steeringWeld = chassis:FindFirstChild(binding.steeringWheel)
	local steeringRest = steeringWeld and steeringWeld:GetAttribute("RestC0")
	return {
		model = model,
		chassis = chassis,
		mounts = mounts,
		force = force,
		torque = torque,
		wheels = wheels,
		calipers = calipers,
		wheelRest = wheelRest,
		caliperRest = caliperRest,
		steeringWheel = if steeringWeld
				and steeringWeld:IsA("Weld")
				and typeof(steeringRest) == "CFrame"
			then steeringWeld
			else nil,
		steeringWheelRest = if typeof(steeringRest) == "CFrame" then steeringRest else CFrame.identity,
		seat = seat,
		prompt = prompt,
	}
end

return CarRig
