--!strict
--[[
	One car's physics, run each frame by whichever side owns its assembly: the driver's client
	while someone drives, the server while it stands empty. Each wheel is a raycast from the top
	of its travel; the vehicle model turns the contacts into forces, and they reach the engine
	as one world-space force and one torque about the centre of mass, held through the
	frame's physics steps.
]]
local Workspace = game:GetService("Workspace")

local CarRig = require("./CarRig")
local InputHelp = require("../Config/InputHelp")
local Interface = require("../Vehicle/Interface")
local Model = require("../Vehicle/Model")
local Steering = require("../Vehicle/Steering")
local Surfaces = require("../Config/Surfaces")
local Types = require("../Config/Cars/Types")
local Units = require("../Units")

export type Runner = {
	rig: CarRig.Rig,
	car: Types.CarConfig,
	state: Model.VehicleState,
	raycast: RaycastParams,
	reach: { number },
	-- Accumulated wheel rotation for the visuals, rad.
	spinAngles: { number },
	last: Interface.StepResult?,
	-- Car-frame acceleration of the centre of mass, in g, smoothed; for the camera and HUD.
	longitudinalG: number,
	lateralG: number,
	lastVelocity: Vector3,
}

local M = Units.METRES_PER_STUD
-- Seconds; the g readout is for cameras and gauges, which want it calm.
local G_SMOOTHING = 0.08

local VehicleRunner = {}

function VehicleRunner.new(rig: CarRig.Rig, car: Types.CarConfig, help: InputHelp.InputHelp?): Runner
	local raycast = RaycastParams.new()
	raycast.FilterType = Enum.RaycastFilterType.Exclude
	raycast.FilterDescendantsInstances = { rig.model }
	raycast.IgnoreWater = true
	-- Players standing by the car are not road.
	raycast.CollisionGroup = CarRig.RAY_GROUP
	local reach = table.create(4)
	for wheel = 1, 4 do
		local tyre = if wheel <= 2 then car.front.tyre else car.rear.tyre
		reach[wheel] = Units.metresToStuds(car.suspension.travel + tyre.radius)
	end
	return {
		rig = rig,
		car = car,
		state = Model.new(car, help),
		raycast = raycast,
		reach = reach,
		spinAngles = table.create(4, 0),
		last = nil,
		longitudinalG = 0,
		lateralG = 0,
		lastVelocity = rig.chassis.AssemblyLinearVelocity,
	}
end

local function surfaceGrip(material: Enum.Material): number
	local grip = Surfaces.GRIP[material] or Surfaces.DEFAULT_GRIP
	local wetness = Workspace:GetAttribute("Wetness")
	if typeof(wetness) == "number" then
		grip *= 1 - math.clamp(wetness, 0, 1) * (1 - Surfaces.WET_GRIP)
	end
	return grip
end

type Contact = { point: Vector3, mount: Vector3 }

local function contacts(runner: Runner, frame: CFrame): ({ Interface.WheelContact }, { Contact })
	local chassis = runner.rig.chassis
	local up, forward, right = frame.UpVector, frame.LookVector, frame.RightVector
	local travel = runner.car.suspension.travel
	local wheels: { Interface.WheelContact } = table.create(4)
	local points: { Contact } = table.create(4)
	for wheel, mount in runner.rig.mounts do
		local origin = mount.WorldPosition
		local reach = runner.reach[wheel]
		local hit = Workspace:Raycast(origin, -up * reach, runner.raycast)
		local distance = if hit then (hit.Position - origin):Dot(-up) else reach
		local point = origin - up * distance
		local velocity = chassis:GetVelocityAtPosition(point)
		wheels[wheel] = {
			grounded = hit ~= nil,
			compression = math.clamp(Units.studsToMetres(reach - distance), 0, travel),
			compressionSpeed = if hit then -velocity:Dot(up) * M else 0,
			forwardSpeed = velocity:Dot(forward) * M,
			rightSpeed = velocity:Dot(right) * M,
			grip = if hit then surfaceGrip(hit.Material) else 1,
		}
		points[wheel] = { point = point, mount = origin }
	end
	return wheels, points
end

local function applyForces(runner: Runner, result: Interface.StepResult, frame: CFrame, points: { Contact })
	local chassis = runner.rig.chassis
	local up, forward, right = frame.UpVector, frame.LookVector, frame.RightVector
	local centre = chassis.AssemblyCenterOfMass
	local total, moment = Vector3.zero, Vector3.zero
	local function push(force: Vector3, at: Vector3)
		total += force
		moment += (at - centre):Cross(force)
	end
	for wheel, wheelResult in result.wheels do
		local contact = points[wheel]
		push(up * Units.newtonsToForce(wheelResult.suspensionForce), contact.mount)
		local tyre = forward * wheelResult.forwardForce + right * wheelResult.rightForce
		push(tyre * (1 / Units.NEWTONS_PER_FORCE_UNIT), contact.point)
	end
	local velocity = chassis.AssemblyLinearVelocity
	if velocity.Magnitude > 0.01 then
		push(-velocity.Unit * Units.newtonsToForce(result.aeroDrag), centre)
	end
	local frontAxle = Units.metresToStuds((1 - runner.car.frontWeightShare) * runner.car.wheelbase)
	local rearAxle = frontAxle - Units.metresToStuds(runner.car.wheelbase)
	push(-up * Units.newtonsToForce(result.downforceFront), centre + forward * frontAxle)
	push(-up * Units.newtonsToForce(result.downforceRear), centre + forward * rearAxle)
	runner.rig.force.Force = total
	runner.rig.torque.Torque = moment
end

local function track(runner: Runner, frame: CFrame, dt: number)
	local velocity = runner.rig.chassis.AssemblyLinearVelocity
	local acceleration = (velocity - runner.lastVelocity) / dt * M / 9.81
	runner.lastVelocity = velocity
	local blend = 1 - math.exp(-dt / G_SMOOTHING)
	runner.longitudinalG += (acceleration:Dot(frame.LookVector) - runner.longitudinalG) * blend
	runner.lateralG += (acceleration:Dot(frame.RightVector) - runner.lateralG) * blend
end

function VehicleRunner.step(runner: Runner, input: Interface.DriverInput, dt: number): Interface.StepResult
	local chassis = runner.rig.chassis
	local frame = chassis.CFrame
	local wheels, points = contacts(runner, frame)
	local velocity = chassis.AssemblyLinearVelocity
	local result = Model.step(runner.state, input, wheels, {
		forwardSpeed = velocity:Dot(frame.LookVector) * M,
		rightSpeed = velocity:Dot(frame.RightVector) * M,
		-- Positive turning right, which is a negative spin about up.
		yawRate = -chassis.AssemblyAngularVelocity:Dot(frame.UpVector),
	}, dt)
	applyForces(runner, result, frame, points)
	track(runner, frame, dt)
	runner.last = result
	return result
end

-- Wheels and calipers follow the suspension and steering; wheels also spin. Only the side
-- that runs the car calls this, since only it knows the wheel states.
function VehicleRunner.animate(runner: Runner, dt: number)
	local result = runner.last
	if result == nil then
		return
	end
	local static = runner.car.suspension.staticCompression
	local steeringWheel = runner.rig.steeringWheel
	if steeringWheel then
		-- The filtered steering input times the lock is the steering wheel's angle; a right
		-- turn is clockwise to the driver, a negative turn about the column's +Z (toward them).
		local angle = result.telemetry.steer * Steering.maxWheelAngle(runner.car.steering)
		steeringWheel.C0 = runner.rig.steeringWheelRest * CFrame.Angles(0, 0, -angle)
	end
	for wheel, weld in runner.rig.wheels do
		local wheelResult = result.wheels[wheel]
		runner.spinAngles[wheel] = (runner.spinAngles[wheel] + wheelResult.spin * dt) % (2 * math.pi)
		local compression = runner.state.compressions[wheel]
		local lift = CFrame.new(0, Units.metresToStuds(compression - static), 0)
		-- Positive steer is to the right: a negative turn about up. Rolling forward turns the
		-- top of the wheel toward -Z: a negative turn about the axle.
		local steer = CFrame.Angles(0, -wheelResult.steerAngle, 0)
		local rest = runner.rig.wheelRest[wheel]
		local hub = lift * CFrame.new(rest.Position) * steer
		weld.C0 = hub * CFrame.Angles(-runner.spinAngles[wheel], 0, 0) * rest.Rotation
		for index, caliper in runner.rig.calipers[wheel] do
			local caliperRest = runner.rig.caliperRest[wheel][index]
			caliper.C0 = hub * CFrame.new(caliperRest.Position - rest.Position) * caliperRest.Rotation
		end
	end
end

-- Clears the forces, when this side stops running the car.
function VehicleRunner.release(rig: CarRig.Rig)
	rig.force.Force = Vector3.zero
	rig.torque.Torque = Vector3.zero
end

return VehicleRunner
