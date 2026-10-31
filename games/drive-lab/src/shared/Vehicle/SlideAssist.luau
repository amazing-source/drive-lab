--!strict
--[[
	The slide assist (docs/research/14_game_handling.md): Gran Turismo's countersteering assistance,
	in the input layer. While the car slides it steers the front wheels along the front axle's path,
	less a share of the yaw rate, at a quick hand's pace, and hands the steering back over a short
	hold once the slide has gone. A slide is the rear axle past a share of its peak slip angle and
	more saturated than the front, or the yaw rate off ESC's reference. Only the steering input
	changes: the car, its tyres and its electronics are untouched.
]]
local Electronics = require("./Electronics")
local Geometry = require("./Geometry")
local Steering = require("./Steering")
local Types = require("../Config/Cars/Types")

-- What the assist reads besides the chassis motion, set by the model each frame: the notch's
-- values, the rear wheels' angle (rad) and the surface's mean grip from the frame before. `motion`
-- is a scratch table for ESC's yaw reference.
export type Context = {
	profile: Types.SlideAssistProfile,
	notch: Types.SlideAssistNotch,
	rearAngle: number,
	grip: number,
	motion: Electronics.Motion,
}

local SlideAssist = {}

function SlideAssist.newContext(profile: Types.SlideAssistProfile, notch: Types.SlideAssistNotch): Context
	return {
		profile = profile,
		notch = notch,
		rearAngle = 0,
		grip = 1,
		motion = { forwardSpeed = 0, rightSpeed = 0, yawRate = 0, frontSteer = 0, rearSteer = 0, grip = 1 },
	}
end

-- How far the car slides, 0 to 1, for a steering input `steer` at `forwardSpeed` (at least the
-- profile's minimum speed, m/s), `rightSpeed` (m/s) and `yawRate` (rad/s).
function SlideAssist.measure(
	car: Types.CarConfig,
	context: Context,
	steer: number,
	forwardSpeed: number,
	rightSpeed: number,
	yawRate: number
): number
	local profile, notch = context.profile, context.notch
	local frontAngle = Steering.frontAngle(car.steering, steer, forwardSpeed)
	local front = Geometry.frontAxleDistance(car)
	local rear = car.wheelbase - front
	local frontSlip = math.abs(frontAngle - math.atan((rightSpeed + front * yawRate) / forwardSpeed))
		/ car.front.tyre.slipAngleAtPeak
	local rearSlip = math.abs(context.rearAngle - math.atan((rightSpeed - rear * yawRate) / forwardSpeed))
		/ car.rear.tyre.slipAngleAtPeak
	local axle = if rearSlip > frontSlip
		then math.clamp((rearSlip - notch.rearSlipStart) / profile.rearSlipBand, 0, 1)
		else 0
	local motion = context.motion
	motion.forwardSpeed, motion.rightSpeed, motion.yawRate = forwardSpeed, rightSpeed, yawRate
	motion.frontSteer, motion.rearSteer, motion.grip = frontAngle, context.rearAngle, context.grip
	local reference = Electronics.referenceYawRate(car, motion)
	local yawError = if yawRate * reference >= 0
		then math.abs(yawRate) - math.abs(reference)
		else math.abs(yawRate - reference)
	local spin = math.clamp((yawError - notch.yawErrorStart) / profile.yawErrorBand, 0, 1)
	return math.max(axle, spin)
end

-- The share the assist holds over `dt`: the slide now, or the last one fading over `holdTime`.
function SlideAssist.hold(share: number, previous: number, holdTime: number, dt: number): number
	return math.max(share, previous - dt / holdTime, 0)
end

-- The steering input the assist steers to: the front axle's path, less the yaw damping.
function SlideAssist.target(
	car: Types.CarConfig,
	profile: Types.SlideAssistProfile,
	forwardSpeed: number,
	rightSpeed: number,
	yawRate: number
): number
	local path = math.atan((rightSpeed + Geometry.frontAxleDistance(car) * yawRate) / forwardSpeed)
	local perRadian = Steering.ratio(car.steering, forwardSpeed) / Steering.maxWheelAngle(car.steering)
	return math.clamp((path - profile.yawDamping * yawRate) * perRadian, -1, 1)
end

return table.freeze(SlideAssist)
