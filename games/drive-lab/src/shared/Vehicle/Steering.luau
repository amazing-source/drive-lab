--!strict
--[[
	From the steering wheel to the road wheels (01 §2.6, 02 §2.9): a speed-dependent rack ratio
	(Lamborghini Dynamic Steering), the rack's mechanical lock, Ackermann blended toward
	parallel, and rear-wheel steering as a speed-dependent gain on the front angle behind an
	actuator lag. Positive angles steer right. The input layer works upstream of this, so the
	steering-wheel angle here is what a visual wheel should show.
]]
local Geometry = require("./Geometry")
local Types = require("../Config/Cars/Types")

export type SteeringState = {
	rearAngle: number,
	-- Last road-wheel angles per wheel (rad).
	angles: { number },
}

local Steering = {}

function Steering.newState(): SteeringState
	return { rearAngle = 0, angles = table.create(Geometry.WHEELS, 0) }
end

function Steering.maxWheelAngle(config: Types.SteeringConfig): number
	return config.lockToLockTurns * math.pi
end

function Steering.ratio(config: Types.SteeringConfig, speed: number): number
	local t = math.clamp(
		(math.abs(speed) - config.lowRatioSpeed) / (config.highRatioSpeed - config.lowRatioSpeed),
		0,
		1
	)
	return config.lowSpeedRatio + (config.highSpeedRatio - config.lowSpeedRatio) * t
end

-- Mean front road-wheel angle for a steering input in [−1, 1] at `speed`.
function Steering.frontAngle(config: Types.SteeringConfig, steer: number, speed: number): number
	local angle = steer * Steering.maxWheelAngle(config) / Steering.ratio(config, speed)
	return math.clamp(angle, -config.maxRoadWheelAngle, config.maxRoadWheelAngle)
end

function Steering.rearGain(config: Types.SteeringConfig, speed: number): number
	local points = config.rearGain
	local magnitude = math.abs(speed)
	if magnitude <= points[1].speed then
		return points[1].gain
	end
	for index = 2, #points do
		local high = points[index]
		if magnitude <= high.speed then
			local low = points[index - 1]
			return low.gain + (high.gain - low.gain) * (magnitude - low.speed) / (high.speed - low.speed)
		end
	end
	return points[#points].gain
end

-- Left and right angles for a mean angle `angle`: ideal Ackermann puts both wheels' axes
-- through one point on the rear axle line; `ackermann` blends from parallel (0) to that (1).
function Steering.ackermann(car: Types.CarConfig, angle: number): (number, number)
	if math.abs(angle) < 1e-6 then
		return angle, angle
	end
	local wheelbase, halfTrack = car.wheelbase, car.front.track / 2
	local radius = wheelbase / math.tan(math.abs(angle))
	local inner = math.atan(wheelbase / (radius - halfTrack))
	local outer = math.atan(wheelbase / (radius + halfTrack))
	local blend = car.steering.ackermann
	local magnitude = math.abs(angle)
	inner = magnitude + (inner - magnitude) * blend
	outer = magnitude + (outer - magnitude) * blend
	if angle > 0 then
		return outer, inner
	end
	return -inner, -outer
end

-- Updates the four road-wheel angles for steering input `steer` at forward `speed`.
function Steering.update(car: Types.CarConfig, state: SteeringState, steer: number, speed: number, dt: number)
	local config = car.steering
	local front = Steering.frontAngle(config, steer, speed)
	local left, right = Steering.ackermann(car, front)
	local raw = Steering.rearGain(config, speed) * front
	local limit = if raw * front < 0 then config.rearMaxOpposite else config.rearMaxSame
	local target = math.clamp(raw, -limit, limit)
	state.rearAngle = target + (state.rearAngle - target) * math.exp(-dt / config.rearActuatorTime)
	local angles = state.angles
	angles[Geometry.FRONT_LEFT] = left
	angles[Geometry.FRONT_RIGHT] = right
	angles[Geometry.REAR_LEFT] = state.rearAngle
	angles[Geometry.REAR_RIGHT] = state.rearAngle
end

return table.freeze(Steering)
