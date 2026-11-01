--!strict
--[[
	The shape of a car's start-up hand paths (its entry's driver.startupPaths): the driver's hands
	through the start-up, keyed in Blender against that car's cabin and baked by a tools/blender
	script into the car's own module.

	A key is { seconds after the start key, x, y, z, qw, qx, qy, qz }: the wrist frame in the
	driver's seat frame (the DriverSeat part: x right, y up, z back; metres), whose z axis runs up
	the forearm and y out of the back of the hand. The left hand's keys are its own (not mirrored).
]]
export type Shape = "Rest" | "Point" | "Pinch" | "KeyPinch" | "Grip"
export type Point = { x: number, y: number, z: number }
export type Key = { number }
export type ShapeChange = { at: number, shape: Shape }
export type Track = {
	keys: { Key },
	shapes: { ShapeChange },
	-- From here the path bends toward the hand's live grip on the wheel, reached at the last key.
	gripFrom: number,
}

-- A control the start-up turns (its move in the car's Startup) that a hand works: the hand's
-- shape, its contact point in its wrist frame (the index's end, or the pinch between thumb and
-- index) and the point of the control it touches with the control at rest (seat frame, metres).
export type Touch = { control: string, shape: Shape, tip: Point, point: Point }

-- The torso leaning forward through the start-up, where the drawn arm cannot reach a control from
-- the seated pose: its keys { seconds after the start key, degrees forward }, smoothstep between
-- them and 0 outside their span (Rules/StartupLean), turning about the seat's x axis through
-- `pivot` (the hips, seat frame, metres), positive tipping the top toward the nose.
export type Lean = { pivot: Point, keys: { { number } } }

export type Paths = {
	RIGHT: Track,
	LEFT: Track,
	-- The right hand's posed meshes' centres in the wrist frame, metres (hand_poses.py); the left
	-- hand mirrors x.
	MESHES: { Rest: Point, Point: Point, Pinch: Point?, KeyPinch: Point? },
	CUFF: Point,
	-- What the keys were made against, for the specs: the Point hand's index tip in its wrist
	-- frame; START's top face, the console's normal there and the push (seat frame, metres), in a
	-- car with a START button.
	FINGERTIP: Point,
	BUTTON: { top: Point, normal: Point, depth: number }?,
	-- The SVJ's START flap: its hinge line (along x) and the point under its free edge the index
	-- rides.
	FLAP: { hinge: Point, edge: Point }?,
	-- Every other car: the controls its start-up turns, each with the hand that works it.
	TOUCHES: { Touch }?,
	-- A car whose start-up leans the torso forward. Optional.
	LEAN: Lean?,
}

return table.freeze({})
