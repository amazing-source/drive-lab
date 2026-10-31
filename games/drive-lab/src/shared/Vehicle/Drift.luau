--!strict
--[[
	The drift button (docs/research/13_drifting.md §5). Held above a speed with the steering past a
	gate, it engages a drift that holds the body slip the steering asks for, through forces the
	model already has: the front wheels follow the front axle's path plus a slip toward the turn
	(the geometry of InputFilter.steerBounds), the rear tyres' grip and the engine's torque follow
	the angle, traction control relaxes, ESC stands aside, and an all-wheel-drive car sends less
	forward. Released, the target goes to zero and the engagement fades, so the drift steers itself
	out. Below the gate the button is the handbrake it always was.

	`update` runs once a frame; the grip and torque shares run every substep, on the model's
	predicted motion, so the law does not depend on the frame rate.
]]
local Config = require("../Config/Drift")
local Geometry = require("./Geometry")
local Steering = require("./Steering")
local Types = require("../Config/Cars/Types")

export type DriftState = {
	-- 0 to 1: how far the drift is engaged.
	engagement: number,
	-- The gate is met this frame: the button is held, fast enough, steered or already sliding.
	wants: boolean,
	-- 1 for a drift to the right, −1 to the left: the turn it started in.
	direction: number,
	-- Body slip (rad) the drift aims for.
	target: number,
	-- Body slip (rad) at the last frame, and its rate (rad/s) over that frame.
	frameSlip: number,
	frameRate: number,
	-- Body slip (rad) at the last substep, for the substep's own rate; seeded each frame while the
	-- drift is not engaged, so an idle car does no work in its substeps.
	substepSlip: number,
}

local Drift = {}

function Drift.newState(): DriftState
	return {
		engagement = 0,
		wants = false,
		direction = 1,
		target = 0,
		frameSlip = 0,
		frameRate = 0,
		substepSlip = 0,
	}
end

-- Body slip (rad), unsigned: the angle between the heading and the direction of travel.
function Drift.bodySlip(forwardSpeed: number, rightSpeed: number): number
	return math.abs(math.atan2(rightSpeed, math.abs(forwardSpeed)))
end

function Drift.engaged(state: DriftState): boolean
	return state.engagement > 0
end

-- Whether the assists are the drift's (TC relaxed, ESC aside) rather than the mode's.
function Drift.assisting(state: DriftState): boolean
	return state.engagement > Config.ENGAGED
end

-- The target body slip for a steering input `steer` (shaped, in [−1, 1]).
function Drift.target(profile: Types.DriftProfile, state: DriftState, steer: number): number
	if not state.wants then
		return 0
	end
	local toward = steer * state.direction
	if toward <= -Config.STEER_GATE then
		return 0
	end
	local reach = math.clamp((toward - Config.STEER_GATE) / (1 - Config.STEER_GATE), 0, 1)
	return Config.MIN_ANGLE + (profile.maxAngle - Config.MIN_ANGLE) * reach
end

-- Once a frame: the gate, the engagement's ramp, the direction and the target.
function Drift.update(
	profile: Types.DriftProfile,
	state: DriftState,
	held: boolean,
	steer: number,
	forwardSpeed: number,
	rightSpeed: number,
	dt: number
)
	local slip = Drift.bodySlip(forwardSpeed, rightSpeed)
	state.frameRate = (slip - state.frameSlip) / dt
	state.frameSlip = slip
	local speed = math.sqrt(forwardSpeed * forwardSpeed + rightSpeed * rightSpeed)
	state.wants = held
		and speed >= Config.MIN_SPEED
		and (math.abs(steer) >= Config.STEER_GATE or slip > Config.SLIDE_GATE)
	if state.wants and state.engagement == 0 then
		state.direction = if steer < 0 then -1 elseif steer > 0 then 1 elseif rightSpeed > 0 then -1 else 1
	end
	if state.engagement <= 0 then
		state.substepSlip = slip
	end
	state.engagement = if state.wants
		then math.min(1, state.engagement + dt / Config.RISE_TIME)
		else math.max(0, state.engagement - dt / Config.FALL_TIME)
	state.target = Drift.target(profile, state, steer)
end

-- The steering input the wheels get: the player's, blended by the engagement toward the front
-- axle's path plus the commanded slip toward the turn.
function Drift.steer(
	car: Types.CarConfig,
	state: DriftState,
	player: number,
	forwardSpeed: number,
	rightSpeed: number,
	yawRate: number
): number
	if state.engagement <= 0 then
		return player
	end
	local path =
		math.atan((rightSpeed + Geometry.frontAxleDistance(car) * yawRate) / math.max(forwardSpeed, 1))
	local over = state.frameSlip - state.target
	local command = math.clamp(
		Config.FRONT_SLIP - Config.STEER_OVER_GAIN * over - Config.STEER_RATE_GAIN * state.frameRate,
		-1,
		1
	)
	local angle = path + state.direction * command * car.front.tyre.slipAngleAtPeak
	local perRadian = Steering.ratio(car.steering, forwardSpeed) / Steering.maxWheelAngle(car.steering)
	local assisted = math.clamp(angle * perRadian, -1, 1)
	return player + state.engagement * (assisted - player)
end

-- Every substep, from the predicted motion: the rear tyres' grip share and the engine torque's
-- share. Both are exactly 1 while the drift is not engaged.
function Drift.shares(
	profile: Types.DriftProfile,
	state: DriftState,
	forwardSpeed: number,
	rightSpeed: number,
	dt: number
): (number, number)
	local engagement = state.engagement
	if engagement <= 0 then
		return 1, 1
	end
	local slip = Drift.bodySlip(forwardSpeed, rightSpeed)
	local rate = (slip - state.substepSlip) / dt
	state.substepSlip = slip
	local over = slip - state.target
	local share = profile.holdShare
		+ Config.ANGLE_GAIN * over / math.max(state.target, Config.SLIDE_GATE)
		+ Config.ANGLE_RATE_GAIN * rate
	local grip = 1 - engagement * (1 - math.clamp(share, Config.FLOOR_SHARE, 1))
	local torque = 1 - engagement * math.clamp(over / Config.TORQUE_BAND, 0, 1)
	return grip, torque
end

-- Traction control's slip threshold: the mode's, relaxed toward the profile's while drifting.
function Drift.tcSlip(profile: Types.DriftProfile, state: DriftState, modeSlip: number): number
	if not Drift.assisting(state) then
		return modeSlip
	end
	return modeSlip + state.engagement * (math.max(modeSlip, profile.tcSlip) - modeSlip)
end

-- The most the coupling may send forward (N·m): the mode's capacity, capped toward the profile's
-- share of the gearbox output while drifting.
function Drift.couplingCapacity(
	profile: Types.DriftProfile,
	state: DriftState,
	capacity: number,
	outputTorque: number
): number
	if state.engagement <= 0 then
		return capacity
	end
	local cap = profile.frontShare * math.abs(outputTorque)
	return capacity + state.engagement * (math.min(capacity, cap) - capacity)
end

return table.freeze(Drift)
