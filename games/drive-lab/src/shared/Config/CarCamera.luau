--!strict
--[[
	The driving cameras. Distances are metres (the camera converts them with Units, so views keep
	their framing at any world scale); angles are radians.
]]
export type View = "Chase" | "Cockpit" | "Hood"

export type CarCamera = {
	VIEWS: { View },
	CHASE_DISTANCE: number,
	CHASE_HEIGHT: number,
	CHASE_LOOK_HEIGHT: number,
	CHASE_LOOK_AHEAD: number,
	HOOD_FORWARD: number,
	HOOD_HEIGHT: number,
	EYE_FORWARD: number,
	EYE_UP: number,
	EYE_RANGE: { forward: { number }, up: { number }, step: number },
	BASE_FOV: number,
	FOV_GAIN: number,
	FOV_SPEED: number,
	FOV_KICK: { perG: number, maxG: number, attack: number, release: number, cockpit: number },
	LOOK_SENSITIVITY: number,
	LOOK_RETURN_HALF_LIFE: number,
	MAX_LOOK_YAW: number,
	MAX_LOOK_PITCH: number,
}

local VIEWS: { View } = { "Chase", "Cockpit", "Hood" }

local CarCamera: CarCamera = table.freeze({
	VIEWS = VIEWS,
	-- Low and close, as the reference clip frames the car.
	CHASE_DISTANCE = 6.0,
	CHASE_HEIGHT = 1.7,
	CHASE_LOOK_HEIGHT = 0.9,
	CHASE_LOOK_AHEAD = 3.0,
	-- From the centre of mass, along the car: just ahead of the windscreen, above the bonnet.
	HOOD_FORWARD = 1.15,
	HOOD_HEIGHT = 0.62,
	-- The cockpit eye, metres ahead of the head's centre. Behind it: the seated R6 driver's head
	-- already touches the headrest, so the eye moves back inside the hidden head to sit 0.38 m
	-- from the wheel (0.24 m at +0.08, the owner found the view too close, 2026-10-27).
	EYE_FORWARD = 0,
	-- And raised, metres, so the eye looks down over the forearms onto the hands on the rim; level
	-- with the forearms, they hid the hands.
	EYE_UP = 0.07,
	-- The player sets the seat, as in a sim: the mouse wheel moves the eye forward and back,
	-- with Shift up and down, a centimetre a notch within these limits (metres, about the
	-- defaults). The owner found +0.08 too close and -0.065 too far (2026-10-27/28).
	EYE_RANGE = table.freeze({ forward = { -0.15, 0.12 }, up = { -0.05, 0.15 }, step = 0.01 }),
	-- Degrees: 70 standing, widening by FOV_GAIN at FOV_SPEED km/h.
	BASE_FOV = 70,
	FOV_GAIN = 12,
	FOV_SPEED = 300,
	-- Degrees the view widens per g of acceleration (none braking), up to maxG; half-lives (s) in
	-- and out, quick both ways so it never reads as a zoom trailing the car; the cockpit takes
	-- a share, or the dashboard visibly zooms. After the racing-game research, 2026-10-28.
	FOV_KICK = table.freeze({ perG = 3, maxG = 1.2, attack = 0.04, release = 0.12, cockpit = 0.5 }),
	-- Right mouse button (or right stick) to look around; the view eases back on release.
	LOOK_SENSITIVITY = math.rad(0.25),
	LOOK_RETURN_HALF_LIFE = 0.25,
	MAX_LOOK_YAW = math.rad(110),
	MAX_LOOK_PITCH = math.rad(40),
})

return CarCamera
