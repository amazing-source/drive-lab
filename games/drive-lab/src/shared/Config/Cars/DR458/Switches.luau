--!strict
--[[
	The DR458's driver switches (Config/CarSwitches), from docs/research/12_dr458_challenge_evo.md
	§2 and §3.3. FLASH on the wheel flashes the high beam while held; PIT is the pit-lane limiter;
	WIPER and WATER are the wiper and its washer; RAIN LIGHT is on the switch panel; SCROLL steps
	the binnacle display's pages; RADIO talks to the pit crew while held.
]]
local CarSwitches = require("../../CarSwitches")

local Switches: CarSwitches.Switches = table.freeze({
	highBeam = "Flash" :: "Flash",
	pitLimiter = table.freeze({
		-- Documented, §3.3: 60 km/h in the pit lane (Europe, 2014).
		limitKmh = 60,
		-- Drive Lab's rule, as a racing game's limiter: it arms in any forward gear at any speed,
		-- and the car slows to the limit by itself. The real car's, likely (§3.3, one source):
		-- armFromGear = 2, armToGear = 2, armBelowKmh = 60, which the automatic gearbox never
		-- meets (it is in 2nd only above 60 km/h).
		armFromGear = 1,
		-- EST: the throttle goes from free to closed over the last 3 km/h.
		band = 3,
		-- Unknown for the 458; the 488 Challenge flashes its hazards while the limiter is on.
		hazards = false,
	}),
	wiper = table.freeze({
		-- Off, medium and fast, as the 458 GTE's wiper switch (0, 1, 2); the Challenge's own steps
		-- are not documented. EST: 45 and 65 wipes a minute, inside FMVSS 104 S4.1.1 (one speed at
		-- 45 or more, the fastest at least 15 above a slower one).
		speeds = table.freeze({ 60 / 45, 60 / 65 }),
		-- EST: three wipes after a wash.
		afterWash = 3,
	}),
	rainLight = true,
	-- Documented, §2.4: three pages.
	displayPages = 3,
	-- Likely, §2.1: RADIO on the wheel is push-to-talk to the pit crew.
	radio = true,
})

return Switches
