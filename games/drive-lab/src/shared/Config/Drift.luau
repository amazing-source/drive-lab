--!strict
--[[
	The drift every car shares (Rules/Drift); a car's own numbers are its `drift` profile
	(Config/Cars/Types). Angles in radians, speeds in m/s. Why each value is what it is:
	docs/research/13_drifting.md §5.
]]
export type Drift = {
	-- Below this speed the drift button is only the handbrake.
	MIN_SPEED: number,
	-- Steering input past which the button starts a drift, or a body slip already past SLIDE_GATE.
	STEER_GATE: number,
	SLIDE_GATE: number,
	-- Seconds the engagement takes to rise to 1 and to fall back to 0.
	RISE_TIME: number,
	FALL_TIME: number,
	-- Engagement under which traction control's own threshold and ESC are back.
	ENGAGED: number,
	-- Target body slip with the steering centred; full lock toward the turn asks the car's maximum.
	MIN_ANGLE: number,
	-- Rear grip share: the profile's hold share at the target, plus ANGLE_GAIN per unit of the
	-- angle's relative excess and ANGLE_RATE_GAIN per rad/s of its growth, never under FLOOR_SHARE.
	FLOOR_SHARE: number,
	ANGLE_GAIN: number,
	ANGLE_RATE_GAIN: number,
	-- Body slip past the target over which the engine's torque fades out.
	TORQUE_BAND: number,
	-- The front tyres' slip toward the turn, as a share of their peak, at the target; less by
	-- STEER_OVER_GAIN per rad over it and STEER_RATE_GAIN per rad/s of growth.
	FRONT_SLIP: number,
	STEER_OVER_GAIN: number,
	STEER_RATE_GAIN: number,
}

local Drift: Drift = table.freeze({
	MIN_SPEED = 30 / 3.6,
	STEER_GATE = 0.25,
	SLIDE_GATE = math.rad(5),
	RISE_TIME = 0.25,
	FALL_TIME = 0.5,
	ENGAGED = 0.05,
	MIN_ANGLE = math.rad(15),
	FLOOR_SHARE = 0.45,
	ANGLE_GAIN = 0.8,
	ANGLE_RATE_GAIN = 0.01 / math.rad(1),
	TORQUE_BAND = math.rad(10),
	FRONT_SLIP = 0.6,
	STEER_OVER_GAIN = 1 / math.rad(10),
	STEER_RATE_GAIN = 1 / math.rad(70),
})

return Drift
