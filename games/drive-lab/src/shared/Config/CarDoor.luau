--!strict
--[[
	The driver's door's sound: one uploaded pack (tools/audio/pack_door.py, manifest.json beside
	it in drive-lab-assets/door/audio) holding the latch as the door starts to open and the shut
	as it closes, the SVJ's own from the Assetto Corsa mod's bank (26_door_open.wav,
	36_door_close.wav). Each region starts at its sound's onset.
]]
export type Region = { from: number, to: number }

-- The hand on the door's pull strap (Rules/DoorStrap decides when it holds it; the strap
-- itself is in the car's model binding).
export type StrapConfig = {
	-- The arm whose palm holds it, and the palm in that arm's space as a share of its size:
	-- tools/anim r6_fk.HAND (0, -0.85, -0.05) on a 1 x 2 x 1 arm, the point the clips aim.
	ARM: string,
	PALM: Vector3,
	-- Studs the strap's length or end must move before it is written again.
	EPSILON: number,
}

export type CarDoorConfig = {
	SOUND_ID: string,
	LATCH: Region,
	SHUT: Region,
	-- Seconds ahead of the door's own timeline the sounds are started: the shut's thump peaks
	-- this long into its region (measured on the file), so it lands as the door closes, and the
	-- latch clicks just before the door moves.
	LEAD: number,
	VOLUME: number,
	-- Studs: full volume within the minimum, silent past the maximum.
	ROLL_OFF: Region,
	STRAP: StrapConfig,
}

local CarDoor: CarDoorConfig = table.freeze({
	SOUND_ID = "rbxassetid://139259949513411",
	LATCH = table.freeze({ from = 0.2689, to = 0.835 }),
	SHUT = table.freeze({ from = 1.1262, to = 1.6378 }),
	LEAD = 0.1,
	VOLUME = 0.8,
	ROLL_OFF = table.freeze({ from = 6, to = 90 }),
	STRAP = table.freeze({
		ARM = "Left Arm",
		PALM = Vector3.new(0, -0.425, -0.05),
		EPSILON = 0.002,
	}),
})

return CarDoor
