--!strict
--[[
	The shape of a car's start-up hand paths (its entry's driver.startupPaths): the driver's hands
	through the start-up, keyed in Blender against that car's cabin and baked by a tools/blender
	script into the car's own module.

	A key is { seconds after the start key, x, y, z, qw, qx, qy, qz }: the wrist frame in the
	driver's seat frame (the DriverSeat part: x right, y up, z back; metres), whose z axis runs up
	the forearm and y out of the back of the hand. The left hand's keys are its own (not mirrored).
]]
export type Shape = "Rest" | "Point" | "Grip"
export type Point = { x: number, y: number, z: number }
export type Key = { number }
export type ShapeChange = { at: number, shape: Shape }
export type Track = {
	keys: { Key },
	shapes: { ShapeChange },
	-- From here the path bends toward the hand's live grip on the wheel, reached at the last key.
	gripFrom: number,
}

export type Paths = {
	RIGHT: Track,
	LEFT: Track,
	-- The right hand's posed meshes' centres in the wrist frame, metres (hand_poses.py); the left
	-- hand mirrors x.
	MESHES: { Rest: Point, Point: Point },
	CUFF: Point,
	-- What the keys were made against, for the specs: the Point hand's index tip in its wrist
	-- frame; START's top face, the console's normal there and the push; the flap's hinge line
	-- (along x) and the point under its free edge the index rides (seat frame, metres).
	FINGERTIP: Point,
	BUTTON: { top: Point, normal: Point, depth: number },
	FLAP: { hinge: Point, edge: Point },
}

return table.freeze({})
