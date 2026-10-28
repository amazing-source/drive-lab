--!strict
export type CameraFeel = {
	BASE_FOV: number,
	SPRINT_FOV: number,
	FOV_HALF_LIFE: number,
}

local CameraFeel: CameraFeel = table.freeze({
	-- Degrees: Roblox's default at walking pace, widening with ground speed up to a full sprint.
	BASE_FOV = 70,
	SPRINT_FOV = 80,
	FOV_HALF_LIFE = 0.18,
})

return CameraFeel
