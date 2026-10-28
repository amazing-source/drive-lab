--!strict
--[[
	A car's lamps as the Aventador S and SVJ have them (issue #41; the SVJ shares the S's units as
	far as photographs show). Each lamp is its own piece of the model's light mesh
	(tools/blender/split_lights.py), named Light_<Corner>_<Lamp>, and glows through its
	SurfaceAppearance; Roblox lights added here throw the light.

	Front, each side (LP700-4 press release, 2011; Commons "Lamborghini Aventador S coupé French
	Blue (5)"): the Y light guide round the headlamp is the daytime running light; one round
	bi-xenon projector does both beams (CarExpert, 2018 S and 2021 SVJ specifications); seven LEDs
	in hexagonal cells at the lamp's inboard tip are the indicator; a slim amber marker sits on the
	bumper's flank (lit amber at night on a US SVJ, youtube.com/watch?v=BXXAggNT6Hk 00:00).
	Rear, each side (press release; Commons "2018 Lamborghini Aventador S, rear right, in
	Greenwich CT"): three red Y guides are the tail lamps and brighten as the brakes, with the
	high stop strip across the engine cover (youtube.com/watch?v=85isFcdMhg8 02:05-02:15); amber
	cells above them are the indicators; a clear chevron inboard is the reversing light, with the
	red fog lamp inside it; plate lamps and a red side marker.

	Not found in any source, so chosen and open to the owner: what the Y does while its side's
	indicator flashes (the rules allow off or dimmed for the whole cycle, UN R48 6.19.7.5); the
	Y's level with the headlights on (seen lit at night, brightness not measurable).
]]
local CarLights = require("../Rules/CarLights")

-- Colours as 0-255 channels, so the specs can read this file outside Roblox.
export type Rgb = { r: number, g: number, b: number }

-- A lamp's glow: its SurfaceAppearance's EmissiveTint, and EmissiveStrength at full output by
-- day and at night (blended by Rules/CarLights.daylight).
export type Glow = { tint: Rgb, day: number, night: number }

export type CarLightsConfig = {
	TUNING: CarLights.Tuning,
	-- Lighting.Brightness of the night and the dimmest day presets (Config/Atmosphere).
	NIGHT_BRIGHTNESS: number,
	DAY_BRIGHTNESS: number,
	-- The Ys as tail lamps, a share of their brake output.
	TAIL_SHARE: number,
	PAD_HOLD_SECONDS: number,
	GLOW: {
		drl: Glow,
		projector: Glow,
		frontIndicator: Glow,
		frontMarker: Glow,
		tail: Glow,
		rearIndicator: Glow,
		reverse: Glow,
		fog: Glow,
		stop: Glow,
		plate: Glow,
		rearMarker: Glow,
	},
	HEADLIGHT: { range: number, angle: number, brightness: number, color: Rgb, pitch: number },
	TAIL: { range: number, brightness: number, brakeRange: number, brakeBrightness: number, color: Rgb },
	INDICATOR: { range: number, brightness: number, color: Rgb },
	REVERSE: { range: number, angle: number, brightness: number, color: Rgb },
	CABIN: { range: number, angle: number, brightness: number, color: Rgb },
}

local function rgb(r: number, g: number, b: number): Rgb
	return table.freeze({ r = r, g = g, b = b })
end

local WHITE = rgb(255, 255, 255)
local AMBER = rgb(255, 130, 10)
local RED = rgb(255, 22, 8)

local Config: CarLightsConfig = table.freeze({
	-- Headlights come on by themselves at night or in rain this heavy; a brake pedal past this
	-- lights the brakes. Indicators: 90 flashes a minute, the middle of UN R48's 90 +- 30 and of
	-- FMVSS 108's 60 to 120, half of each period lit (FMVSS 108: 30 to 75 %); LEDs switch in
	-- under 0.1 s, so on and off are steps. The running light dims to a position lamp's level
	-- with the headlights (R148: position 4 to 140 cd against a DRL's 400 to 1200) and goes out
	-- on the side whose indicator runs.
	TUNING = table.freeze({
		rainOn = 0.3,
		brakeOn = 0.05,
		blinkHz = 1.5,
		blinkOnShare = 0.5,
		drlWithHeadlights = 0.15,
		drlWhileIndicating = 0,
	}),
	NIGHT_BRIGHTNESS = 0.6,
	DAY_BRIGHTNESS = 1.6,
	-- A stop lamp is at least five times the tail lamp (UN R148 4.8.11; FMVSS 108 table IX).
	TAIL_SHARE = 0.2,
	PAD_HOLD_SECONDS = 0.5,
	GLOW = table.freeze({
		drl = table.freeze({ tint = rgb(235, 242, 255), day = 9, night = 3.2 }),
		projector = table.freeze({ tint = rgb(240, 244, 255), day = 6, night = 2.4 }),
		frontIndicator = table.freeze({ tint = AMBER, day = 14, night = 5 }),
		frontMarker = table.freeze({ tint = AMBER, day = 3, night = 1.4 }),
		tail = table.freeze({ tint = RED, day = 12, night = 5 }),
		rearIndicator = table.freeze({ tint = AMBER, day = 12, night = 4.5 }),
		reverse = table.freeze({ tint = WHITE, day = 8, night = 3 }),
		fog = table.freeze({ tint = RED, day = 10, night = 4 }),
		stop = table.freeze({ tint = RED, day = 10, night = 4 }),
		plate = table.freeze({ tint = WHITE, day = 1.5, night = 0.8 }),
		rearMarker = table.freeze({ tint = RED, day = 3, night = 1.4 }),
	}),
	-- One beam per projector, from its lens: range at Roblox's 60-stud maximum, dipped a little
	-- (radians); colour after the Assetto Corsa mod's own (1500, 1500, 1540).
	HEADLIGHT = table.freeze({
		range = 60,
		angle = 55,
		brightness = 5,
		color = rgb(248, 248, 255),
		pitch = math.rad(-3),
	}),
	TAIL = table.freeze({
		range = 4,
		brightness = 0.4,
		brakeRange = 8,
		brakeBrightness = 2.2,
		color = rgb(255, 25, 0),
	}),
	INDICATOR = table.freeze({ range = 5, brightness = 1.2, color = AMBER }),
	-- Between the two reversing lamps, facing back.
	REVERSE = table.freeze({ range = 24, angle = 100, brightness = 2, color = rgb(255, 255, 250) }),
	-- The roof console's lamp (the binding's cabinLight), facing down over both seats. Its colour
	-- is not documented; a warm white like most reading lamps.
	CABIN = table.freeze({ range = 9, angle = 140, brightness = 1.2, color = rgb(255, 226, 190) }),
})

return Config
