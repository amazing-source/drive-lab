--!strict
--[[
	The car camera's vibrations (Rules/CarShake), from the racing-game research of 2026-10-28:
	small and fast reads as speed, large reads as cheap (heavy shake is the most common complaint
	about Need for Speed Heat). Road vibration after Sleitnick's CameraShaker "Vibration" preset
	and Project CARS' high-speed shake; the upshift kick after the Aventador's 50 ms ISR shifts,
	harsh in Corsa. Seeds for the owner's feel in a playtest; SCALE turns the whole of it down.
]]
local CarShake = require("../Rules/CarShake")

local Config: CarShake.Tuning = table.freeze({
	road = table.freeze({
		base = 0.03,
		gain = 0.12,
		exponent = 1.5,
		topKmh = 350,
		hz = table.freeze({ 12, 22 }),
	}),
	engine = table.freeze({
		degrees = table.freeze({ 0.015, 0.04 }),
		hz = 25,
		fadeKmh = table.freeze({ 40, 100 }),
	}),
	launch = table.freeze({ degrees = 0.6, fromG = 0.4, toG = 1.0, fadeKmh = 80, hz = 9 }),
	shift = table.freeze({
		down = 0.4,
		up = 0.3,
		dip = 0.06,
		rise = 0.15,
		settle = 0.15,
		modes = table.freeze({ Strada = 0.35, Sport = 0.7, Corsa = 1 }),
	}),
	-- The chase camera hangs behind the car rather than riding in it: less engine and kick. The
	-- hood view rides on the body but sees the road: little road vibration.
	views = table.freeze({
		Chase = table.freeze({ road = 1, engine = 0.6, launch = 1, shift = 0.5, lift = 0 }),
		Cockpit = table.freeze({ road = 1.5, engine = 1, launch = 1, shift = 1, lift = 0.004 }),
		Hood = table.freeze({ road = 0.4, engine = 0.5, launch = 0.7, shift = 1, lift = 0 }),
	}),
	scale = 1,
})

return Config
