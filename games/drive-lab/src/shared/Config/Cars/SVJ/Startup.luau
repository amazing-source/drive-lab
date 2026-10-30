--!strict
--[[
	The SVJ's keyless start: the right hand lifts the red flap on the console, presses START under
	it and lets the flap down, with a foot on the brake. The flap is the model binding's
	StartFlap control.
]]
local CarEntry = require("../../CarEntry")

local Startup: CarEntry.Startup = table.freeze({
	moves = table.freeze({
		table.freeze({ control = "StartFlap", angle = math.rad(70), move = 0.25, at = 1.0, back = 2.1 }),
	}),
	pressAt = 1.5,
	wheelAt = 2.9,
	drivableAt = 3.1,
	-- Measured on the start-up recording the engine sound plays (Assetto Corsa mod,
	-- 13_Avent_Startup_Race_Adaptive_Idle.wav): about 0.7 s of starter, the catch at 0.75 s,
	-- the flare at its loudest and highest 1.25 to 1.5 s, loud until 3.2 s, a fast idle
	-- about 1.17 times the idle's pitch settling to idle by 10 s. Revs from the 950 rpm idle
	-- and that pitch ratio (the flare's line is 1.9 times the idle's).
	catchAfter = 0.75,
	rpm = table.freeze({
		times = { 0, 0.7, 0.8, 1.0, 1.3, 1.6, 2.2, 3.2, 3.6, 6.0, 8.0, 10.0 },
		values = { 250, 250, 700, 1400, 1800, 1750, 1500, 1250, 1120, 1080, 1020, 950 },
	}),
	brake = 0.6,
})

return Startup
