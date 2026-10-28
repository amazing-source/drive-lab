--!strict
--[[
	How far a moving body leans: toward the direction it travels, as the usual R6 tilt scripts
	do, and into turns by the share of the lean that would balance the turn (tan = v * yaw rate
	/ g). Both come from velocities, never from acceleration: a Humanoid stops dead when the
	keys are released, and an acceleration-driven lean then rocks back and forth (the owner saw
	exactly that, 2026-10-27). The lean eases to its target with no spring, so letting go brings
	the body straight back upright.
]]
local Lean = require("../Config/Lean")

export type State = {
	-- Radians: pitch positive leans forward, roll positive leans to the right.
	pitch: number,
	roll: number,
}

export type Motion = {
	-- World velocity (studs/s) and the body's facing, both horizontal.
	velocityX: number,
	velocityZ: number,
	facingX: number,
	facingZ: number,
	-- rad/s, positive turning right.
	yawRate: number,
	gravity: number,
	-- False while seated, swimming, ragdolled: the lean relaxes to upright.
	upright: boolean,
}

local BodyLean = {}

function BodyLean.new(): State
	return { pitch = 0, roll = 0 }
end

function BodyLean.target(motion: Motion): (number, number)
	if not motion.upright then
		return 0, 0
	end
	local length = math.sqrt(motion.facingX * motion.facingX + motion.facingZ * motion.facingZ)
	if length < 1e-6 then
		return 0, 0
	end
	local forwardX, forwardZ = motion.facingX / length, motion.facingZ / length
	-- Right of a facing (x, z) in Roblox's frame, where -Z is forward and +X is right.
	local rightX, rightZ = -forwardZ, forwardX
	local forward = motion.velocityX * forwardX + motion.velocityZ * forwardZ
	local right = motion.velocityX * rightX + motion.velocityZ * rightZ

	local pitch = Lean.FORWARD_TILT * math.clamp(forward / Lean.FORWARD_SPEED, -1, 1)
	local roll = Lean.SIDE_TILT * math.clamp(right / Lean.SIDE_SPEED, -1, 1)
		+ math.atan(forward * motion.yawRate / motion.gravity) * Lean.TURN_GAIN
	return math.clamp(pitch, -Lean.MAX_BACK, Lean.MAX_FORWARD),
		math.clamp(roll, -Lean.MAX_ROLL, Lean.MAX_ROLL)
end

function BodyLean.step(state: State, motion: Motion, dt: number): State
	if dt <= 0 then
		return state
	end
	local pitch, roll = BodyLean.target(motion)
	local keep = 0.5 ^ (dt / Lean.HALF_LIFE)
	return {
		pitch = pitch + (state.pitch - pitch) * keep,
		roll = roll + (state.roll - roll) * keep,
	}
end

return table.freeze(BodyLean)
