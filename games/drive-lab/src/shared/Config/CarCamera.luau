--!strict
--[[
	The driving cameras. Distances are metres (the camera converts them with Units, so views keep
	their framing at any world scale); angles are radians, fields of view degrees (vertical, as
	Roblox and Assetto Corsa both measure them).
]]
export type View = "Chase" | "Cockpit" | "Hood"

-- The chase camera's shift with the car's g, in the car's own frame: metres per g back under
-- acceleration and toward the outside of a turn, each capped at `max`, eased with `halfLife`
-- (s), and faded in from rest to `fadeKmh`.
export type Lean = {
	longitudinalPerG: number,
	lateralPerG: number,
	max: number,
	halfLife: number,
	fadeKmh: number,
}

-- An optional critically damped spring on the chase camera's yaw; `hz` is its natural frequency.
export type YawSpring = { enabled: boolean, hz: number }

-- From the rear axle (the midpoint of the rear hubs), in the car's frame: `distance` behind,
-- `height` above, aimed at a point `lookAhead` ahead at hub height, then tilted up by `pitch`.
export type Chase = {
	distance: number,
	height: number,
	lookAhead: number,
	pitch: number,
	lean: Lean,
	yawSpring: YawSpring,
}

-- Degrees the view widens per g of acceleration (none braking), up to `max`; it eases in with
-- the `attack` half-life (s), stays put for `hold` s once the pull falls, then eases out with
-- the `release` half-life.
export type Kick = { perG: number, max: number, attack: number, hold: number, release: number }

-- Each view's field of view at rest, and the share of the kick it takes.
export type ViewFov = { base: number, kickShare: number }

export type CarCamera = {
	VIEWS: { View },
	CHASE: Chase,
	HOOD_FORWARD: number,
	HOOD_HEIGHT: number,
	EYE_FORWARD: number,
	EYE_UP: number,
	EYE_RANGE: { forward: { number }, up: { number }, step: number },
	FOV: { [View]: ViewFov },
	FOV_KICK: Kick,
	LOOK_SENSITIVITY: number,
	LOOK_RETURN_HALF_LIFE: number,
	MAX_LOOK_YAW: number,
	MAX_LOOK_PITCH: number,
}

local VIEWS: { View } = { "Chase", "Cockpit", "Hood" }

-- No speed term: in the owner's reference the view stays put while cruising and widens only as
-- the car pulls (2026-10-28). Chase 60 is Assetto Corsa's default. The cockpit is 4 degrees
-- wider than Assetto Corsa's 56: from the default seat the cluster's screen then ends at 95 % of
-- the frame's height with its bezel in view, where at 56 it touched the frame's bottom edge
-- (edit-mode captures, 2026-10-28). The cockpit and the hood take a quarter of the kick (4.5
-- degrees per g), or the dashboard and the bonnet zoom; the cockpit had an eighth until the
-- owner found the widening too faint (2026-10-29).
local FOV: { [View]: ViewFov } = {
	Chase = table.freeze({ base = 60, kickShare = 1 }),
	Cockpit = table.freeze({ base = 60, kickShare = 0.25 }),
	Hood = table.freeze({ base = 70, kickShare = 0.25 }),
}

local CarCamera: CarCamera = table.freeze({
	VIEWS = VIEWS,
	-- Assetto Corsa's first chase camera (system/cfg/chase_cam.ini ships 3.0 m, 1.4 m, 0.0349
	-- rad; read off rustyAC's port of CameraDrivableManager::updateChase), chosen by the owner
	-- against the SVJ reference frames (2026-10-28). Its yaw is rigid, it never rolls, it rides
	-- the body's pitch, and its only smoothing is this lean. Distance and height are set to the
	-- reference's framing, measured on our model in edit mode: at 3.0 m and 1.4 m the car came
	-- out 0.632 frame heights wide against the reference's 0.58; at 3.3 m and 1.2 m (1.55 m
	-- above the road, the reference's own camera height) it is 0.570 cruising, 0.495 under full
	-- throttle at 170 km/h (reference 0.49).
	CHASE = table.freeze({
		distance = 3.3,
		height = 1.2,
		lookAhead = 4.0,
		pitch = math.rad(2),
		lean = table.freeze({
			longitudinalPerG = 0.2,
			lateralPerG = 0.4,
			max = 0.5,
			halfLife = 0.23,
			fadeKmh = 10,
		}),
		-- Off: Assetto Corsa's yaw is rigid. On, it soaks up yaw chatter and trails a steady
		-- turn by 2 * yaw rate / (2 pi hz): 1.9 degrees at 30 degrees a second and 5 Hz.
		yawSpring = table.freeze({ enabled = false, hz = 5 }),
	}),
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
	FOV = table.freeze(FOV),
	-- First sized so full throttle shrinks the chase car by about the 16 % of the reference
	-- (frames 02 and 03), held through a gear change: frame 03 is mid-upshift and still wide.
	-- Raised by half (12 per g up to 10) when the owner found it not marked enough (2026-10-29).
	FOV_KICK = table.freeze({ perG = 18, max = 15, attack = 0.15, hold = 0.25, release = 0.5 }),
	-- Right mouse button (or right stick) to look around; the view eases back on release.
	LOOK_SENSITIVITY = math.rad(0.25),
	LOOK_RETURN_HALF_LIFE = 0.25,
	MAX_LOOK_YAW = math.rad(110),
	MAX_LOOK_PITCH = math.rad(40),
})

return CarCamera
