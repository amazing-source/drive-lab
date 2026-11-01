--!strict
--[[
	The Boss 302's lamps (Config/CarLights Lights), from the 2012 Mustang Owner's Guide's bulb chart
	and lamp sections: one halogen bulb per side does both beams (HID came to the Boss for 2013); the
	front park and turn lamp sits in the headlamp unit behind an amber lens; the tail, brake and turn
	lamps are LEDs in three compartments per side, which light one after another on the turn signal
	"from the inner most" and all together on the brakes and the hazards (Ford's 2014 Mustang
	workshop manual, 417-01: "sequentially from the inboard lamp to the outboard lamp", "the rear
	lamps do not flash sequentially for the hazard function"; each compartment is a combined stop
	and turn lamp, so it shows no brake while it flashes, FMVSS 108 table I-a); the high stop lamp is an
	LED strip; the Boss's fog lamp openings are blocked (Ford Racing); the reversing lamps are in
	the tail lamp assemblies.

	The model's lamp pieces are not the house split, so they are named here (`pieces`): the three
	compartments are one piece per side for now, flashing together on the turn signal too; the
	sequence needs them as three pieces. The model has no reversing lamp piece yet, so nothing
	shows reverse.
]]
local CarLights = require("../../CarLights")

type Rgb = CarLights.Rgb

local function rgb(r: number, g: number, b: number): Rgb
	return table.freeze({ r = r, g = g, b = b })
end

local WHITE = rgb(255, 255, 255)
local AMBER = rgb(255, 112, 0)
local RED = rgb(255, 10, 0)
-- A halogen bulb's warm white (about 3200 K), against the DR458's bluish xenon.
local HALOGEN = rgb(255, 228, 190)

-- The three compartments play tail, brake and turn; the park and turn lamp plays park and turn.
local PIECES: CarLights.Pieces = {
	drlLeft = {},
	drlRight = {},
	projector = {
		{ name = "Light_FrontLeft_Headlamp", glow = "projector" },
		{ name = "Light_FrontRight_Headlamp", glow = "projector" },
	},
	left = {
		{ name = "Light_FrontLeft_ParkTurn", glow = "frontIndicator" },
		{ name = "Light_RearLeft_Brake", glow = "rearIndicator" },
	},
	right = {
		{ name = "Light_FrontRight_ParkTurn", glow = "frontIndicator" },
		{ name = "Light_RearRight_Brake", glow = "rearIndicator" },
	},
	position = {
		{ name = "Light_FrontLeft_ParkTurn", glow = "frontMarker" },
		{ name = "Light_FrontRight_ParkTurn", glow = "frontMarker" },
	},
	tail = {
		{ name = "Light_RearLeft_Tail", glow = "tail" },
		{ name = "Light_RearRight_Tail", glow = "tail" },
		{ name = "Light_RearLeft_Brake", glow = "tail" },
		{ name = "Light_RearRight_Brake", glow = "tail" },
	},
	stop = {
		{ name = "Light_RearLeft_Brake", glow = "stop" },
		{ name = "Light_RearRight_Brake", glow = "stop" },
		{ name = "Light_RearLeft_HighStop", glow = "stop" },
		{ name = "Light_RearRight_HighStop", glow = "stop" },
	},
	reverse = {},
	-- No source gives the delay between compartments; UN R6 5.6(d) bounds the sweep to finish within
	-- 200 ms of the flash's start. EST: 1/15 s, so the third lights at 133 ms.
	sweepStep = 1 / 15,
}

local Lights: CarLights.Lights = table.freeze({
	required = table.freeze({
		"Light_FrontLeft_Headlamp",
		"Light_FrontRight_Headlamp",
		"Light_RearLeft_Tail",
		"Light_RearRight_Tail",
	}),
	glow = table.freeze({
		drl = table.freeze({ tint = HALOGEN, day = 9, night = 3.2 }),
		projector = table.freeze({ tint = HALOGEN, day = 6, night = 2.4 }),
		frontIndicator = table.freeze({ tint = AMBER, day = 14, night = 6 }),
		frontMarker = table.freeze({ tint = AMBER, day = 3, night = 1.4 }),
		tail = table.freeze({ tint = RED, day = 20, night = 10 }),
		rearIndicator = table.freeze({ tint = RED, day = 20, night = 10 }),
		reverse = table.freeze({ tint = WHITE, day = 8, night = 3 }),
		fog = table.freeze({ tint = RED, day = 20, night = 12 }),
		stop = table.freeze({ tint = RED, day = 6, night = 6 }),
		plate = table.freeze({ tint = WHITE, day = 1.5, night = 0.8 }),
		rearMarker = table.freeze({ tint = RED, day = 3, night = 1.4 }),
	}),
	-- A halogen beam: as the DR458's in reach, warmer and dimmer.
	headlight = table.freeze({
		range = 60,
		angle = 55,
		brightness = 4,
		color = HALOGEN,
		pitch = math.rad(-3),
	}),
	highBeam = table.freeze({ range = 60, angle = 30, brightness = 7, pitch = 0 }),
	tail = table.freeze({
		range = 3,
		brightness = 0.25,
		brakeRange = 6,
		brakeBrightness = 0.9,
		color = rgb(255, 25, 0),
	}),
	indicator = table.freeze({ range = 3, brightness = 0.5, color = AMBER, rearColor = rgb(255, 25, 0) }),
	reverse = table.freeze({ range = 24, angle = 100, brightness = 2, color = rgb(255, 255, 250) }),
	cabin = table.freeze({ range = 10, angle = 150, brightness = 2, color = rgb(255, 226, 190) }),
	pieces = table.freeze(PIECES),
})

return Lights
