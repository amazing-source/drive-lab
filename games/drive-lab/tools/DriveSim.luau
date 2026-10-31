--!strict
--[[
	A flat test track for the vehicle model, so the car can be calibrated without Roblox
	(tests/Calibration.spec.luau checks it, tools/calibrate.luau prints it). It plays the part the
	Roblox glue will: each frame it measures the wheels' contacts and the chassis motion, calls
	Model.step once, then integrates a rigid body with the returned forces held constant across
	the frame at Roblox's 240 Hz solver rate, as a VectorForce and a Torque are held.

	The body has planar position and yaw, and heave, pitch and roll as real degrees of freedom
	(small angles). Load transfer then comes through the springs, dampers and anti-roll bars
	with their real lag, which is what Roblox will do and what the suspension module must survive
	at 30 FPS; a quasi-static transfer would skip exactly the part worth testing. Wheels are
	massless and the ground is a plane, so a wheel's compression comes from the body's pose.
]]
local Geometry = require("../src/shared/Vehicle/Geometry")
local InputHelp = require("../src/shared/Config/InputHelp")
local Model = require("../src/shared/Vehicle/Model")
local Types = require("../src/shared/Config/Cars/Types")
local World = require("../src/shared/Config/World")

local SOLVER_RATE = 240

export type Body = {
	-- World position (m) and heading (rad, increasing as the car turns right).
	x: number,
	y: number,
	heading: number,
	-- World velocity (m/s) and yaw rate (rad/s).
	vx: number,
	vy: number,
	yawRate: number,
	-- Centre-of-mass height change from static (m), nose-up pitch and right-side-down roll (rad).
	heave: number,
	heaveRate: number,
	pitch: number,
	pitchRate: number,
	roll: number,
	rollRate: number,
}

export type Sim = {
	car: Types.CarConfig,
	model: Model.VehicleState,
	body: Body,
	positions: { Geometry.WheelPosition },
	contacts: { Model.WheelContact },
	chassis: Model.ChassisMotion,
	time: number,
	grip: number,
	-- Per-wheel multipliers on `grip`, in Vehicle/Geometry's wheel order: what VehicleRunner's
	-- surface grip would give each wheel.
	wheelGrip: { number },
}

export type InputOptions = {
	throttle: number?,
	brake: number?,
	steer: number?,
	handbrake: number?,
	shiftUp: boolean?,
	shiftDown: boolean?,
	gearboxMode: ("auto" | "manual")?,
	drivingMode: Types.DrivingMode?,
	abs: boolean?,
	tc: boolean?,
	esc: boolean?,
	drift: boolean?,
}

local DriveSim = {}

function DriveSim.new(car: Types.CarConfig, help: InputHelp.InputHelp?): Sim
	local contacts = table.create(Geometry.WHEELS)
	for wheel = 1, Geometry.WHEELS do
		contacts[wheel] = {
			grounded = true,
			compression = car.suspension.staticCompression,
			compressionSpeed = 0,
			forwardSpeed = 0,
			rightSpeed = 0,
			grip = 1,
		}
	end
	return {
		car = car,
		model = Model.new(car, help or InputHelp.direct),
		body = {
			x = 0,
			y = 0,
			heading = 0,
			vx = 0,
			vy = 0,
			yawRate = 0,
			heave = 0,
			heaveRate = 0,
			pitch = 0,
			pitchRate = 0,
			roll = 0,
			rollRate = 0,
		},
		positions = Geometry.wheelPositions(car),
		contacts = contacts,
		chassis = { forwardSpeed = 0, rightSpeed = 0, yawRate = 0 },
		time = 0,
		grip = 1,
		wheelGrip = table.create(Geometry.WHEELS, 1),
	}
end

function DriveSim.input(options: InputOptions?): Model.DriverInput
	local o: InputOptions = options or {}
	return {
		throttle = o.throttle or 0,
		brake = o.brake or 0,
		steer = o.steer or 0,
		handbrake = o.handbrake or 0,
		shiftUp = o.shiftUp or false,
		shiftDown = o.shiftDown or false,
		gearboxMode = o.gearboxMode or "auto",
		drivingMode = o.drivingMode or "Corsa",
		assists = {
			abs = if o.abs == nil then true else o.abs,
			tc = if o.tc == nil then true else o.tc,
			esc = if o.esc == nil then true else o.esc,
		},
		drift = o.drift,
	}
end

-- Velocity in the car frame (forward, right).
function DriveSim.localVelocity(body: Body): (number, number)
	local c, s = math.cos(body.heading), math.sin(body.heading)
	return body.vx * c + body.vy * s, body.vy * c - body.vx * s
end

function DriveSim.forwardSpeed(sim: Sim): number
	return (DriveSim.localVelocity(sim.body))
end

-- Starts the car rolling straight at `speed` in `gear`, every shaft turning at road speed.
function DriveSim.setSpeed(sim: Sim, speed: number, gear: number)
	local car, model = sim.car, sim.model
	sim.body.vx = speed * math.cos(sim.body.heading)
	sim.body.vy = speed * math.sin(sim.body.heading)
	local speeds = model.drive.speeds
	speeds[2] = speed / car.rear.tyre.radius * car.driveline.rearReduction
	speeds[3] = 0
	speeds[4] = speed / car.front.tyre.radius * car.driveline.frontReduction
	speeds[5] = 0
	model.gearbox.gear, model.gearbox.target = gear, gear
	model.gearbox.autoClutch, model.gearbox.engagement, model.gearbox.launching = 1, 1, false
	speeds[1] = math.max(speeds[2] * car.gearbox.ratios[gear], model.engine.idleSpeed)
end

local function measure(sim: Sim)
	local body, car = sim.body, sim.car
	local forward, right = DriveSim.localVelocity(body)
	local height = car.cgHeight + body.heave
	local travel = car.suspension.travel
	for wheel = 1, Geometry.WHEELS do
		local position = sim.positions[wheel]
		local contact = sim.contacts[wheel]
		local rise = body.heave + position.forward * body.pitch - position.right * body.roll
		local riseRate = body.heaveRate + position.forward * body.pitchRate - position.right * body.rollRate
		local compression = car.suspension.staticCompression - rise
		contact.grounded = compression > 0
		contact.compression = math.clamp(compression, 0, travel)
		contact.compressionSpeed = if contact.grounded then -riseRate else 0
		contact.forwardSpeed = forward - body.yawRate * position.right + body.pitchRate * height
		contact.rightSpeed = right + body.yawRate * position.forward - body.rollRate * height
		contact.grip = sim.grip * sim.wheelGrip[wheel]
	end
	sim.chassis.forwardSpeed = forward
	sim.chassis.rightSpeed = right
	sim.chassis.yawRate = body.yawRate
end

-- Net forces of a step in the car frame: planar force, vertical force, and yaw, pitch and roll
-- moments about the centre of mass.
local function netForces(sim: Sim, result: Model.StepResult): (number, number, number, number, number, number)
	local car, body = sim.car, sim.body
	local height = car.cgHeight + body.heave
	local fx, fy, fz = 0, 0, -car.mass * World.GRAVITY_MPS2
	local yaw, pitch, roll = 0, 0, 0
	for wheel = 1, Geometry.WHEELS do
		local position = sim.positions[wheel]
		local out = result.wheels[wheel]
		fx += out.forwardForce
		fy += out.rightForce
		fz += out.suspensionForce
		yaw += position.forward * out.rightForce - position.right * out.forwardForce
		pitch += out.suspensionForce * position.forward + out.forwardForce * height
		roll += -out.suspensionForce * position.right - out.rightForce * height
	end
	local forward, right = DriveSim.localVelocity(body)
	local speed = math.sqrt(forward * forward + right * right)
	if speed > 1e-6 then
		fx -= result.aeroDrag * forward / speed
		fy -= result.aeroDrag * right / speed
	end
	local drift = result.driftForce
	fx += drift.forward
	fy += drift.right
	yaw += drift.yaw
	local frontAxle = sim.positions[1].forward
	local rearAxle = sim.positions[3].forward
	fz -= result.downforceFront + result.downforceRear
	pitch -= result.downforceFront * frontAxle + result.downforceRear * rearAxle
	return fx, fy, fz, yaw, pitch, roll
end

-- One frame: measure, step the model, integrate the body. Returns the step's result.
function DriveSim.frame(sim: Sim, input: Model.DriverInput, dt: number): Model.StepResult
	measure(sim)
	local result = Model.step(sim.model, input, sim.contacts, sim.chassis, dt)
	local car, body = sim.car, sim.body
	local fx, fy, fz, yaw, pitch, roll = netForces(sim, result)
	local c, s = math.cos(body.heading), math.sin(body.heading)
	local worldX, worldY = fx * c - fy * s, fx * s + fy * c
	local count = math.ceil(dt * SOLVER_RATE - 1e-9)
	local h = dt / count
	for _ = 1, count do
		body.vx += worldX / car.mass * h
		body.vy += worldY / car.mass * h
		body.yawRate += yaw / car.yawInertia * h
		body.heaveRate += fz / car.mass * h
		body.pitchRate += pitch / car.pitchInertia * h
		body.rollRate += roll / car.rollInertia * h
		body.x += body.vx * h
		body.y += body.vy * h
		body.heading += body.yawRate * h
		body.heave += body.heaveRate * h
		body.pitch += body.pitchRate * h
		body.roll += body.rollRate * h
	end
	sim.time += dt
	return result
end

-- The mode the scenarios below run in unless told: the one a test driver launches in, or the
-- car's first.
local function defaultMode(car: Types.CarConfig): Types.DrivingMode
	local launch = car.launch
	return if launch then launch.mode else car.modeOrder[1]
end

-- Launch control, as a test driver does it: brake and full throttle held until the engine
-- settles at its launch speed, then the brake released. Times are from the release. A car without
-- launch control makes the same start on the brake alone.
export type LaunchResult = { time100: number, time200: number }

function DriveSim.launch(car: Types.CarConfig, dt: number, options: InputOptions?): LaunchResult
	local sim = DriveSim.new(car)
	local o: InputOptions = options or {}
	local mode = o.drivingMode or defaultMode(car)
	local hold = DriveSim.input({ throttle = 1, brake = 1, drivingMode = mode, esc = o.esc })
	while sim.time < 1.5 do
		DriveSim.frame(sim, hold, dt)
	end
	local go = DriveSim.input({ throttle = 1, drivingMode = mode, tc = o.tc, esc = o.esc })
	local start = sim.time
	local result = { time100 = math.huge, time200 = math.huge }
	while sim.time - start < 20 do
		local before = DriveSim.forwardSpeed(sim)
		DriveSim.frame(sim, go, dt)
		local after = DriveSim.forwardSpeed(sim)
		local crossed = sim.time - dt + dt * 0.5
		if before < 100 / 3.6 and after >= 100 / 3.6 then
			crossed = sim.time - dt + dt * (100 / 3.6 - before) / (after - before)
			result.time100 = crossed - start
		end
		if before < 200 / 3.6 and after >= 200 / 3.6 then
			crossed = sim.time - dt + dt * (200 / 3.6 - before) / (after - before)
			result.time200 = crossed - start
			break
		end
	end
	return result
end

-- Full brake from `speed` in a straight line, gearbox in auto. Distance is from the frame the
-- pedal goes down to the stop; deceleration is the peak of a 0.1 s average.
export type BrakeResult = { distance: number, time: number, peakDeceleration: number }

function DriveSim.brake(car: Types.CarConfig, speed: number, dt: number, options: InputOptions?): BrakeResult
	local sim = DriveSim.new(car)
	local o: InputOptions = options or {}
	DriveSim.setSpeed(sim, speed, 3)
	local mode = o.drivingMode or defaultMode(car)
	local coast = DriveSim.input({ drivingMode = mode, esc = o.esc })
	while sim.time < 0.5 do
		DriveSim.frame(sim, coast, dt)
	end
	local stop = DriveSim.input({ brake = 1, drivingMode = mode, abs = o.abs, esc = o.esc })
	local startX, start = sim.body.x, sim.time
	local window = math.max(1, math.floor(0.1 / dt + 0.5))
	local history: { number } = {}
	local peak = 0
	while sim.time - start < 10 do
		DriveSim.frame(sim, stop, dt)
		local now = DriveSim.forwardSpeed(sim)
		table.insert(history, now)
		if #history > window then
			peak = math.max(peak, (history[#history - window] - now) / (window * dt))
		end
		if now <= 0.05 then
			break
		end
	end
	return { distance = sim.body.x - startX, time = sim.time - start, peakDeceleration = peak }
end

-- Full throttle held in `gear` (manual) until the limiter has bounced for two seconds. Returns
-- the highest speed reached (m/s).
function DriveSim.gearTop(car: Types.CarConfig, gear: number, dt: number): number
	local sim = DriveSim.new(car)
	local ratio = car.gearbox.ratios[gear] * car.driveline.rearReduction
	local limiter = car.engine.limiterRpm * 2 * math.pi / 60
	DriveSim.setSpeed(sim, limiter * car.rear.tyre.radius / ratio * 0.7, gear)
	local drive = DriveSim.input({ throttle = 1, gearboxMode = "manual", drivingMode = defaultMode(car) })
	local best, firstCut = 0, math.huge
	while sim.time < 60 and sim.time < firstCut + 2 do
		local result = DriveSim.frame(sim, drive, dt)
		best = math.max(best, DriveSim.forwardSpeed(sim))
		if result.telemetry.limiter and firstCut == math.huge then
			firstCut = sim.time
		end
	end
	return best
end

-- Flat out in auto from `fromSpeed` in top gear until speed stops rising (under 0.02 m/s in
-- 2 s). Returns speed (m/s), rpm and gear.
function DriveSim.topSpeed(car: Types.CarConfig, fromSpeed: number, dt: number): (number, number, number)
	local sim = DriveSim.new(car)
	DriveSim.setSpeed(sim, fromSpeed, #car.gearbox.ratios)
	local drive = DriveSim.input({ throttle = 1, drivingMode = defaultMode(car) })
	local result = DriveSim.frame(sim, drive, dt)
	local last, lastTime = DriveSim.forwardSpeed(sim), sim.time
	while sim.time < 300 do
		result = DriveSim.frame(sim, drive, dt)
		if sim.time - lastTime >= 2 then
			local now = DriveSim.forwardSpeed(sim)
			if now - last < 0.02 then
				break
			end
			last, lastTime = now, sim.time
		end
	end
	return DriveSim.forwardSpeed(sim), result.telemetry.rpm, result.telemetry.gear
end

-- Steering input that aims the car at a point `lookahead` m ahead on a circle of `radius` m
-- centred to the right of the start, turning right (pure pursuit).
local function pursue(sim: Sim, radius: number, lookahead: number): number
	local car, body = sim.car, sim.body
	local dx, dy = body.x, body.y - radius
	local angle = math.atan2(dx, -dy) + lookahead / radius
	local aimX, aimY = radius * math.sin(angle), radius - radius * math.cos(angle)
	local c, s = math.cos(body.heading), math.sin(body.heading)
	local ax, ay = aimX - body.x, aimY - body.y
	local alpha = math.atan2(ay * c - ax * s, ax * c + ay * s)
	local roadAngle = math.atan(2 * car.wheelbase * math.sin(alpha) / lookahead)
	local forward = DriveSim.forwardSpeed(sim)
	local config = car.steering
	local t =
		math.clamp((forward - config.lowRatioSpeed) / (config.highRatioSpeed - config.lowRatioSpeed), 0, 1)
	local ratio = config.lowSpeedRatio + (config.highSpeedRatio - config.lowSpeedRatio) * t
	return math.clamp(roadAngle * ratio / (config.lockToLockTurns * math.pi), -1, 1)
end

-- Constant-radius skidpad (ISO 4138 style), assists off: pure-pursuit steering on a right-hand
-- circle with speed ramped slowly. Returns the highest lateral acceleration (g, the 1 s average
-- of forward speed × yaw rate) held while the car stays within 1.5 m of the circle.
function DriveSim.skidpad(
	car: Types.CarConfig,
	radius: number,
	dt: number,
	drivingMode: Types.DrivingMode?
): number
	local sim = DriveSim.new(car)
	local mode = drivingMode or defaultMode(car)
	local startSpeed = math.sqrt(0.6 * World.GRAVITY_MPS2 * radius)
	DriveSim.setSpeed(sim, startSpeed, 2)
	local window = math.max(1, math.floor(1 / dt + 0.5))
	local samples: { number } = {}
	local sum, best = 0, 0
	while sim.time < 200 do
		local forward = DriveSim.forwardSpeed(sim)
		local target = startSpeed + 0.08 * sim.time
		local input = DriveSim.input({
			throttle = math.clamp(0.3 + 0.8 * (target - forward), 0, 1),
			steer = pursue(sim, radius, 0.4 * radius),
			drivingMode = mode,
			abs = false,
			tc = false,
			esc = false,
		})
		DriveSim.frame(sim, input, dt)
		local body = sim.body
		local offCircle = math.abs(math.sqrt(body.x * body.x + (body.y - radius) ^ 2) - radius)
		local lateral = DriveSim.forwardSpeed(sim) * body.yawRate
		table.insert(samples, lateral)
		sum += lateral
		if #samples > window then
			sum -= table.remove(samples, 1) :: number
		end
		if offCircle > 1.5 and sim.time > 2 then
			break
		end
		if #samples == window then
			best = math.max(best, sum / window)
		end
	end
	return best / World.GRAVITY_MPS2
end

-- Parked with nothing pressed for `seconds`, after a 2 cm drop onto the springs. Returns the
-- largest horizontal distance from the start (m) and the largest horizontal speed over the
-- last 20 s (m/s).
function DriveSim.rest(car: Types.CarConfig, seconds: number, dt: number): (number, number)
	local sim = DriveSim.new(car)
	sim.body.heave = 0.02
	local idle = DriveSim.input({ drivingMode = defaultMode(car) })
	local drift, jitter = 0, 0
	while sim.time < seconds do
		DriveSim.frame(sim, idle, dt)
		local body = sim.body
		drift = math.max(drift, math.sqrt(body.x * body.x + body.y * body.y))
		if sim.time > seconds - 20 then
			jitter = math.max(jitter, math.sqrt(body.vx * body.vx + body.vy * body.vy))
		end
	end
	return drift, jitter
end

return table.freeze(DriveSim)
