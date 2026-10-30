--!strict
--[[
	The driver's assists (Rules/DriverAssists), researched for issue #21 on 2026-10-28; the sources
	are listed in its pull request.
	- The Aventador's driver can switch ESC off (its launch-control start asks for it), and on the
	  SVJ that is the step past the drive modes. It takes traction control with it, the engine
	  torque half of ESC. ABS stays: no source has the car's ABS switchable, and switching a Bosch
	  ESC off leaves ABS working.
	- ESC comes back on at every new start, its ESC OFF light stays lit while it is off, and its
	  light may flash while it acts (FMVSS 126); the SVJ's does (Car and Driver, 2018).
	- Held about 3 s to switch off, as most cars' ESC OFF buttons are: the Aventador's own control
	  and hold time were not found in a readable source. The flash rate is an estimate.
]]
local DriverAssists = require("../../../Rules/DriverAssists")

local Config: DriverAssists.Tuning = table.freeze({
	offHoldSeconds = 3,
	on = table.freeze({ abs = true, tc = true, esc = true }),
	off = table.freeze({ abs = true, tc = false, esc = false }),
	lampFlashHz = 2,
})

return Config
