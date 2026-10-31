--!strict
--[[
	The shape of a car's gear-lever data for the driver's right hand (its entry's driver.shift): the
	lever's geometry, the hand's grip on the knob, and the keyed way between the wheel and the knob,
	written by tools/anim/shift_paths.py against that car's cabin. The gearbox's Vehicle/ShiftPlan
	says where along the H the lever is (a column and a row); this says where that puts the lever.

	Points are metres in the driver's seat frame (the DriverSeat part: x right, y up, z back). A key
	is { seconds, x, y, z, qw, qx, qy, qz }: a wrist frame, z up the forearm, y out of the back of the
	hand.
]]
export type Point = { x: number, y: number, z: number }
export type Key = { number }
export type ShapeChange = { at: number, shape: string }

-- A lateral angle per gate column, degrees, positive toward the car's right.
export type Column = { column: number, degrees: number }

export type Shifter = {
	pivot: Point,
	-- The knob's centre with the lever in neutral.
	knob: Point,
	-- The car's right and back, the axes the lever turns about (the manifest's gate motion): first
	-- sideways about the forward axis for its column, then fore and aft about the right axis.
	right: Point,
	back: Point,
	knobRadius: number,
	-- Columns in order; a column between two is turned between their angles.
	columns: { Column },
	-- Fore-and-aft angles, degrees: row +1 forward, row -1 back.
	forward: number,
	backward: number,
	-- How far the knob goes down along the lever when pushed (reverse's lockout).
	push: number,
}

export type Shift = {
	shifter: Shifter,
	-- The wrist frame holding the knob, in the knob's frame: origin at its centre, axes the seat's with
	-- the lever in neutral, turned with the lever.
	grip: Key,
	-- From the steering grip (the first key, the wheel straight) to the knob grip with the lever in
	-- neutral (the last key): played forward by the hand's share reaching, back releasing.
	hand: { keys: { Key }, shapes: { ShapeChange } },
	-- Seconds the way takes each direction, and the left foot's from its rest to the clutch: what the
	-- gearbox's shift timing reads.
	reach: number,
	release: number,
	foot: number,
}

return table.freeze({})
