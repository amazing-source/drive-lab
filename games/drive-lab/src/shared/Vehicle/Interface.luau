--!strict
--[[
	The contract between the vehicle model and whatever drives it: the Roblox glue in play, the
	offline harness in tests. SI units. Car frame: forward, right, up. Wheels are ordered front
	left, front right, rear left, rear right (Vehicle/Geometry).
]]
local Gearbox = require("./Gearbox")
local Types = require("../Config/Cars/Types")

export type Assists = { abs: boolean, tc: boolean, esc: boolean }

export type DriverInput = {
	-- Raw device values; the input filter runs inside the step.
	throttle: number,
	brake: number,
	steer: number,
	handbrake: number,
	-- Paddle presses: true only on the frame the paddle goes down.
	shiftUp: boolean,
	shiftDown: boolean,
	gearboxMode: Gearbox.GearboxMode,
	drivingMode: Types.DrivingMode,
	assists: Assists,
}

export type WheelContact = {
	grounded: boolean,
	-- m from full extension, up to the configured travel.
	compression: number,
	-- m/s, positive while compressing.
	compressionSpeed: number,
	-- Velocity of the contact point in the CAR frame (m/s); the model rotates it into the
	-- wheel's frame by its own steer angle.
	forwardSpeed: number,
	rightSpeed: number,
	-- Surface friction multiplier: 1 on dry asphalt, below 1 on wet.
	grip: number,
}

export type ChassisMotion = {
	-- At the centre of mass, car frame, m/s.
	forwardSpeed: number,
	rightSpeed: number,
	-- rad/s, positive turning right.
	yawRate: number,
}

export type WheelResult = {
	-- N along the suspension axis, pushing the body up at the wheel's mount.
	suspensionForce: number,
	-- N in the car frame at the contact patch, averaged over the frame.
	forwardForce: number,
	rightForce: number,
	steerAngle: number,
	-- rad/s, positive rolling forward.
	spin: number,
	slipRatio: number,
	slipAngle: number,
	-- N carried by the tyre.
	load: number,
	-- Combined slip over the slip at peak grip: 1 is at the limit. For squeal and rumble.
	combinedSlip: number,
}

export type Telemetry = {
	rpm: number,
	-- −1 reverse, 0 neutral, 1 to 7.
	gear: number,
	-- Magnitude of the forward speed.
	speedKmh: number,
	-- Throttle the engine actually got, after the input filter, assists, shift cut and blip.
	throttle: number,
	-- Brake pedal after the input filter, scaled by the mean ABS pressure.
	brake: number,
	absActive: boolean,
	tcActive: boolean,
	escActive: boolean,
	shifting: boolean,
	-- Share of the gearbox output torque sent to the front axle through the coupling.
	frontTorqueShare: number,
	clutch: number,
	limiter: boolean,
	-- 0 closed (high downforce) to 1 open (low drag).
	alaOpen: number,
	-- Steering input after the input filter, in [−1, 1]; times the lock gives the wheel angle.
	steer: number,
	rearSteerAngle: number,
}

export type StepResult = {
	wheels: { WheelResult },
	-- N, against the car's velocity through the air, at the centre of mass.
	aeroDrag: number,
	-- N, down, at each axle's line.
	downforceFront: number,
	downforceRear: number,
	telemetry: Telemetry,
}

return {}
