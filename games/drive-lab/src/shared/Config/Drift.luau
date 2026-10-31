--!strict
--[[
	The drift every car shares (Vehicle/Drift); a car's own numbers are its `drift` profile
	(Config/Cars/Types). Angles in radians, speeds in m/s, times in seconds.
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
	-- Seconds the yaw rate takes to close most of its gap to what the drift asks, and the most
	-- angular acceleration (rad/s²) the drift may add.
	YAW_TIME: number,
	YAW_ACCEL: number,
	-- After a drift, the travel keeps turning onto the heading until the body slip is under
	-- EXIT_SLIP, for at most EXIT_TIME, while the yaw settles on what the player's steering asks
	-- within EXIT_YAW_TIME, at up to EXIT_YAW_ACCEL (rad/s²).
	EXIT_SLIP: number,
	EXIT_TIME: number,
	EXIT_YAW_TIME: number,
	EXIT_YAW_ACCEL: number,
}

local Drift: Drift = table.freeze({
	MIN_SPEED = 30 / 3.6,
	STEER_GATE = 0.25,
	SLIDE_GATE = math.rad(5),
	-- A tap of the key engages it fully: a keyboard player taps Space into a corner.
	RISE_TIME = 0.15,
	FALL_TIME = 0.5,
	ENGAGED = 0.05,
	-- Quick enough that the nose answers the key at once, slow enough not to jerk the body.
	YAW_TIME = 0.12,
	YAW_ACCEL = 8,
	-- Small enough that what is left is ordinary grip driving, long enough for any drift to close.
	EXIT_SLIP = math.rad(2),
	EXIT_TIME = 1.5,
	-- The rotation stops almost at once, so the car runs where it pointed when Space came up: about
	-- 3° more of turn at 80 km/h, against 10° at the drift's own yaw time.
	EXIT_YAW_TIME = 0.03,
	EXIT_YAW_ACCEL = 25,
})

return Drift
