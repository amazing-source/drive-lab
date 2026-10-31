--!strict
--[[
	The driver's assists (Rules/DriverAssists): AdvanceTrac, the Boss 302's ESC and traction control
	with ABS (research note §1.9). Everything runs from the start. Held, the console button switches
	AdvanceTrac off, ESC and traction control together, and ABS stays on. The real car also has a
	brief press for traction control alone and a press with the brake held for its sport setting,
	which here is the Sport drive mode.
]]
local DriverAssists = require("../../../Rules/DriverAssists")

local Config: DriverAssists.Tuning = table.freeze({
	on = table.freeze({ abs = true, tc = true, esc = true }),
	escButton = table.freeze({
		-- Documented: held for more than 5 s (with the brake on and no throttle).
		holdSeconds = 5,
		off = table.freeze({ abs = true, tc = false, esc = false }),
	}),
	-- EST, as the other cars'.
	lampFlashHz = 2,
})

return Config
