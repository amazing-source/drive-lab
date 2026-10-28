--!strict
export type Lean = {
	FORWARD_TILT: number,
	FORWARD_SPEED: number,
	SIDE_TILT: number,
	SIDE_SPEED: number,
	TURN_GAIN: number,
	MAX_FORWARD: number,
	MAX_BACK: number,
	MAX_ROLL: number,
	HALF_LIFE: number,
}

local Lean: Lean = table.freeze({
	-- Toward the direction of travel, reached at FORWARD_SPEED / SIDE_SPEED (studs/s). The run
	-- animation already leans hard, so the forward share stays small.
	FORWARD_TILT = math.rad(5),
	FORWARD_SPEED = 22,
	SIDE_TILT = math.rad(10),
	SIDE_SPEED = 16,
	-- Into a turn: the share of the lean that balances the turn, tan(lean) = speed * yaw rate / g.
	TURN_GAIN = 0.5,
	MAX_FORWARD = math.rad(10),
	MAX_BACK = math.rad(6),
	MAX_ROLL = math.rad(18),
	-- Seconds for the lean to cover half the way to its target. A plain ease, no spring, so it
	-- never swings past upright when the player lets go (owner, 2026-10-27).
	HALF_LIFE = 0.1,
})

return Lean
