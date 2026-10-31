--!strict
--[[
	The driver's switches that differ from car to car (Controllers/CarSwitches, Controllers/
	Driving, Controllers/CarLights): each car's set is part of its Config/Cars entry, and a control
	whose switch the car lacks does nothing in it and has no row on its controls screen.
]]
local PitLimiter = require("../Rules/PitLimiter")
local Wiper = require("../Rules/Wiper")

export type Switches = {
	-- The high beam key switches the beam on and off, or flashes it while held.
	highBeam: "Toggle" | "Flash",
	pitLimiter: PitLimiter.Tuning?,
	-- The wiper and its washer.
	wiper: Wiper.Tuning?,
	rainLight: boolean,
	-- Pages the display steps through; nil on a display with one.
	displayPages: number?,
}

-- Config/Controls entries that only a car with a given feature has (Config/Cars/Contract.features:
-- pitLimiter, wiper, rainLight, displayPages, escButton, launch, cabinLight). Every other control
-- is on every car.
local NEEDS: { [string]: string } = {
	PIT_LIMITER = "pitLimiter",
	WIPER = "wiper",
	WASHER = "wiper",
	RAIN_LIGHT = "rainLight",
	DISPLAY_PAGE = "displayPages",
	ESC_OFF = "escButton",
	CABIN_LIGHT = "cabinLight",
}

return table.freeze({ NEEDS = table.freeze(NEEDS) })
