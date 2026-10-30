--!strict
--[[
	The driver's assists (Rules/DriverAssists), from docs/research/12_dr458_challenge_evo.md §1.9.
	The car's systems are F1-Trac traction control, ABS/EBD and the E-Diff; no source names a
	stability control, so ESC never runs, and the car has no ESC button. The manettino's OFF
	switches traction control off and leaves ABS on (no source says OFF disables ABS).
]]
local DriverAssists = require("../../../Rules/DriverAssists")

local Config: DriverAssists.Tuning = table.freeze({
	on = table.freeze({ abs = true, tc = true, esc = false }),
	modes = table.freeze({
		OFF = table.freeze({ abs = true, tc = false, esc = false }),
	}),
	lampFlashHz = 2,
})

return Config
