--!strict
--[[
	The engine as a torque source on its own inertia (01 §2.3): full-load torque interpolated
	from the car's table, closed-throttle drag (friction and pumping) blended in by throttle,
	a fuel-cut limiter with hysteresis and a simple idle governor. The drag is handed to the
	driveline as a friction capacity rather than a torque, so engine braking can stop the
	crank but never spin it backwards.
]]
local Types = require("../Config/Cars/Types")

local RAD_PER_RPM = 2 * math.pi / 60

-- Share of idle speed over which the governor goes from closed to fully open.
local IDLE_BAND = 0.15
-- The governor aims a little above idle so it settles at idle while carrying the drag.
local IDLE_AIM = 1.03

export type Engine = {
	curveSpeeds: { number },
	curveTorques: { number },
	dragSpeed: number,
	dragTorque: number,
	dragSlope: number,
	inertia: number,
	idleSpeed: number,
	limiterSpeed: number,
	resumeSpeed: number,
	launchSpeed: number,
}

export type EngineState = {
	speed: number,
	limiterCut: boolean,
}

local Engine = {
	RAD_PER_RPM = RAD_PER_RPM,
}

function Engine.prepare(config: Types.EngineConfig): Engine
	local speeds = table.create(#config.torqueCurve, 0)
	local torques = table.create(#config.torqueCurve, 0)
	for index, point in config.torqueCurve do
		speeds[index] = point.rpm * RAD_PER_RPM
		torques[index] = point.torque
	end
	local lowSpeed = config.dragLow.rpm * RAD_PER_RPM
	local highSpeed = config.dragHigh.rpm * RAD_PER_RPM
	return table.freeze({
		curveSpeeds = table.freeze(speeds),
		curveTorques = table.freeze(torques),
		dragSpeed = lowSpeed,
		dragTorque = config.dragLow.torque,
		dragSlope = (config.dragHigh.torque - config.dragLow.torque) / (highSpeed - lowSpeed),
		inertia = config.inertia,
		idleSpeed = config.idleRpm * RAD_PER_RPM,
		limiterSpeed = config.limiterRpm * RAD_PER_RPM,
		resumeSpeed = (config.limiterRpm - config.limiterHysteresis) * RAD_PER_RPM,
		launchSpeed = config.launchRpm * RAD_PER_RPM,
	})
end

function Engine.newState(engine: Engine): EngineState
	return { speed = engine.idleSpeed, limiterCut = false }
end

-- Full-load torque at `speed` (rad/s). Below the table it falls linearly to zero at rest;
-- above it, the last value holds (the limiter cuts before it matters).
function Engine.fullTorque(engine: Engine, speed: number): number
	local speeds, torques = engine.curveSpeeds, engine.curveTorques
	if speed <= speeds[1] then
		return torques[1] * math.max(speed, 0) / speeds[1]
	end
	local last = #speeds
	if speed >= speeds[last] then
		return torques[last]
	end
	local low, high = 1, last
	while high - low > 1 do
		local middle = (low + high) // 2
		if speeds[middle] <= speed then
			low = middle
		else
			high = middle
		end
	end
	local t = (speed - speeds[low]) / (speeds[high] - speeds[low])
	return torques[low] + (torques[high] - torques[low]) * t
end

-- Closed-throttle friction and pumping torque (a magnitude), linear in speed through the two
-- configured points and fading to zero at rest.
function Engine.dragTorque(engine: Engine, speed: number): number
	if speed <= engine.dragSpeed then
		return engine.dragTorque * math.max(speed, 0) / engine.dragSpeed
	end
	return engine.dragTorque + engine.dragSlope * (speed - engine.dragSpeed)
end

-- Throttle the idle governor adds below idle.
function Engine.idleThrottle(engine: Engine, speed: number): number
	local aim = engine.idleSpeed * IDLE_AIM
	return math.clamp((aim - speed) / (engine.idleSpeed * IDLE_BAND), 0, 1)
end

-- Fuel cut with hysteresis against `limit` (rad/s): cut at the limit, resume once speed has
-- fallen by the configured hysteresis.
function Engine.updateLimiter(engine: Engine, state: EngineState, limit: number): boolean
	if state.speed >= limit then
		state.limiterCut = true
	elseif state.speed < limit - (engine.limiterSpeed - engine.resumeSpeed) then
		state.limiterCut = false
	end
	return state.limiterCut
end

-- Splits the engine's output at `throttle` into the torque it drives with and the drag
-- capacity the driveline applies as friction.
function Engine.output(engine: Engine, speed: number, throttle: number): (number, number)
	return throttle * Engine.fullTorque(engine, speed), (1 - throttle) * Engine.dragTorque(engine, speed)
end

return table.freeze(Engine)
