--!strict
--[[
	The shape of a car's hand gestures (its entry's driver.gestures): what the driver's hand does
	while the player works a wheel button or a panel switch, keyed by tools/anim/gesture_paths.py
	against that car's wheel and cabin and written into the car's own module.

	A key is { seconds into the gesture, x, y, z, qw, qx, qy, qz }: the wrist frame (z up the
	forearm, y out of the back of the hand; metres) in the steering wheel's frame (x right, y up
	the wheel's face, z toward the driver) for a "Wheel" gesture, so the hand follows the wheel at
	any angle, or in the DriverSeat's frame for a "Seat" one. A track runs from the grip (its first
	key) to the pose held while the input is held (its last key), and plays backward to let go.
]]
export type Point = { x: number, y: number, z: number }
export type Key = { number }
-- "Grip", "Rest" or "Point" (the shapes the start-up already draws), or a name in MESHES.
export type ShapeChange = { at: number, shape: string }

-- A control the hand turns on the way (the knob's weld, a toggle's weld): from the angle of the
-- state before the press to the next state's, between `start` and `finish` seconds along the keys.
export type Turn = { control: string, start: number, finish: number }

export type Track = {
	keys: { Key },
	shapes: { ShapeChange },
	turn: Turn?,
	-- A "Seat" track's keys start and end on the grip with the wheel straight; over this many
	-- seconds from either end the path is moved onto the live grip, wherever the wheel is.
	gripBlend: number?,
	-- For the specs: the hand's contact point in its wrist frame (the thumb's pad, the index's
	-- end) and where it meets the control at the held pose, in the gesture's frame (metres).
	tip: Point,
	target: Point,
}

-- What the control's state is before a press, which picks the track: none (a button), the car's
-- drive mode (a knob that steps through Physics.modeOrder) or a toggle's Off / On.
export type Latch = "Mode" | "Toggle"

export type Gesture = {
	-- The Config/Controls entry whose input plays it.
	control: string,
	-- +1 the right hand, -1 the left.
	side: number,
	frame: "Wheel" | "Seat",
	latch: Latch?,
	-- By the state before the press: "Press" for a button, a mode's name, or "Off" / "On".
	tracks: { [string]: Track },
}

-- A posed mesh: its frame in its wrist frame ({ x, y, z, qw, qx, qy, qz }, metres), and the cuff
-- drawn with it: the grip's, for a grip with only its thumb or a finger moved, or the posed
-- hands' wrist cuff.
export type Mesh = { frame: Key, cuff: "Grip" | "Wrist" }

export type Gestures = {
	list: { Gesture },
	-- By the name each mesh is kept under in ReplicatedStorage.DriveLabAssets.Hands.
	MESHES: { [string]: Mesh },
	-- Seconds a tap holds the pose once reached, so a short press still shows.
	HOLD_MIN: number,
}

return table.freeze({})
