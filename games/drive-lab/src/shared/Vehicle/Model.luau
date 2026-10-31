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
local Drift = require("./Drift")
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
	-- Each tyre's peak forces at this frame's load and grip, before the drift scales the rear's.
	basePeakX: { number },
	basePeakY: { number },
	drift: Drift.DriftState,
	-- The handbrake the brakes get (the drift releases it) and the steering the wheels get.
	handbrake: number,
	wheelSteer: number,
	-- The drift's force (N, forward and right) and yaw torque (N·m) at the centre of mass, summed
	-- over the frame's substeps times their length.
	driftForward: number,
	driftRight: number,
	driftYaw: number,
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
		basePeakX = table.create(Geometry.WHEELS, 0),
		basePeakY = table.create(Geometry.WHEELS, 0),
		drift = Drift.newState(),
		handbrake = 0,
		wheelSteer = 0,
		driftForward = 0,
		driftRight = 0,
		driftYaw = 0,
		throttle = 0,
		meanGrip = 1,
		context = {
			engineSpeed = 0,
			outputSpeed = 0,
			engineTorque = 0,
			groundSpeed = 0,
			throttle = 0,
			brake = 0,
			mode = car.modes[car.modeOrder[1]],
			gearboxMode = "auto",
			holdGear = false,
			clutchPedal = 0,
		},
		motion = { forwardSpeed = 0, rightSpeed = 0, yawRate = 0, frontSteer = 0, rearSteer = 0, grip = 1 },
	}
end

-- Yaw rate (rad/s) the player's own steering asks of the car: ESC's reference for the wheels the
-- player's input `steer` (shaped, not yet filtered) would set, so a released key asks for none at
-- once rather than as the filter returns the wheel.
local function playerYawRate(
	state: VehicleState,
	steer: number,
	forward: number,
	right: number,
	yaw: number
): number
	local motion = state.motion
	motion.forwardSpeed, motion.rightSpeed, motion.yawRate = forward, right, yaw
	motion.frontSteer = Steering.frontAngle(state.car.steering, steer, forward)
	motion.rearSteer = state.steering.rearAngle
	motion.grip = state.meanGrip
	return Electronics.referenceYawRate(state.car, motion)
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
	context.clutchPedal = input.clutchPedal or 0
	local launch = state.car.launch
	context.holdGear = state.launch.phase == "Launching" and launch ~= nil and not launch.autoUpshift
		or Drift.engaged(state.drift)
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
		local tyre = state.tyreStates[wheel]
		Tyre.setLoad(state.tyres[wheel], tyre, load, wheels[wheel].grip)
		state.basePeakX[wheel], state.basePeakY[wheel] = tyre.peakX, tyre.peakY
		state.spins[wheel] = Driveline.wheelSpeed(state.driveline, state.drive, wheel)
		local angle = state.steering.angles[wheel]
		state.cosines[wheel], state.sines[wheel] = math.cos(angle), math.sin(angle)
	end
end

-- The engine's throttle this substep: the driver's after TC, ESC, reverse's top speed and the
-- governor, the gearbox's cut, blip or share, the idle governor (none once stalled), then the
-- limiter.
local function engineThrottle(
	state: VehicleState,
	input: DriverInput,
	prediction: Prediction,
	dt: number
): number
	local electronics, engine, car = state.electronics, state.engine, state.car
	local engineSpeed = state.drive.speeds[1]
	local driver = state.controls.throttle
		* electronics.tcFactor
		* electronics.escFactor
		* Gearbox.reverseCut(car.gearbox, state.gearbox.gear, prediction.forward)
	local governor = car.engine.governor
	if governor then
		driver *= math.clamp((governor.speed - math.abs(prediction.forward)) / governor.band, 0, 1)
	end
	local driveTorque = Engine.output(engine, engineSpeed, driver)
	local context = gearboxContext(state, input, math.abs(prediction.forward), driveTorque)
	local cut, blip, share = Gearbox.update(state.car.gearbox, state.car.engine, state.gearbox, context, dt)
	local throttle = if cut then 0 else math.max(driver * share, blip)
	if Gearbox.stalled(state.gearbox) then
		throttle = 0
	else
		local idleRpm = context.mode.idleRpm
		local idleSpeed = if idleRpm then idleRpm * Engine.RAD_PER_RPM else nil
		throttle = math.max(throttle, Engine.idleThrottle(engine, engineSpeed, idleSpeed))
	end
	state.engineState.speed = engineSpeed
	local limit = if state.gearbox.holding
		then engine.launchSpeed
		elseif Gearbox.pullingAway(car.gearbox, state.gearbox, context) then engine.launchSpeed
			* (1 + car.gearbox.clutchSlipBand)
		else engine.limiterSpeed
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
	local esc = input.assists.esc and not Drift.assisting(state.drift)
	Electronics.updateEsc(car, mode, electronics, esc, motion, dt)
	local escBraking = false
	for wheel = 1, Geometry.WHEELS do
		escBraking = escBraking or electronics.escBrake[wheel] > 0
	end
	local braking = state.controls.brake > BRAKING or escBraking
	Electronics.updateAbs(
		car.electronics,
		mode,
		electronics,
		input.assists.abs,
		braking,
		state.surface,
		state.ground,
		dt
	)
	-- A launch works the tyres at its own slip, even with TC switched off.
	local launch = car.launch
	local launching = state.launch.phase == "Launching"
	local profile = car.drift
	local tcSlip = if profile then Drift.tcSlip(profile, state.drift, mode.tcSlipRatio) else mode.tcSlipRatio
	Electronics.updateTc(
		car.electronics,
		if launching and launch then launch.slipRatio else tcSlip,
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
	local profile = car.drift
	if profile then
		loads.couplingCapacity =
			Drift.couplingCapacity(profile, state.drift, loads.couplingCapacity, drive.outputTorque)
	end
	loads.lsdCapacity =
		Driveline.lsdCapacity(car.driveline, mode, Driveline.rearInputTorque(state.driveline, drive))
	loads.lossCapacity = (1 - car.driveline.efficiency) * math.abs(drive.outputTorque)
	for wheel = 1, Geometry.WHEELS do
		loads.brakeCapacity[wheel] = Brakes.torque(
			state.brakes,
			wheel,
			state.controls.brake,
			state.handbrake,
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
	local profile = car.drift
	if profile and Drift.engaged(state.drift) then
		local front, rear = Drift.grip(profile, state.drift)
		for wheel = 1, Geometry.WHEELS do
			local tyre = state.tyreStates[wheel]
			if Geometry.isFront(wheel) then
				tyre.peakY = state.basePeakY[wheel] * front
			else
				tyre.peakX, tyre.peakY = state.basePeakX[wheel] * rear, state.basePeakY[wheel] * rear
			end
		end
	end
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
	if profile then
		local driftForward, driftRight, driftYaw = Drift.forces(
			car,
			profile,
			state.drift,
			prediction.forward,
			prediction.right,
			prediction.yaw,
			moment
		)
		state.driftForward += driftForward * dt
		state.driftRight += driftRight * dt
		state.driftYaw += driftYaw * dt
		forceX += driftForward
		forceY += driftRight
		moment += driftYaw
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
	local hbox = gearbox.hbox
	local plan = hbox.plan
	return {
		wheels = results,
		aeroDrag = state.aeroForces.drag,
		driftForce = {
			forward = state.driftForward / dt,
			right = state.driftRight / dt,
			yaw = state.driftYaw / dt,
		},
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
			drift = state.drift.engagement,
			driftTarget = state.drift.target,
			steer = if Drift.engaged(state.drift) then state.wheelSteer else state.controls.steer,
			rearSteerAngle = state.steering.rearAngle,
			clutchPedal = hbox.pedal,
			handAt = hbox.handAt,
			footAt = hbox.footAt,
			shiftFrom = if plan then plan.from else gearbox.gear,
			shiftTo = if plan then plan.to else gearbox.gear,
			shiftElapsed = if plan then hbox.time else 0,
			stalled = hbox.stalled,
			shiftRefused = hbox.refused,
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
	local steerBefore = state.controls.steer
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
	-- The wheels hold one angle through the frame's substeps: the frame's mean steer rather than
	-- its end, or at 30 FPS a turning wheel leads the 240 FPS car by half a frame (3 to 4 % more
	-- yaw half a second into a slow keyboard turn, measured 2026-10-29).
	local steer = (steerBefore + state.controls.steer) / 2
	local profile = car.drift
	if profile then
		local held = input.drift == true
		local shaped = InputFilter.shape(state.help, pedals.steer)
		Drift.update(
			profile,
			state.drift,
			held,
			shaped,
			forward,
			right,
			playerYawRate(state, shaped, forward, right, yaw),
			dt
		)
		steer = Drift.steer(car, state.drift, steer, forward, right, yaw)
	end
	state.wheelSteer = steer
	state.handbrake = if state.drift.wants then 0 else controls.handbrake
	Steering.update(car, state.steering, steer, forward, dt)
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
	state.driftForward, state.driftRight, state.driftYaw = 0, 0, 0
	for _ = 1, count do
		substep(state, input, wheels, chassis, prediction, mode, h)
	end
	return buildResult(state, chassis, dt)
end

-- Starts a stalled engine (Gearbox.restart's interlock), cranking it to idle. Returns whether it
-- started.
function Model.restart(state: VehicleState, clutchPedal: number): boolean
	if not Gearbox.restart(state.car.gearbox, state.gearbox, clutchPedal) then
		return false
	end
	local speeds = state.drive.speeds
	speeds[1] = math.max(speeds[1], state.engine.idleSpeed)
	return true
end

return table.freeze(Model)
