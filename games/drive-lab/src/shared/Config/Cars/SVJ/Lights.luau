--!strict
--[[
	The SVJ's lamps (Config/CarLights Lights): each lamp's glow, and the Roblox lights they throw.
]]
local CarLights = require("../../CarLights")

type Rgb = CarLights.Rgb

local function rgb(r: number, g: number, b: number): Rgb
	return table.freeze({ r = r, g = g, b = b })
end

local WHITE = rgb(255, 255, 255)
local AMBER = rgb(255, 112, 0)
local RED = rgb(255, 10, 0)
local RED_LENS = rgb(214, 36, 30)
local AMBER_LENS = rgb(236, 138, 40)

local Lights: CarLights.Lights = table.freeze({
	required = table.freeze({
		"Light_FrontLeft_Projector",
		"Light_FrontRight_Projector",
		"Light_FrontLeft_Modules",
		"Light_FrontRight_Modules",
		"Light_RearLeft_Tail",
		"Light_RearRight_Tail",
		"Light_RearLeft_Indicator",
		"Light_RearRight_Indicator",
		"Light_RearLeft_Reverse",
		"Light_RearRight_Reverse",
	}),
	glow = table.freeze({
		drl = table.freeze({ tint = rgb(235, 242, 255), day = 9, night = 3.2 }),
		projector = table.freeze({ tint = rgb(240, 244, 255), day = 6, night = 2.4 }),
		frontIndicator = table.freeze({ tint = AMBER, day = 14, night = 6 }),
		frontMarker = table.freeze({ tint = AMBER, day = 3, night = 1.4 }),
		tail = table.freeze({ tint = RED, day = 7, night = 10, filter = RED_LENS }),
		rearIndicator = table.freeze({ tint = AMBER, day = 14, night = 6, filter = AMBER_LENS }),
		reverse = table.freeze({ tint = WHITE, day = 8, night = 3 }),
		fog = table.freeze({ tint = RED, day = 10, night = 4 }),
		stop = table.freeze({ tint = RED, day = 6, night = 6, filter = RED_LENS }),
		plate = table.freeze({ tint = WHITE, day = 1.5, night = 0.8 }),
		rearMarker = table.freeze({ tint = RED, day = 3, night = 1.4, filter = RED_LENS }),
	}),
	-- Roblox lights below are a night effect: each is scaled by 1 - daylight, as a real lamp's light
	-- is lost in the sun's. Ranges in studs, as Roblox's lights take them (60 is their maximum).
	-- One beam per projector, from its lens: range at Roblox's 60-stud maximum, dipped a little
	-- (radians); colour after the Assetto Corsa mod's own (1500, 1500, 1540).
	headlight = table.freeze({
		range = 60,
		angle = 55,
		brightness = 5,
		color = rgb(248, 248, 255),
		pitch = math.rad(-3),
	}),
	-- On high beam a second, narrower beam from each projector reaches level ahead, on top of the
	-- dipped one (the regulations' high beam peaks at 40,000 cd and more against a dipped beam's
	-- 10,000 at its key point: UN R149, FMVSS 108).
	highBeam = table.freeze({ range = 60, angle = 30, brightness = 8, pitch = 0 }),
	tail = table.freeze({
		range = 3,
		brightness = 0.25,
		brakeRange = 6,
		brakeBrightness = 0.9,
		color = rgb(255, 25, 0),
	}),
	indicator = table.freeze({ range = 3, brightness = 0.5, color = AMBER }),
	-- Between the two reversing lamps, facing back.
	reverse = table.freeze({ range = 24, angle = 100, brightness = 2, color = rgb(255, 255, 250) }),
	-- The roof console's lamp (the binding's cabinLight), facing down over both seats. Its colour
	-- is not documented; a warm white like most reading lamps.
	cabin = table.freeze({ range = 10, angle = 150, brightness = 2, color = rgb(255, 226, 190) }),
})

return Lights
