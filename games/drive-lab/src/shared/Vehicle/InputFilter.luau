--!strict
--[[
	The input layer (01 §4): turns raw device values into what the driver's hands and feet would
	do. Steering is shaped, clamped to the angle that puts the front axle at a share of its peak
	slip, then rate-limited, returning to centre faster than it turns in and slower as speed
	rises. Pedals ramp. Nothing here changes the car; every rate is exact in dt, so a frame rate
	changes nothing either.
]]
local Geometry = require("./Geometry")
local InputHelp = require("../Config/InputHelp")
local Steering = require("./Steering")
local Types = require("../Config/Cars/Types")

export type Controls = {
	steer: number,
	throttle: number,
	brake: number,
	handbrake: number,
}

-- Raw device values the filter reads: steer in [−1, 1], pedals in [0, 1].
export type RawControls = {
	steer: number,
	throttle: number,
	brake: number,
	handbrake: number,
}

local InputFilter = {}

function InputFilter.newState(): Controls
	return { steer = 0, throttle = 0, brake = 0, handbrake = 0 }
end

function InputFilter.shape(help: InputHelp.InputHelp, value: number): number
	local magnitude = math.abs(value)
	if magnitude <= help.deadzone then
		return 0
	end
	local scaled = math.min(1, (magnitude - help.deadzone) / (1 - help.deadzone)) ^ help.stickExponent
	return if value < 0 then -scaled else scaled
end

-- Steering inputs (in [−1, 1] units) that put the front axle at ±targetSlip of its peak slip
-- angle. The front axle moves at atan((v_y + a·r) / v_x) from the heading, so steering past it
-- by the target slip reaches the target (01 §4 point 3); a slide shifts both bounds, which
-- opens countersteer by itself.
function InputFilter.steerBounds(
	help: InputHelp.InputHelp,
	car: Types.CarConfig,
	forwardSpeed: number,
	rightSpeed: number,
	yawRate: number
): (number, number)
	if not help.dynamicLimit or forwardSpeed < help.limitMinSpeed then
		return -1, 1
	end
	local front = Geometry.frontAxleDistance(car)
	local heading = math.atan((rightSpeed + front * yawRate) / forwardSpeed)
	local slip = help.targetSlip * car.front.tyre.slipAngleAtPeak
	local perRadian = Steering.ratio(car.steering, forwardSpeed) / Steering.maxWheelAngle(car.steering)
	return (heading - slip) * perRadian, (heading + slip) * perRadian
end

local function ramp(current: number, target: number, riseTime: number, fallTime: number, dt: number): number
	if target > current then
		return if riseTime <= 0 then target else math.min(target, current + dt / riseTime)
	end
	return if fallTime <= 0 then target else math.max(target, current - dt / fallTime)
end

function InputFilter.update(
	help: InputHelp.InputHelp,
	car: Types.CarConfig,
	state: Controls,
	raw: RawControls,
	forwardSpeed: number,
	rightSpeed: number,
	yawRate: number,
	dt: number
)
	local target = InputFilter.shape(help, math.clamp(raw.steer, -1, 1))
	local low, high = InputFilter.steerBounds(help, car, forwardSpeed, rightSpeed, yawRate)
	-- The limit may stop a request but never steers against the player's direction.
	if target > 0 then
		target = math.min(target, math.max(0, high))
	elseif target < 0 then
		target = math.max(target, math.min(0, low))
	end
	local current = state.steer
	local rate = help.steerRate / (1 + math.abs(forwardSpeed) / help.rateHalvingSpeed)
	local turningIn = math.abs(target) > math.abs(current) and target * current >= 0
	if not turningIn then
		rate *= help.returnRateFactor
	end
	local step = rate * dt
	state.steer = current + math.clamp(target - current, -step, step)

	state.throttle =
		ramp(state.throttle, math.clamp(raw.throttle, 0, 1), help.throttleRiseTime, help.throttleFallTime, dt)
	state.brake = ramp(state.brake, math.clamp(raw.brake, 0, 1), help.brakeRiseTime, help.brakeFallTime, dt)
	state.handbrake =
		ramp(state.handbrake, math.clamp(raw.handbrake, 0, 1), help.brakeRiseTime, help.brakeFallTime, dt)
end

return table.freeze(InputFilter)
