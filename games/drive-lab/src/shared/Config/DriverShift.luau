--!strict
--[[
	The shape of a car's shift data for the driver's right hand (its entry's driver.shift): the hand's
	grip on the knob and the keyed way between the wheel and the knob, written by
	tools/anim/shift_paths.py against that car's cabin. The lever itself is the car's model binding's
	(Binding.Shifter), which Rules/ShiftHand turns into the seat's frame; the gearbox's
	Vehicle/ShiftPlan says where along the H it is.

	Points are metres in the driver's seat frame (the DriverSeat part: x right, y up, z back). A key
	is { seconds, x, y, z, qw, qx, qy, qz }: a wrist frame, z up the forearm, y out of the back of the
	hand.
]]
export type Key = { number }
export type ShapeChange = { at: number, shape: string }
export type Point = { x: number, y: number, z: number }

export type Shift = {
	-- The knob ball's radius (metres), for the fingers' wrap.
	knobRadius: number,
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
	-- The same durations for the game-quick pace (the keyed way is played by share, so only these
	-- change).
	quick: { reach: number, release: number, foot: number }?,
	-- The Knob hand mesh's centre in the wrist frame, metres (the right hand; the left mirrors x), as
	-- Config/DriverStartup's MESHES give the start-up hands.
	mesh: Point?,
}

return table.freeze({})
