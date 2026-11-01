--!strict
--[[
	The Boss 302's start, in its owner's guide's order (research: boss302/research/
	references_data_vfx.md §6): no start button; with the handbrake on, the clutch down and the
	lever in neutral, the key turns to ON, then on to START, and springs back to ON as the engine
	cranks (the computer keeps cranking until it catches). The starter needs the clutch fully down:
	the left foot holds it from the key until driving unlocks, and a driver working the clutch by
	hand holds it himself (Config/CarEntry.CLUTCH_INTERLOCK). The TracKey drive mode starts it with
	the TracKey.
]]
local CarEntry = require("../../CarEntry")

-- The key cylinder's positions from OFF, clockwise looking into the cylinder. EST, a typical Ford
-- key's: the bezel's marks are unreadable in all three photos of the cylinder, and the key head
-- covers its face; the modelled key's place agrees with three solved views to about 10 mm.
local KEY_ON = math.rad(60)
local KEY_START = math.rad(90)

local Startup: CarEntry.Startup = {
	moves = {
		-- The right hand comes from the thigh to the key and turns it to ON, then holds it about 0.6 s
		-- for the gauges and the fuel pump (StartupPaths is keyed to these times; EST against footage).
		{ control = "Key_Ignition", angle = KEY_ON, move = 0.25, at = 1.0 },
		-- At the press: on to START. The guide has the driver let go as it cranks (the computer keeps
		-- cranking until it catches), so the spring brings it back to ON at once.
		{ control = "Key_Ignition", angle = KEY_START - KEY_ON, move = 0.15, at = 1.85, back = 2.15 },
	},
	-- START, then the hand back on the wheel and driving unlocked (StartupPaths is keyed to these).
	pressAt = 1.85,
	wheelAt = 3.3,
	drivableAt = 3.5,
	-- Measured on the sound pack's start-up (its 4th-order line, from the press): the starter until
	-- it catches, a flare, and a settle above both idles, which the engine leaves for the drive
	-- mode's idle after the hand-over.
	catchAfter = 0.54,
	rpm = {
		times = { 0, 0.52, 0.7, 0.9, 1.3, 1.7, 2.1, 2.7, 4.1 },
		values = { 200, 200, 1460, 1520, 1460, 1345, 1280, 1255, 1230 },
	},
	-- The order holds the car on the handbrake: the right foot stays off the brake.
	brake = 0,
	clutch = 1,
	interlock = "Clutch" :: "Clutch",
	keys = { TracKey = "TracKey" },
}

return Startup
