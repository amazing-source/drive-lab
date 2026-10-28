--!strict
export type Look = {
	MAX_YAW: number,
	MAX_PITCH_UP: number,
	MAX_PITCH_DOWN: number,
	SEND_INTERVAL: number,
	SEND_THRESHOLD: number,
	SMOOTHING_HALF_LIFE: number,
	LOCAL_HALF_LIFE: number,
}

-- Inside the active range of a human neck (about 80 degrees of rotation each way, 50 of flexion,
-- 60 of extension), so the head never reaches a pose a person cannot hold.
local Look: Look = table.freeze({
	MAX_YAW = math.rad(70),
	MAX_PITCH_UP = math.rad(55),
	MAX_PITCH_DOWN = math.rad(50),
	SEND_INTERVAL = 0.1,
	SEND_THRESHOLD = math.rad(1),
	SMOOTHING_HALF_LIFE = 0.06,
	-- The owner's own head trails the camera a little, as a neck does, instead of snapping.
	LOCAL_HALF_LIFE = 0.1,
})

return Look
