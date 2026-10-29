--!strict
--[[
	One car's physics, stepped once per frame by whatever owns the rigid body (the Roblox glue,
	or tools/DriveSim offline). The chassis is integrated outside; this model turns the frame's
	contacts and motion into forces.

	Per frame it runs the input layer, steering, suspension, tyre loads and aero. Then it splits
	the frame into equal substeps of at most `simulation.maxSubstep` (01 §5.3 point 1, 04 §2.5)
	for the fast states: wheel spin, engine, clutch, differentials, tyre deflections and the
	electronics. Inside the frame it also predicts the chassis's planar velocity from its own
	tyre and drag forces, so the tyre-to-chassis coupling is integrated at the substep rather
	than the frame rate; the forces it returns are frame averages, which carry the same momentum
	as that prediction when the engine holds them constant over the frame.
]]
local Aero = require("./Aero")
local Brakes = require("./Brakes")
local Driveline = require("./Driveline")
local Electronics = require("./Electronics")
local Engine = require("./Engine")
local Gearbox = require("./Gearbox")
local Geometry = require("./Geometry")
local InputFilter = require("./InputFilter")
local InputHelp = require("../Config/InputHelp")
local Interface = require("./Interface")
local Launch = require("./Launch")
local Selector = require("./Selector")
local Steering = require("./Steering")
local Suspension = require("./Suspension")
local Tyre = require("./Tyre")
local Types = require("../Config/Cars/Types")
local World = require("../Config/World")

export type CarConfig = Types.CarConfig
export type DriverInput = Interface.DriverInput
export type WheelContact = Interface.WheelContact
export type ChassisMotion = Interface.ChassisMotion
export type StepResult = Interface.StepResult

-- Pedal above which ABS treats the car as braking.
local BRAKING = 0.01
-- Gearbox output torque (N·m) below which the front share reads as zero.
local SHARE_FLOOR = 1

export type VehicleState = {
	car: CarConfig,
	help: InputHelp.InputHelp,
	positions: { Geometry.WheelPosition },
	tyres: { Tyre.Tyre },
	suspension: Suspension.Suspension,
	engine: Engine.Engine,
	driveline: Driveline.Driveline,
	brakes: Brakes.Brakes,
	controls: InputFilter.Controls,
	selector: Selector.SelectorState,
	launch: Launch.LaunchState,
	-- The device's pedals after the selector's swap, for the input filter.
	pedals: InputFilter.RawControls,
	engineState: Engine.EngineState,
	gearbox: Gearbox.GearboxState,
	drive: Driveline.DrivelineState,
	loads: Driveline.Loads,
	tyreStates: { Tyre.TyreState },
	electronics: Electronics.ElectronicsState,
	aero: Aero.AeroState,
	aeroForces: Aero.AeroForces,
	steering: Steering.SteeringState,
	compressions: { number },
	compressionSpeeds: { number },
	grounded: { boolean },
	suspensionForces: { number },
	wheelLoads: { number },
	cosines: { number },
	sines: { number },
	ground: { number },
	lateral: { number },
	surface: { number },
	spins: { number },
	sumForward: { number },
	sumRight: { number },
	throttle: number,
	meanGrip: number,
	context: Gearbox.Context,
	motion: Electronics.Motion,
}

-- The chassis velocity the model predicts within a frame.
type Prediction = { forward: number, right: number, yaw: number }

local Model = {}

function Model.new(car: CarConfig, help: InputHelp.InputHelp?): VehicleState
	local tyres = table.create(Geometry.WHEELS)
	local tyreStates = table.create(Geometry.WHEELS)
	for wheel = 1, Geometry.WHEELS do
		tyres[wheel] = Tyre.prepare(Geometry.axle(car, wheel).tyre, Geometry.cornerMass(car, wheel))
		tyreStates[wheel] = Tyre.newState()
	end
	local engine = Engine.prepare(car.engine)
	local wheelLoads = table.create(Geometry.WHEELS, 0)
	for wheel = 1, Geometry.WHEELS do
		wheelLoads[wheel] = Geometry.cornerMass(car, wheel) * World.GRAVITY_MPS2
	end
	return {
		car = car,
		help = help or InputHelp.keyboard,
		positions = Geometry.wheelPositions(car),
		tyres = tyres,
		suspension = Suspension.prepare(car),
		engine = engine,
		driveline = Driveline.prepare(car, car.engine.inertia),
		brakes = Brakes.prepare(car.brakes),
		controls = InputFilter.newState(),
		selector = Selector.newState(),
		launch = Launch.newState(),
		pedals = { steer = 0, throttle = 0, brake = 0, handbrake = 0 },
		engineState = Engine.newState(engine),
		gearbox = Gearbox.newState(),
		drive = Driveline.newState(engine.idleSpeed),
		loads = Driveline.newLoads(),
		tyreStates = tyreStates,
		electronics = Electronics.newState(),
		aero = Aero.newState(),
		aeroForces = { drag = 0, downforceFront = 0, downforceRear = 0 },
		steering = Steering.newState(),
		compressions = table.create(Geometry.WHEELS, 0),
		compressionSpeeds = table.create(Geometry.WHEELS, 0),
		grounded = table.create(Geometry.WHEELS, false),
		suspensionForces = table.create(Geometry.WHEELS, 0),
		wheelLoads = wheelLoads,
		cosines = table.create(Geometry.WHEELS, 1),
		sines = table.create(Geometry.WHEELS, 0),
		ground = table.create(Geometry.WHEELS, 0),
		lateral = table.create(Geometry.WHEELS, 0),
		surface = table.create(Geometry.WHEELS, 0),
		spins = table.create(Geometry.WHEELS, 0),
		sumForward = table.create(Geometry.WHEELS, 0),
		sumRight = table.create(Geometry.WHEELS, 0),
		throttle = 0,
		meanGrip = 1,
		context = {
			engineSpeed = 0,
			outputSpeed = 0,
			engineTorque = 0,
			groundSpeed = 0,
			throttle = 0,
			brake = 0,
			mode = car.modes.Strada,
			gearboxMode = "auto",
			holdGear = false,
		},
		motion = { forwardSpeed = 0, rightSpeed = 0, yawRate = 0, frontSteer = 0, rearSteer = 0, grip = 1 },
	}
end

local function gearboxContext(
	state: VehicleState,
	input: DriverInput,
	groundSpeed: number,
	engineTorque: number
): Gearbox.Context
	local context = state.context
	context.engineSpeed = state.drive.speeds[1]
	context.outputSpeed = state.drive.speeds[2]
	context.engineTorque = engineTorque
	context.groundSpeed = groundSpeed
	context.throttle = state.controls.throttle
	context.brake = state.controls.brake
	context.mode = state.car.modes[input.drivingMode]
	context.gearboxMode = input.gearboxMode
	context.holdGear = state.launch.phase == "Launching" and not state.car.launch.autoUpshift
	return context
end

local function updateCorners(
	state: VehicleState,
	wheels: { WheelContact },
	mode: Types.ModeConfig,
	dt: number
)
	local grip, count = 0, 0
	for wheel = 1, Geometry.WHEELS do
		local contact = wheels[wheel]
		state.compressions[wheel] = contact.compression
		state.compressionSpeeds[wheel] = contact.compressionSpeed
		state.grounded[wheel] = contact.grounded
		if contact.grounded then
			grip += contact.grip
			count += 1
		end
	end
	state.meanGrip = if count > 0 then grip / count else 1
	Suspension.forces(
		state.suspension,
		mode.damperRatio,
		state.compressions,
		state.compressionSpeeds,
		state.grounded,
		state.suspensionForces
	)
	local follow = 1 - math.exp(-dt / state.car.simulation.loadFilterTime)
	for wheel = 1, Geometry.WHEELS do
		local load = state.wheelLoads[wheel]
		load = if state.grounded[wheel] then load + (state.suspensionForces[wheel] - load) * follow else 0
		state.wheelLoads[wheel] = load
		Tyre.setLoad(state.tyres[wheel], state.tyreStates[wheel], load, wheels[wheel].grip)
		state.spins[wheel] = Driveline.wheelSpeed(state.driveline, state.drive, wheel)
		local angle = state.steering.angles[wheel]
		state.cosines[wheel], state.sines[wheel] = math.cos(angle), math.sin(angle)
	end
end

-- The engine's throttle this substep: the driver's after TC, ESC and reverse's top speed, the
-- gearbox's cut or blip, the idle governor, then the limiter.
local function engineThrottle(
	state: VehicleState,
	input: DriverInput,
	prediction: Prediction,
	dt: number
): number
	local electronics, engine = state.electronics, state.engine
	local engineSpeed = state.drive.speeds[1]
	local driver = state.controls.throttle
		* electronics.tcFactor
		* electronics.escFactor
		* Gearbox.reverseCut(state.car.gearbox, state.gearbox.gear, prediction.forward)
	local driveTorque = Engine.output(engine, engineSpeed, driver)
	local context = gearboxContext(state, input, math.abs(prediction.forward), driveTorque)
	local cut, blip = Gearbox.update(state.car.gearbox, state.car.engine, state.gearbox, context, dt)
	local throttle = if cut then 0 else math.max(driver, blip)
	throttle = math.max(throttle, Engine.idleThrottle(engine, engineSpeed))
	state.engineState.speed = engineSpeed
	local limit = if state.gearbox.holding then engine.launchSpeed else engine.limiterSpeed
	if Engine.updateLimiter(engine, state.engineState, limit) then
		throttle = 0
	end
	return throttle
end

local function runElectronics(
	state: VehicleState,
	input: DriverInput,
	prediction: Prediction,
	mode: Types.ModeConfig,
	dt: number
)
	local car, electronics = state.car, state.electronics
	local angles = state.steering.angles
	for wheel = 1, Geometry.WHEELS do
		state.surface[wheel] = state.spins[wheel] * state.tyres[wheel].radius
	end
	local motion = state.motion
	motion.forwardSpeed = prediction.forward
	motion.rightSpeed = prediction.right
	motion.yawRate = prediction.yaw
	motion.frontSteer = (angles[Geometry.FRONT_LEFT] + angles[Geometry.FRONT_RIGHT]) / 2
	motion.rearSteer = angles[Geometry.REAR_LEFT]
	motion.grip = state.meanGrip
	Electronics.updateEsc(car, mode, electronics, input.assists.esc, motion, dt)
	local escBraking = false
	for wheel = 1, Geometry.WHEELS do
		escBraking = escBraking or electronics.escBrake[wheel] > 0
	end
	local braking = state.controls.brake > BRAKING or escBraking
	Electronics.updateAbs(
		car.electronics,
		electronics,
		input.assists.abs,
		braking,
		state.surface,
		state.ground,
		dt
	)
	-- A launch works the tyres at its own slip, even with TC switched off.
	local launching = state.launch.phase == "Launching"
	Electronics.updateTc(
		car.electronics,
		if launching then car.launch.slipRatio else mode.tcSlipRatio,
		electronics,
		input.assists.tc or launching,
		state.controls.throttle,
		state.surface,
		state.ground,
		dt
	)
end

local function setLoads(state: VehicleState, mode: Types.ModeConfig, throttle: number)
	local car, drive, loads = state.car, state.drive, state.loads
	local engineSpeed = drive.speeds[1]
	loads.engineTorque, loads.engineDrag = Engine.output(state.engine, engineSpeed, throttle)
	loads.ratio = if state.gearbox.phase == "neutral"
		then 0
		else Gearbox.ratio(car.gearbox, state.gearbox.gear)
	loads.clutchCapacity = Gearbox.clutchCapacity(car.gearbox, state.gearbox)
	loads.couplingCapacity = Driveline.couplingCapacity(mode, drive.outputTorque, drive.clutchTorque >= 0)
	loads.lsdCapacity =
		Driveline.lsdCapacity(car.driveline, Driveline.rearInputTorque(state.driveline, drive))
	loads.lossCapacity = (1 - car.driveline.efficiency) * math.abs(drive.outputTorque)
	for wheel = 1, Geometry.WHEELS do
		loads.brakeCapacity[wheel] = Brakes.torque(
			state.brakes,
			wheel,
			state.controls.brake,
			state.controls.handbrake,
			state.electronics.absFactor[wheel],
			state.electronics.escBrake[wheel]
		) + Tyre.rollingResistanceTorque(state.tyres[wheel], state.wheelLoads[wheel], state.ground[wheel])
	end
end

local function substep(
	state: VehicleState,
	input: DriverInput,
	wheels: { WheelContact },
	chassis: ChassisMotion,
	prediction: Prediction,
	mode: Types.ModeConfig,
	dt: number
)
	local car, positions = state.car, state.positions
	local dForward = prediction.forward - chassis.forwardSpeed
	local dRight = prediction.right - chassis.rightSpeed
	local dYaw = prediction.yaw - chassis.yawRate
	for wheel = 1, Geometry.WHEELS do
		local position = positions[wheel]
		local forward = wheels[wheel].forwardSpeed + dForward - dYaw * position.right
		local right = wheels[wheel].rightSpeed + dRight + dYaw * position.forward
		local c, s = state.cosines[wheel], state.sines[wheel]
		state.ground[wheel] = forward * c + right * s
		state.lateral[wheel] = right * c - forward * s
	end
	runElectronics(state, input, prediction, mode, dt)
	state.throttle = engineThrottle(state, input, prediction, dt)
	setLoads(state, mode, state.throttle)

	local drive, driveline, simulation = state.drive, state.driveline, car.simulation
	for wheel = 1, Geometry.WHEELS do
		Tyre.prepareSubstep(
			state.tyres[wheel],
			state.tyreStates[wheel],
			state.ground[wheel],
			state.lateral[wheel],
			state.spins[wheel],
			simulation,
			dt
		)
	end
	Driveline.solve(driveline, drive, state.loads, state.tyreStates, simulation.solverIterations, dt)

	local forceX, forceY, moment = 0, 0, 0
	for wheel = 1, Geometry.WHEELS do
		local spin = Driveline.wheelSpeed(driveline, drive, wheel)
		state.spins[wheel] = spin
		Tyre.finishSubstep(
			state.tyres[wheel],
			state.tyreStates[wheel],
			state.ground[wheel],
			spin,
			simulation,
			dt
		)
		local fx = Driveline.tyreForce(driveline, drive, wheel, dt)
		local fy = state.tyreStates[wheel].forceY
		local c, s = state.cosines[wheel], state.sines[wheel]
		local forward, right = fx * c - fy * s, fx * s + fy * c
		state.sumForward[wheel] += forward * dt
		state.sumRight[wheel] += right * dt
		forceX += forward
		forceY += right
		moment += positions[wheel].forward * right - positions[wheel].right * forward
	end
	local airSpeed = math.sqrt(prediction.forward * prediction.forward + prediction.right * prediction.right)
	if airSpeed > 1e-6 then
		local drag = state.aeroForces.drag / airSpeed
		forceX -= drag * prediction.forward
		forceY -= drag * prediction.right
	end
	local forward = prediction.forward
	prediction.forward += dt * (forceX / car.mass + prediction.yaw * prediction.right)
	prediction.right += dt * (forceY / car.mass - prediction.yaw * forward)
	prediction.yaw += dt * moment / car.yawInertia
end

local function buildResult(state: VehicleState, chassis: ChassisMotion, dt: number): StepResult
	local results = table.create(Geometry.WHEELS)
	local absSum = 0
	for wheel = 1, Geometry.WHEELS do
		local tyre = state.tyreStates[wheel]
		results[wheel] = {
			suspensionForce = state.suspensionForces[wheel],
			forwardForce = state.sumForward[wheel] / dt,
			rightForce = state.sumRight[wheel] / dt,
			steerAngle = state.steering.angles[wheel],
			spin = Driveline.wheelSpeed(state.driveline, state.drive, wheel),
			slipRatio = tyre.slipRatio,
			slipAngle = tyre.slipAngle,
			load = state.wheelLoads[wheel],
			combinedSlip = tyre.combinedSlip,
		}
		absSum += state.electronics.absFactor[wheel]
	end
	local drive, electronics, gearbox = state.drive, state.electronics, state.gearbox
	local output = drive.outputTorque
	return {
		wheels = results,
		aeroDrag = state.aeroForces.drag,
		downforceFront = state.aeroForces.downforceFront,
		downforceRear = state.aeroForces.downforceRear,
		telemetry = {
			rpm = drive.speeds[1] / Engine.RAD_PER_RPM,
			gear = gearbox.gear,
			speedKmh = math.abs(chassis.forwardSpeed) * 3.6,
			throttle = state.throttle,
			brake = state.controls.brake * absSum / Geometry.WHEELS,
			absActive = electronics.absActive,
			tcActive = electronics.tcActive,
			escActive = electronics.escActive,
			shifting = Gearbox.isShifting(gearbox),
			frontTorqueShare = if math.abs(output) > SHARE_FLOOR then drive.couplingTorque / output else 0,
			clutch = gearbox.engagement,
			limiter = state.engineState.limiterCut,
			alaOpen = state.aero.alaOpen,
			launch = state.launch.phase,
			steer = state.controls.steer,
			rearSteerAngle = state.steering.rearAngle,
		},
	}
end

-- Advances the car by one frame of `dt` seconds (clamped to `simulation.maxFrameTime`) and
-- returns the forces for the rigid body. The result is a fresh table each call.
function Model.step(
	state: VehicleState,
	input: DriverInput,
	wheels: { WheelContact },
	chassis: ChassisMotion,
	dt: number
): StepResult
	local car = state.car
	dt = math.clamp(dt, 1e-5, car.simulation.maxFrameTime)
	local mode = car.modes[input.drivingMode]
	local forward, right, yaw = chassis.forwardSpeed, chassis.rightSpeed, chassis.yawRate
	local groundSpeed = math.abs(forward)
	local gearbox = state.gearbox
	local selected = Launch.selected(car.launch, input)
	local launchReady = Launch.available(
		car.launch,
		input,
		gearbox.gear,
		Gearbox.isShifting(gearbox),
		groundSpeed,
		car.gearbox.selectorMaxSpeed
	)
	Selector.update(state.help, car.gearbox, gearbox, state.selector, input, groundSpeed, launchReady, dt)
	local pedals = Selector.pedals(state.help, gearbox, input, state.pedals)
	InputFilter.update(state.help, car, state.controls, pedals, forward, right, yaw, dt)
	local controls = state.controls
	Launch.update(
		car.launch,
		state.launch,
		selected,
		launchReady,
		controls.throttle,
		controls.brake,
		gearbox.gear,
		groundSpeed
	)
	Steering.update(car, state.steering, state.controls.steer, forward, dt)
	updateCorners(state, wheels, mode, dt)
	local alaTarget =
		Aero.alaTarget(car.aero, forward, state.controls.throttle, state.controls.brake, yaw * forward)
	Aero.update(
		car.aero,
		state.aero,
		math.sqrt(forward * forward + right * right),
		alaTarget,
		dt,
		state.aeroForces
	)
	Gearbox.request(
		car.gearbox,
		car.engine,
		state.gearbox,
		input.shiftUp,
		input.shiftDown,
		gearboxContext(state, input, math.abs(forward), 0)
	)

	local count = math.ceil(dt / car.simulation.maxSubstep - 1e-9)
	local h = dt / count
	local prediction: Prediction = { forward = forward, right = right, yaw = yaw }
	for wheel = 1, Geometry.WHEELS do
		state.sumForward[wheel], state.sumRight[wheel] = 0, 0
	end
	for _ = 1, count do
		substep(state, input, wheels, chassis, prediction, mode, h)
	end
	return buildResult(state, chassis, dt)
end

return table.freeze(Model)
