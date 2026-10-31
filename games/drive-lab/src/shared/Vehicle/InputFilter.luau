--!strict
--[[
	The input layer (01 §4): turns raw device values into what the driver's hands and feet would
	do. Steering is shaped, clamped to the angle that puts the front axle at a share of its peak
	slip, then moved there as a hand turns a wheel: it speeds up, holds a capped rate and slows
	into the target, never past it (a trapezoid in time). Turning in takes longer as speed
	rises; the return to centre is slow at rest and quick on the move; turning toward the other
	side is quicker than turning in. At a game-feel notch above Realistic the slide assist
	(Vehicle/SlideAssist) takes the target over while the car slides, at its own quicker pace.
	Pedals ramp. Nothing here changes the car. The steering runs in internal steps of at most
	STEER_STEP, so every frame rate follows the same path and lands within a frame of the same
	time; the pedal ramps are exact in dt.
]]
local Geometry = require("./Geometry")
local InputHelp = require("../Config/InputHelp")
local SlideAssist = require("./SlideAssist")
local Steering = require("./Steering")
local Types = require("../Config/Cars/Types")

export type Controls = {
	steer: number,
	-- Rate of `steer` (per second), carried between frames so the steering eases.
	steerVelocity: number,
	-- Share of the steering the slide assist holds, 0 to 1.
	slide: number,
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

-- Longest internal step of the steering (s): 240 Hz, the frame-rate spec's reference.
local STEER_STEP = 1 / 240

function InputFilter.newState(): Controls
	return { steer = 0, steerVelocity = 0, slide = 0, throttle = 0, brake = 0, handbrake = 0 }
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

-- Seconds a move from `current` toward `target` would take across full lock: a return toward
-- centre, a turn toward the other side, or a turn in. The other side is a turn in sped up by
-- oppositeFactor, never the return: on the move the return is quick (the road's trail), and a
-- swing from one side to the other borrowed it, 4 to 5 times faster than turning in from 14 m/s
-- (the owner felt it as an uncontrolled flick, 2026-10-30).
function InputFilter.moveTime(
	help: InputHelp.InputHelp,
	current: number,
	target: number,
	speed: number
): number
	local speedAbs = math.abs(speed)
	local blend = help.returnBlend
	local share = math.clamp((speedAbs - blend.from) / (blend.to - blend.from), 0, 1)
	local back = help.returnTimeStill + (help.returnTimeMoving - help.returnTimeStill) * share
	if target * current >= 0 and math.abs(target) < math.abs(current) then
		return back
	end
	local turnIn = help.lockTime * (1 + speedAbs / help.rateHalvingSpeed)
	if target * current < 0 then
		return turnIn / help.oppositeFactor
	end
	return turnIn
end

-- One step of the eased move from `current` toward `target` over `time` per full lock: the
-- speed builds and falls at the rate that spends `easeShare` of the time speeding up and as
-- much slowing down, capped in between, and the step stops on the target rather than past it.
local function steerStep(
	current: number,
	velocity: number,
	target: number,
	time: number,
	easeShare: number,
	dt: number
): (number, number)
	if time <= 0 then
		return target, 0
	end
	local ease = time * easeShare
	local topSpeed = 1 / (time - ease)
	local accel = if ease > 0 then topSpeed / ease else math.huge
	local error = target - current
	local distance = math.abs(error)
	-- The fastest speed from which this step's braking still stops on the target.
	local stopSpeed = if accel == math.huge
		then math.huge
		else math.sqrt((accel * dt / 2) ^ 2 + 2 * accel * distance) - accel * dt / 2
	local wanted = math.sign(error) * math.min(stopSpeed, topSpeed)
	local change = if accel == math.huge
		then wanted - velocity
		else math.clamp(wanted - velocity, -accel * dt, accel * dt)
	local nextVelocity = velocity + change
	-- Moved at the step's new speed, as the stopping speed above assumes.
	local nextValue = current + nextVelocity * dt
	if (target - nextValue) * error <= 0 then
		return target, 0
	end
	return nextValue, nextVelocity
end

-- The share the slide assist holds this frame, and the target it blends the player's toward.
local function assist(
	car: Types.CarConfig,
	state: Controls,
	slide: SlideAssist.Context?,
	target: number,
	forwardSpeed: number,
	rightSpeed: number,
	yawRate: number,
	dt: number
): (number, number)
	if slide == nil or forwardSpeed < slide.profile.minSpeed then
		return 0, target
	end
	local profile = slide.profile
	local share = SlideAssist.measure(car, slide, state.steer, forwardSpeed, rightSpeed, yawRate)
	local held = SlideAssist.hold(share, state.slide, profile.holdTime, dt)
	if held <= 0 then
		return 0, target
	end
	local wanted = SlideAssist.target(car, profile, forwardSpeed, rightSpeed, yawRate)
	return held, math.clamp(target + held * (wanted - target), -1, 1)
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
	dt: number,
	slide: SlideAssist.Context?
)
	local target = InputFilter.shape(help, math.clamp(raw.steer, -1, 1))
	local low, high = InputFilter.steerBounds(help, car, forwardSpeed, rightSpeed, yawRate)
	-- The limit may stop a request but never steers against the player's direction.
	if target > 0 then
		target = math.min(target, math.max(0, high))
	elseif target < 0 then
		target = math.max(target, math.min(0, low))
	end
	local held
	held, target = assist(car, state, slide, target, forwardSpeed, rightSpeed, yawRate, dt)
	state.slide = held
	local assisted = if held > 0 then slide else nil
	local easeShare = if assisted
		then assisted.profile.steerEaseShare
		elseif help.lockTime > 0 then math.min(help.easeTime / help.lockTime, 0.5)
		else 0
	local remaining = dt
	repeat
		local step = math.min(remaining, STEER_STEP)
		local time = if assisted
			then assisted.profile.steerTime
			else InputFilter.moveTime(help, state.steer, target, forwardSpeed)
		state.steer, state.steerVelocity =
			steerStep(state.steer, state.steerVelocity, target, time, easeShare, step)
		remaining -= step
	until remaining <= 1e-12

	state.throttle =
		ramp(state.throttle, math.clamp(raw.throttle, 0, 1), help.throttleRiseTime, help.throttleFallTime, dt)
	state.brake = ramp(state.brake, math.clamp(raw.brake, 0, 1), help.brakeRiseTime, help.brakeFallTime, dt)
	state.handbrake =
		ramp(state.handbrake, math.clamp(raw.handbrake, 0, 1), help.brakeRiseTime, help.brakeFallTime, dt)
end

return table.freeze(InputFilter)
