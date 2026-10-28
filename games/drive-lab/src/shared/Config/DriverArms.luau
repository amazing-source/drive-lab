--!strict
--[[
	The driver's arms, drawn in place of the avatar's blocky ones while seated. Arm lengths and
	widths are studs for a character at scale 1 (an R6 torso 2 studs tall) and scale with the
	character. The hands are real-sized against the steering wheel they hold: meshes posed around
	the SVJ's rim by tools/blender/hand_grip.py, exported in the wheel's own frame at the world
	scale, and kept in the place at ReplicatedStorage.DriveLabAssets.Hands (Hand_R, Hand_L, and
	the sleeve cuffs Cuff_R, Cuff_L that cover the wrists along the hands' own axis).
]]
export type Offset = { out: number, down: number, back: number }
export type Point = { x: number, y: number, z: number }

export type DriverArms = {
	UPPER_LENGTH: number,
	LOWER_LENGTH: number,
	CUFF_OVERHANG: number,
	ELBOW_SIZE: number,
	SHOULDER_INSET: number,
	ELBOW_BIAS: Offset,
	HAND_CENTRE: Point,
	CUFF_CENTRE: Point,
	HAND_WRIST: Point,
	HAND_FOREARM: Point,
	HAND_BACK: Point,
	FOLLOW_LIMIT: number,
	SLEEVE_COLOR: Color3,
}

local DriverArms: DriverArms = table.freeze({
	-- Nearly straight at the SVJ's seat (elbows about 135 degrees), as in a sporting driving
	-- position. Real proportions (1.17 and 1.05) bent the elbows to 100 degrees there, so the
	-- forearms rose almost vertically to hands that point at the wheel: the owner saw the wrists'
	-- cut ends (2026-10-27). The R6 arm is 2 studs; these are 1.59 with no hand.
	UPPER_LENGTH = 0.82,
	LOWER_LENGTH = 0.77,
	-- Studs the forearm's sleeve runs past the wrist, so its cuff covers the hand's cut end
	-- (1.5 cm at the world scale). The sleeves' cross-sections are the meshes' own.
	CUFF_OVERHANG = 0.05,
	-- The cloth ball that fills the elbow between the two sleeves, at character scale 1.
	ELBOW_SIZE = 0.52,
	-- The shoulder joint sits this far inside the torso's side, so the sleeve grows out of it.
	SHOULDER_INSET = 0.2,
	-- The elbow bends toward where the forearm would lie straight down the hand's own axis,
	-- nudged down and out by this much (torso axes, against a unit pull).
	ELBOW_BIAS = table.freeze({ out = 0.3, down = 0.3, back = 0 }),
	-- The right hand, from hand_grip.py's hands.json (run with --bar-tilt 10 --wrist-turn -10):
	-- its mesh and cuff centres and its wrist, studs in the steering wheel's frame (x right, y up
	-- the wheel's face, z toward the driver), gripping 25 degrees above 3 o'clock, clear of the
	-- spoke; then two directions in that frame, from the wrist down the forearm and out of the
	-- back of the hand. The left hand mirrors x.
	HAND_CENTRE = table.freeze({ x = 0.7092, y = 0.4279, z = 0.1923 }),
	CUFF_CENTRE = table.freeze({ x = 0.7962, y = 0.2674, z = 0.7406 }),
	HAND_WRIST = table.freeze({ x = 0.8266, y = 0.3252, z = 0.5895 }),
	HAND_FOREARM = table.freeze({ x = -0.0816, y = -0.2297, z = 0.9698 }),
	HAND_BACK = table.freeze({ x = 0.8925, y = 0.4162, z = 0.1736 }),
	-- The hands turn with the wheel this far either way (radians), then the wheel slides
	-- through them, so the arms never cross.
	FOLLOW_LIMIT = math.rad(110),
	SLEEVE_COLOR = Color3.fromRGB(22, 22, 24),
})

return DriverArms
