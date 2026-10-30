--!strict
--[[
	The DR458's start, timed on the start-up recording its sound plays (Audio's startup.sound),
	which starts at the press of ENGINE START. The cabin controls worked before it (the master key,
	the guard and IGNITION, docs/research/12_dr458_challenge_evo.md §2.5) need the model binding's
	controls, so they come with it; until then the hands reach for ENGINE START only.
]]
local CarEntry = require("../../CarEntry")

local Startup: CarEntry.Startup = table.freeze({
	moves = table.freeze({}),
	-- EST, the SVJ's: the press, the hands back on the wheel and driving unlocked. The moves before
	-- the press will push them later.
	pressAt = 1.5,
	wheelAt = 2.9,
	drivableAt = 3.1,
	-- The catch and the revs follow the recording's firing order, and end at the car's idle; the
	-- starter's revs are EST, as its sound carries no engine order.
	catchAfter = 0.71,
	rpm = table.freeze({
		times = { 0, 0.70, 0.95, 1.15, 1.45, 1.65, 2.05, 2.45, 2.98 },
		values = { 250, 250, 2170, 2480, 2360, 2200, 1450, 1160, 1000 },
	}),
	-- EST, the SVJ's.
	brake = 0.6,
})

return Startup
