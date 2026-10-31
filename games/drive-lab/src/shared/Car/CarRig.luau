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

local Binding = require("../Config/Cars/Binding")
local CarParts = require("../Rules/CarParts")
local Geometry = require("../Vehicle/Geometry")
local Hinge = require("../Rules/Hinge")
local Types = require("../Config/Cars/Types")
local Units = require("../Units")

-- A hinged part's weld, turned about its C0's X axis, and that C0 shut.
export type Hinged = { weld: Weld, rest: CFrame }

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
	-- The driver's door opens by turning its weld's C0 about its X axis (the hinge); nil on a
	-- model without one. The rest is that C0 shut.
	door: Weld?,
	doorRest: CFrame,
	-- The cabin controls, by the binding's names; one whose part has not streamed in is missing.
	controls: { [string]: Hinged },
	-- The wiper's arm, turned about its C0's X from parked; nil on a model without one or before
	-- it has streamed in.
	wiper: Hinged?,
	-- The gear lever: its weld's C0 at rest is its pivot with the chassis's axes, which
	-- Controllers/CarShifter turns and slides; nil on a model without one or before it has
	-- streamed in.
	shifter: Hinged?,
	-- The door's pull strap (Rules/DoorStrap) on its own weld from the chassis, posed by its C0
	-- (the strap's centre, its -Y down the strap) and its part's Size.Y; nil on a model without
	-- one or before it has streamed in.
	strap: Weld?,
	seat: Seat,
	prompt: ProximityPrompt,
}

local TAG = "DriveLabCar"
local DOOR_HINGE = "DoorHinge"
local DOOR_STRAP = "DoorStrap"

local CarRig = {
	TAG = TAG,
	-- The strap's weld on the chassis: present once the server has rigged a car with a strap,
	-- so a client that finds it without its part knows the part has not streamed in yet.
	STRAP_WELD = DOOR_STRAP,
	-- Wheel rays travel in RAY_GROUP, which the server makes pass through CHARACTER_GROUP.
	RAY_GROUP = "DriveLabWheelRays",
	CHARACTER_GROUP = "DriveLabCharacters",
	-- A character's colliding parts while it is at a car's door or in its seat
	-- (Controllers/SeatHandOver): as CHARACTER_GROUP, but through the Default group the car's
	-- collision box is in. The Humanoid sets the head and torso colliding every frame, so their
	-- group is what keeps them from pushing the body off the door mark or the car off the body.
	DOOR_GROUP = "DriveLabAtCarDoor",
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

-- The piece each piece of the model rides (Rules/CarParts), by name.
local function carriersOf(model: Model, binding: Binding.CarModel): { [string]: string }
	local pieces: { CarParts.Piece } = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local from = part:GetAttribute(CarParts.PART_ATTRIBUTE)
			table.insert(pieces, { name = part.Name, part = if typeof(from) == "string" then from else nil })
		end
	end
	return CarParts.carriers(pieces, binding.parents)
end

-- Imports are real scale; the world is Units.WORLD_SCALE times bigger. Scales the model to it and
-- sets the tyres back on whatever is under the car.
local function scaleToWorld(model: Model, binding: Binding.CarModel)
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

-- Lifts every part but the wheels, the calipers and what rides them off the wheels, where the
-- model sits its body too low; the wheels stay on the ground, so the physics is unchanged.
local function raiseBody(model: Model, binding: Binding.CarModel, carriers: { [string]: string })
	local lift = Vector3.new(0, Units.metresToStuds(binding.bodyRaise), 0)
	local fixed: { [string]: true } = {}
	for index, name in binding.wheels do
		fixed[name] = true
		for _, caliper in binding.calipers[index] do
			fixed[caliper] = true
		end
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and not fixed[CarParts.root(carriers, part.Name)] then
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

-- A steering wheel the model has no part for: an invisible hub at the binding's pivot, its Z along
-- the column toward the driver, which the wheel's parts ride (raised with the body).
local function addSteeringHub(model: Model, chassis: BasePart, binding: Binding.CarModel)
	local hub = binding.steeringHub
	if hub == nil or model:FindFirstChild(binding.steeringWheel, true) then
		return
	end
	local x, y, z = Hinge.column(Hinge.chassis(hub.axis))
	local frame = CFrame.fromMatrix(
		carSpace(hub.pivot, hub.pivot.up + binding.bodyRaise),
		Vector3.new(x.x, x.y, x.z),
		Vector3.new(y.x, y.y, y.z),
		Vector3.new(z.x, z.y, z.z)
	)
	local part = newPart("Part", binding.steeringWheel, Vector3.new(0.2, 0.2, 0.2), chassis.CFrame * frame)
	part.Parent = model
end

-- A hinge in chassis space: at its pivot (raised with the body), X along its axis (Rules/Hinge).
local function hingeFrame(pivot: Hinge.CarPoint, axis: Hinge.CarPoint, bodyRaise: number): CFrame
	local x, y, z = Hinge.frame(Hinge.chassis(axis))
	return CFrame.fromMatrix(
		carSpace(pivot, pivot.up + bodyRaise),
		Vector3.new(x.x, x.y, x.z),
		Vector3.new(y.x, y.y, y.z),
		Vector3.new(z.x, z.y, z.z)
	)
end

-- `rest` turns the part from its modelled pose to where it rests (Rules/Hinge.restAngle).
local function hingeWeld(name: string, chassis: BasePart, part: BasePart, frame: CFrame, rest: number)
	local joint = Instance.new("Weld")
	joint.Name = name
	joint.Part0 = chassis
	joint.Part1 = part
	joint.C0 = frame * CFrame.Angles(rest, 0, 0)
	joint.C1 = part.CFrame:ToObjectSpace(chassis.CFrame * frame)
	joint:SetAttribute("RestC0", joint.C0)
	joint.Parent = chassis
end

-- The drive-mode knob rides the steering wheel on its own Weld from the wheel's part, named after
-- the knob and kept on the chassis with the controls' welds, turned about X from its rest by the
-- driver's gestures (Rig/WheelGestures). Nil without a knob in the binding or the model.
local function knobPart(
	model: Model,
	binding: Binding.CarModel,
	wheel: BasePart?
): { part: BasePart, frame: CFrame, rest: number }?
	local knob = binding.modeKnob
	local part = knob and model:FindFirstChild(knob.hinge.part, true)
	if knob == nil or wheel == nil or part == nil or not part:IsA("BasePart") then
		return nil
	end
	return {
		part = part,
		frame = hingeFrame(knob.hinge.pivot, knob.hinge.axis, binding.bodyRaise),
		rest = Hinge.restAngle(knob.hinge),
	}
end

local function knobWeld(chassis: BasePart, wheel: BasePart, part: BasePart, frame: CFrame, rest: number)
	local hinge = chassis.CFrame * frame
	local joint = Instance.new("Weld")
	joint.Name = part.Name
	joint.Part0 = wheel
	joint.Part1 = part
	joint.C0 = wheel.CFrame:ToObjectSpace(hinge) * CFrame.Angles(rest, 0, 0)
	joint.C1 = part.CFrame:ToObjectSpace(hinge)
	joint:SetAttribute("RestC0", joint.C0)
	joint.Parent = chassis
end

-- The door's parts and the door's strap that the binding names and the model has.
local function doorParts(model: Model, binding: Binding.CarModel): ({ BasePart }, BasePart?)
	local door = {}
	local strap: Instance? = nil
	if binding.door then
		for _, name in binding.door.parts do
			local part = model:FindFirstChild(name, true)
			if part and part:IsA("BasePart") then
				table.insert(door, part)
			end
		end
		strap = if binding.door.strap then model:FindFirstChild(binding.door.strap.part, true) else nil
	end
	return door, if strap and strap:IsA("BasePart") then strap else nil
end

-- The hinged parts the binding names and the model has (its pedals, its cabin controls or its
-- wiper), each with its hinge frame and rest. Each hangs on its own Weld named after it, which
-- Controllers/DriverLegs (pedals), Controllers/CarDoor (controls) and Controllers/CarWiper (the
-- wiper) turn about X from its rest.
local function hingeParts<K>(
	model: Model,
	hinges: { [K]: Binding.Hinge }?,
	bodyRaise: number
): { [BasePart]: { frame: CFrame, rest: number } }
	local found: { [BasePart]: { frame: CFrame, rest: number } } = {}
	if hinges == nil then
		return found
	end
	for _, hinge in hinges do
		local part = model:FindFirstChild(hinge.part, true)
		if part and part:IsA("BasePart") then
			found[part] =
				{ frame = hingeFrame(hinge.pivot, hinge.axis, bodyRaise), rest = Hinge.restAngle(hinge) }
		end
	end
	return found
end

-- The door hangs on one Weld to an invisible part at its hinge, its parts welded rigidly to that
-- part; turning the Weld's C0 about X opens it. The door's strap hangs on its own Weld from the
-- chassis, where it sits in the place; Controllers/CarDoor poses it from then on.
local function hang(
	model: Model,
	chassis: BasePart,
	binding: Binding.CarModel,
	door: { BasePart },
	strap: BasePart?
)
	if binding.door and #door > 0 then
		local frame = hingeFrame(binding.door.pivot, binding.door.axis, binding.bodyRaise)
		local hinge = newPart("Part", DOOR_HINGE, Vector3.new(0.2, 0.2, 0.2), chassis.CFrame * frame)
		hinge.Massless = true
		hinge.Parent = model
		hingeWeld(DOOR_HINGE, chassis, hinge, frame, 0)
		for _, part in door do
			local joint = Instance.new("WeldConstraint")
			joint.Part0 = hinge
			joint.Part1 = part
			joint.Parent = part
		end
	end
	if strap then
		local joint = Instance.new("Weld")
		joint.Name = DOOR_STRAP
		joint.Part0 = chassis
		joint.Part1 = strap
		joint.C0 = chassis.CFrame:ToObjectSpace(strap.CFrame)
		joint:SetAttribute("RestC0", joint.C0)
		joint.Parent = chassis
	end
end

local function rigFrame(model: Model, binding: Binding.CarModel, car: Types.CarConfig): (CFrame, number)
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

local function addSeat(model: Model, chassis: BasePart, binding: Binding.CarModel): (Seat, ProximityPrompt)
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
local function addClusterScreen(model: Model, chassis: BasePart, binding: Binding.CarModel)
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
function CarRig.build(model: Model, car: Types.CarConfig, binding: Binding.CarModel): Rig
	assert(model:FindFirstChild("Chassis") == nil, `{model:GetFullName()} is already rigged`)
	scaleToWorld(model, binding)
	raiseBody(model, binding, carriersOf(model, binding))
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
	addSteeringHub(model, chassis, binding)
	local carriers = carriersOf(model, binding)

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
	local door, strapPart = doorParts(model, binding)
	local hinged: { [BasePart]: true } = {}
	for _, part in door do
		hinged[part] = true
	end
	if strapPart then
		hinged[strapPart] = true
	end
	local pedals = hingeParts(model, binding.pedals, binding.bodyRaise)
	local controls = hingeParts(model, binding.controls, binding.bodyRaise)
	local wiper = hingeParts(model, if binding.wiper then { binding.wiper.hinge } else nil, binding.bodyRaise)
	for _, set in { pedals, controls, wiper } do
		for part in set do
			hinged[part] = true
		end
	end
	local lever = binding.shifter and model:FindFirstChild(binding.shifter.part, true)
	local leverPart = if lever and lever:IsA("BasePart") then lever else nil
	if leverPart then
		hinged[leverPart] = true
	end
	local wheelPart = if steeringWheel and steeringWheel:IsA("BasePart") then steeringWheel else nil
	local knob = knobPart(model, binding, wheelPart)
	if knob then
		hinged[knob.part] = true
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= chassis then
			part.Massless = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			if moving[part] and part ~= steeringWheel then
				weld(chassis, part)
			elseif not moving[part] and not hinged[part] then
				-- A part riding another (Rules/CarParts) moves with it; any other is the body.
				local carrierName = carriers[part.Name]
				local carrier = if carrierName then model:FindFirstChild(carrierName, true) else nil
				local joint = Instance.new("WeldConstraint")
				joint.Part0 = if carrier and carrier:IsA("BasePart") then carrier else chassis
				joint.Part1 = part
				joint.Parent = part
			end
		end
	end
	hang(model, chassis, binding, door, strapPart)
	for _, set in { pedals, controls, wiper } do
		for part, hinge in set do
			hingeWeld(part.Name, chassis, part, hinge.frame, hinge.rest)
		end
	end
	if knob and wheelPart then
		knobWeld(chassis, wheelPart, knob.part, knob.frame, knob.rest)
	end
	local shifter = binding.shifter
	if shifter and leverPart then
		local pivot = carSpace(shifter.pivot, shifter.pivot.up + binding.bodyRaise)
		hingeWeld(leverPart.Name, chassis, leverPart, CFrame.new(pivot), 0)
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

-- A hinge weld and its rest C0, or nil while it or its part has not streamed in.
local function hingeOf(chassis: Instance, name: string): (Weld?, CFrame)
	local joint = chassis:FindFirstChild(name)
	local rest = joint and joint:GetAttribute("RestC0")
	if joint and joint:IsA("Weld") and joint.Part1 and typeof(rest) == "CFrame" then
		return joint, rest
	end
	return nil, CFrame.identity
end

-- Either side: the rig's pieces, or nil while they have not all streamed in.
function CarRig.find(model: Model, binding: Binding.CarModel): Rig?
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
	local doorHinge, doorRest = hingeOf(chassis, DOOR_HINGE)
	local controls: { [string]: Hinged } = {}
	local bound = binding.controls
	if bound then
		for name, control in bound do
			local joint, rest = hingeOf(chassis, control.part)
			if joint then
				controls[name] = { weld = joint, rest = rest }
			end
		end
	end
	local wiperWeld, wiperRest = nil, CFrame.identity
	if binding.wiper then
		wiperWeld, wiperRest = hingeOf(chassis, binding.wiper.hinge.part)
	end
	local shifterWeld, shifterRest = nil, CFrame.identity
	if binding.shifter then
		shifterWeld, shifterRest = hingeOf(chassis, binding.shifter.part)
	end
	local strap = hingeOf(chassis, DOOR_STRAP)
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
		door = doorHinge,
		doorRest = doorRest,
		controls = controls,
		wiper = if wiperWeld then { weld = wiperWeld, rest = wiperRest } else nil,
		shifter = if shifterWeld then { weld = shifterWeld, rest = shifterRest } else nil,
		strap = strap,
		seat = seat,
		prompt = prompt,
	}
end

return CarRig
