--!strict
--[[
	The SVJ's driver switches (Config/CarSwitches): its J switches the high beam on and off; it has
	no pit limiter, wiper switch, rain light or display pages in Drive Lab.
]]
local CarSwitches = require("../../CarSwitches")

local Switches: CarSwitches.Switches = table.freeze({
	highBeam = "Toggle" :: "Toggle",
	rainLight = false,
})

return Switches
