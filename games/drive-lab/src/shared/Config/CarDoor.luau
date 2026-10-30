--!strict
--[[
	The driver's hand on the door's pull strap (Rules/DoorStrap decides when it holds it; the
	strap itself is in the car's model binding, the door's sounds in its catalog entry).
]]
export type StrapConfig = {
	-- The arm whose palm holds it, and the palm in that arm's space as a share of its size:
	-- tools/anim r6_fk.HAND (0, -0.85, -0.05) on a 1 x 2 x 1 arm, the point the clips aim.
	ARM: string,
	PALM: Vector3,
	-- Studs the strap's length or end must move before it is written again.
	EPSILON: number,
}

export type CarDoorConfig = {
	STRAP: StrapConfig,
}

local CarDoor: CarDoorConfig = table.freeze({
	STRAP = table.freeze({
		ARM = "Left Arm",
		PALM = Vector3.new(0, -0.425, -0.05),
		EPSILON = 0.002,
	}),
})

return CarDoor
