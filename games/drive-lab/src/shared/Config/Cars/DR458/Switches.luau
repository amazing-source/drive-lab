--!strict
--[[
	The DR458's driver switches (Config/CarSwitches), from docs/research/12_dr458_challenge_evo.md
	§2 and §3.3. FLASH on the wheel flashes the high beam while held; PIT is the pit-lane limiter;
	WIPER and WATER are the wiper and its washer; RAIN LIGHT is on the switch panel; SCROLL steps
	the binnacle display's pages.
]]
local CarSwitches = require("../../CarSwitches")

local Switches: CarSwitches.Switches = table.freeze({
	highBeam = "Flash" :: "Flash",
	pitLimiter = table.freeze({
		-- Documented, §3.3: 60 km/h in the pit lane (Europe, 2014).
		limitKmh = 60,
		-- Likely, §3.3 (one first-hand source): pressed in 2nd below 60 km/h.
		armGear = 2,
		armBelowKmh = 60,
		-- EST: the throttle goes from free to closed over the last 3 km/h.
		band = 3,
	}),
	wiper = table.freeze({
		-- EST: no wiper figure was found; about 50 wipes a minute, and three after a wash.
		wipeSeconds = 1.2,
		afterWash = 3,
	}),
	rainLight = true,
	-- Documented, §2.4: three pages.
	displayPages = 3,
})

return Switches
