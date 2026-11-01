--!strict
--[[
	The Boss 302's start, in its owner's guide's order (research: boss302/research/
	references_data_vfx.md §6): no start button; with the handbrake on, the clutch down and the
	lever in neutral, the key turns to ON, then on to START, and springs back to ON as the engine
	cranks (the computer keeps cranking until it catches). The starter needs the clutch fully down:
	the left foot holds it from the key until driving unlocks, and a driver working the clutch by
	hand holds it himself (Config/CarEntry.CLUTCH_INTERLOCK). The TracKey drive mode starts it with
	the TracKey. Every value is an estimate until StartupPending is empty.
]]
local CarEntry = require("../../CarEntry")

-- The key cylinder's positions from OFF (Key_Ignition in the 3D artist's cockpit parts, draft):
-- EST, a typical Ford key's.
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
	-- Placeholders for the sound pack's measured start (the audio agent writes them): the 5.0's
	-- recording catches about 0.67 s after the press and settles around 1,140 rpm.
	catchAfter = 0.67,
	rpm = {
		times = { 0, 0.6, 0.8, 4.5, 5.3 },
		values = { 200, 200, 1140, 1140, 1140 },
	},
	-- The order holds the car on the handbrake: the right foot stays off the brake.
	brake = 0,
	clutch = 1,
	interlock = "Clutch" :: "Clutch",
	keys = { TracKey = "TracKey" },
}

return Startup
