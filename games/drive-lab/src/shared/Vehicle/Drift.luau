--!strict
--[[
	The drift button: an arcade drift (docs/research/13_drifting.md, issue #195). Held above a speed
	with the steering past a gate, it engages a drift in which the steering rotates the car and the
	direction of travel follows the heading, so the car swings round a corner in a short distance.
	Two forces at the centre of mass do it, on top of the tyres:
	- a yaw torque that brings the yaw rate to what the steering asks;
	- a sideways force that turns the velocity onto the heading, keeping its speed.

	The second is deliberately not physical: it can pass what tyres could hold. The yaw torque also
	cancels the tyres' own yaw moment, so the nose answers the drift rather than the tyres. The slide
	costs speed in proportion to the slip. The tyres keep a share of their grip (the rear's for
	driving too, so power spins them rather than launching the car out of the turn), and the front
	wheels follow the front axle's path. Released, the drift ends without swinging the nose back: the
	travel keeps turning onto the heading until the body slip is small, while the yaw follows what
	the player's own steering asks.

	`update` runs once a frame; `forces` and `grip` run every substep, on the model's predicted
	motion, so the law does not depend on the frame rate.
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
	-- After a drift: the travel is still turning onto the heading.
	exiting: boolean,
	exitTime: number,
	-- Yaw rate (rad/s) the drift brings the car to: the steering's while held, the player's own
	-- steering's (the model's reference) on the way out.
	yawTarget: number,
	-- Body slip (rad) the drift settles at for the steering held now.
	target: number,
}

local Drift = {}

function Drift.newState(): DriftState
	return { engagement = 0, wants = false, exiting = false, exitTime = 0, yawTarget = 0, target = 0 }
end

-- Body slip (rad), unsigned: the angle between the heading and the direction of travel.
function Drift.bodySlip(forwardSpeed: number, rightSpeed: number): number
	return math.abs(math.atan2(rightSpeed, math.abs(forwardSpeed)))
end

function Drift.engaged(state: DriftState): boolean
	return state.engagement > 0
end

-- Whether the drift's forces act: engaged, or ending.
function Drift.active(state: DriftState): boolean
	return state.engagement > 0 or state.exiting
end

-- Whether the assists are the drift's (TC relaxed, ESC aside) rather than the mode's.
function Drift.assisting(state: DriftState): boolean
	return state.engagement > Config.ENGAGED or state.exiting
end

-- Yaw rate (rad/s) a full steering input asks at `speed` (m/s).
function Drift.turnRate(profile: Types.DriftProfile, speed: number): number
	return math.min(profile.turnRate, profile.turnAccel / math.max(speed, 1))
end

-- Once a frame: the gate, the engagement's ramp, the exit and the yaw target. `steer` is the
-- player's shaped input in [−1, 1], `reference` the yaw rate (rad/s) the player's own steering
-- asks of the car.
function Drift.update(
	profile: Types.DriftProfile,
	state: DriftState,
	held: boolean,
	steer: number,
	forwardSpeed: number,
	rightSpeed: number,
	reference: number,
	dt: number
)
	local slip = Drift.bodySlip(forwardSpeed, rightSpeed)
	local speed = math.sqrt(forwardSpeed * forwardSpeed + rightSpeed * rightSpeed)
	local wasActive = Drift.active(state)
	state.wants = held
		and forwardSpeed > 0
		and speed >= Config.MIN_SPEED
		and (math.abs(steer) >= Config.STEER_GATE or slip > Config.SLIDE_GATE)
	state.engagement = if state.wants
		then math.min(1, state.engagement + dt / Config.RISE_TIME)
		else math.max(0, state.engagement - dt / Config.FALL_TIME)
	if state.wants then
		state.exiting, state.exitTime = false, 0
	elseif wasActive then
		state.exitTime += dt
		state.exiting = forwardSpeed > 0 and slip > Config.EXIT_SLIP and state.exitTime < Config.EXIT_TIME
	end
	local rate = steer * Drift.turnRate(profile, speed)
	state.yawTarget = if state.wants then rate else reference
	state.target = if state.wants then math.abs(rate) / profile.alignRate else 0
end

-- The steering input the wheels get: the player's, blended by the engagement toward the front
-- axle's path, so the front tyres follow the car rather than steer it.
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
	local perRadian = Steering.ratio(car.steering, forwardSpeed) / Steering.maxWheelAngle(car.steering)
	local assisted = math.clamp(path * perRadian, -1, 1)
	return player + state.engagement * (assisted - player)
end

-- The share of the front tyres' sideways grip and of the rear tyres' grip kept now.
function Drift.grip(profile: Types.DriftProfile, state: DriftState): (number, number)
	local engagement = state.engagement
	return 1 - engagement * (1 - profile.frontGrip), 1 - engagement * (1 - profile.rearGrip)
end

-- Every substep, from the predicted motion and the tyres' yaw moment (N·m): the drift's force at
-- the centre of mass (N, forward and right) and its yaw torque (N·m, positive turning right). All
-- zero while the drift is not active.
function Drift.forces(
	car: Types.CarConfig,
	profile: Types.DriftProfile,
	state: DriftState,
	forwardSpeed: number,
	rightSpeed: number,
	yawRate: number,
	tyreMoment: number
): (number, number, number)
	if not Drift.active(state) then
		return 0, 0, 0
	end
	local share = if state.exiting then 1 else state.engagement
	local time = if state.wants then Config.YAW_TIME else Config.EXIT_YAW_TIME
	local limit = if state.wants then Config.YAW_ACCEL else Config.EXIT_YAW_ACCEL
	local yawGap = math.clamp((state.yawTarget - yawRate) / time, -limit, limit)
	local torque = share * (car.yawInertia * yawGap - tyreMoment)
	if forwardSpeed <= 0 then
		return 0, 0, torque
	end
	-- Turning the velocity (forward, right) toward the heading at alignRate × slip keeps its length:
	-- the acceleration is that rate times the velocity turned a quarter turn. The scrub acts against
	-- the velocity.
	local slip = math.atan2(rightSpeed, forwardSpeed)
	local turn = share * car.mass * profile.alignRate * slip
	local speed = math.sqrt(forwardSpeed * forwardSpeed + rightSpeed * rightSpeed)
	local scrub = share * car.mass * profile.scrub * math.abs(slip) / speed
	return turn * rightSpeed - scrub * forwardSpeed, -turn * forwardSpeed - scrub * rightSpeed, torque
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
