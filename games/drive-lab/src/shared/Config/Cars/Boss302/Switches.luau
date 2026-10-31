--!strict
--[[
	The Boss 302's driver switches (Config/CarSwitches), from the research note §1.9 and the
	controls table. The left stalk pushed away switches the high beam on and off. TracKey's Pit Lane
	Speed Control (2012) is the pit limiter, armable only in the TracKey drive mode. The stalk's
	wiper and washer come with the car's model; it has no rain light, display pages or radio button.
]]
local CarSwitches = require("../../CarSwitches")

local Switches: CarSwitches.Switches = table.freeze({
	highBeam = "Toggle" :: "Toggle",
	pitLimiter = table.freeze({
		-- Documented: 44 mph by default (settable up to 85 mph on the car, not in Drive Lab).
		limitKmh = 44 * 1.609344,
		-- Drive Lab's rule, as the DR458's: it arms in any forward gear at any speed.
		armFromGear = 1,
		-- EST, as the DR458's: the throttle goes from free to closed over the last 3 km/h.
		band = 3,
		-- Documented: the cruise lamp flashes twice a second, not the hazards.
		hazards = false,
		modes = table.freeze({ "TracKey" }),
	}),
	rainLight = false,
})

return Switches
