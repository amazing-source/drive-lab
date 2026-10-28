--!strict
--[[
	The driver's door's sound: one uploaded pack (tools/audio/pack_door.py, manifest.json beside
	it in drive-lab-assets/door/audio) holding the latch as the door starts to open and the shut
	as it closes, the SVJ's own from the Assetto Corsa mod's bank (26_door_open.wav,
	36_door_close.wav). Each region starts at its sound's onset.
]]
export type Region = { from: number, to: number }

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
}

local CarDoor: CarDoorConfig = table.freeze({
	SOUND_ID = "rbxassetid://139259949513411",
	LATCH = table.freeze({ from = 0.2689, to = 0.835 }),
	SHUT = table.freeze({ from = 1.1262, to = 1.6378 }),
	LEAD = 0.1,
	VOLUME = 0.8,
	ROLL_OFF = table.freeze({ from = 6, to = 90 }),
})

return CarDoor
