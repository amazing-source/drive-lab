--!strict
--[[
	The DR458's lamps (Config/CarLights Lights). The 458 Challenge keeps the road 458's lamp units:
	one bi-xenon projector per side for both beams, a round tail lamp per side whose LED ring is
	the tail and brake lamp, and two rear fog lamps low in the bumper's corners (Ferrari parts
	catalogue, 458 Italia Europe, diagram 0127). FLASH on the wheel flashes the high beam while held
	(Switches). The RAIN LIGHT toggle lights the rear fog lamps, steady: the switch is photographed
	(interior/013) but no source names its lamp or a flash rate for the series, so both are
	inferred (docs/research/12_dr458_challenge_evo.md §3.2). Its green LED, and the LIGHT toggle's,
	are the cockpit's tell-tales. The car has no cabin lamp: its bare roof shows none
	(interior/021, 023), and its binding has no cabinLight, so `cabin` lights nothing.

	The model has pieces for the projectors, the tail rings, the reversing discs and the fog lamps;
	the running lights, indicators, markers and stop bar glow once pieces with their names exist.
	Glow strengths follow the SVJ's until the edit-mode captures.
]]
local CarLights = require("../../CarLights")

type Rgb = CarLights.Rgb

local function rgb(r: number, g: number, b: number): Rgb
	return table.freeze({ r = r, g = g, b = b })
end

local WHITE = rgb(255, 255, 255)
local AMBER = rgb(255, 112, 0)
local RED = rgb(255, 10, 0)
-- The tail rings sit behind red glass: Roblox Glass blends with what is behind it rather than
-- filtering it, so the ring's face takes the lens colour itself (as the SVJ's).
local RED_LENS = rgb(214, 36, 30)
local LED_GREEN = rgb(60, 255, 90)

local Lights: CarLights.Lights = table.freeze({
	required = table.freeze({
		"Light_FrontLeft_Projector",
		"Light_FrontRight_Projector",
		"Light_RearLeft_Tail",
		"Light_RearRight_Tail",
	}),
	glow = table.freeze({
		drl = table.freeze({ tint = rgb(235, 242, 255), day = 9, night = 3.2 }),
		projector = table.freeze({ tint = rgb(240, 244, 255), day = 6, night = 2.4 }),
		frontIndicator = table.freeze({ tint = AMBER, day = 14, night = 6 }),
		frontMarker = table.freeze({ tint = AMBER, day = 3, night = 1.4 }),
		tail = table.freeze({ tint = RED, day = 7, night = 10, filter = RED_LENS }),
		rearIndicator = table.freeze({ tint = AMBER, day = 14, night = 6 }),
		reverse = table.freeze({ tint = WHITE, day = 8, night = 3 }),
		-- The rain light. A rear fog lamp is the brightest red lamp on a car (UN R38: up to 300 cd,
		-- against a stop lamp's 185 under R7), so it outshines the tail ring on the brakes.
		fog = table.freeze({ tint = RED, day = 12, night = 12 }),
		stop = table.freeze({ tint = RED, day = 6, night = 6 }),
		plate = table.freeze({ tint = WHITE, day = 1.5, night = 0.8 }),
		rearMarker = table.freeze({ tint = RED, day = 3, night = 1.4 }),
	}),
	headlight = table.freeze({
		range = 60,
		angle = 55,
		brightness = 5,
		color = rgb(248, 248, 255),
		pitch = math.rad(-3),
	}),
	highBeam = table.freeze({ range = 60, angle = 30, brightness = 8, pitch = 0 }),
	tail = table.freeze({
		range = 3,
		brightness = 0.25,
		brakeRange = 6,
		brakeBrightness = 0.9,
		color = rgb(255, 25, 0),
	}),
	indicator = table.freeze({ range = 3, brightness = 0.5, color = AMBER }),
	reverse = table.freeze({ range = 24, angle = 100, brightness = 2, color = rgb(255, 255, 250) }),
	cabin = table.freeze({ range = 10, angle = 150, brightness = 2, color = rgb(255, 226, 190) }),
	rain = table.freeze({
		pattern = table.freeze({ hz = 0, onShare = 1 }),
		range = 8,
		brightness = 1.2,
		color = rgb(255, 20, 0),
	}),
	-- Small LEDs beside the toggles: lit enough to find at night without lighting the cabin.
	tellTales = table.freeze({
		headlights = table.freeze({ tint = LED_GREEN, day = 3, night = 1.2 }),
		rainLight = table.freeze({ tint = LED_GREEN, day = 3, night = 1.2 }),
	}),
})

return Lights
