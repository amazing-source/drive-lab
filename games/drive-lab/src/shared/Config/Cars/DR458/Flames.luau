--!strict
--[[
	Which of the DR458's pops throw flame (Config/ExhaustFlames CarFlames), out of the two outlets
	in its binding, each along its own axis. The 458 Challenge has a free-flowing race exhaust with
	no valve, and the manettino sets only traction control and ABS (research 12 §1.9), so every
	position throws flame alike. Road 458s with straight-pipe exhausts show short blue jets on the
	overrun after a downshift blip, on rev drops and at full-throttle upshifts, an orange burst only
	on the bigger bangs, and are seen mostly at night or in tunnels; no footage of a 458 Challenge
	throwing flame was found. The chances and thresholds are estimates for that look.
]]
local ExhaustFlames = require("../../../Rules/ExhaustFlames")

local EVERY_POSITION: ExhaustFlames.KindChances =
	table.freeze({ Lift = 0.35, Downshift = 0.6, Upshift = 0.5 })

local Flames: ExhaustFlames.CarFlames = table.freeze({
	chance = table.freeze({ ["1"] = EVERY_POSITION, ["2"] = EVERY_POSITION, OFF = EVERY_POSITION }),
	minStrength = 0.25,
	fireballFrom = 0.75,
	-- The binding's axis is the tailpipe's own.
	rise = 0,
	dayShare = 0.35,
})

return Flames
