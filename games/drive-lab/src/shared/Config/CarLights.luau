--!strict
--[[
	A car's lamps, modelled on the Aventador S and SVJ (issue #41; the SVJ shares the S's units as
	far as photographs show). Each lamp is its own piece of the model's light mesh
	(tools/blender/split_lights.py), named Light_<Corner>_<Lamp>, and glows through its
	SurfaceAppearance; Roblox lights added here throw the light. Each car's glows and lights are
	its entry's (Config/Cars/SVJ/Lights); the behaviour below is every car's.

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

	Not found in any source, so decided by the owner (2026-10-28): the Y goes out on the side whose
	indicator flashes, for the whole cycle (UN R48 6.19.7.5 allows that or dimming); the bumper's
	side marker stays steady, as on the EU SVJ; a high beam on its own control. Chosen, with no
	source: the Y's level with the headlights on (seen lit at night, brightness not measurable).
]]
local CarLights = require("../Rules/CarLights")

-- Colours as 0-255 channels, so the specs can read this file outside Roblox.
export type Rgb = { r: number, g: number, b: number }

-- A lamp's glow: its SurfaceAppearance's EmissiveTint, and EmissiveStrength at full output by
-- day and at night (blended by Rules/CarLights.daylight). `filter`, for a lamp behind a coloured
-- lens, tints the lamp itself (SurfaceAppearance.Color): Roblox's Glass blends with what is
-- behind it rather than filtering it, so a red lens over a white lamp face showed it pink.
export type Glow = { tint: Rgb, day: number, night: number, filter: Rgb? }

-- One of a car's glows by name (its lights' `glow`).
export type GlowName =
	"drl"
	| "projector"
	| "frontIndicator"
	| "frontMarker"
	| "tail"
	| "rearIndicator"
	| "reverse"
	| "fog"
	| "stop"
	| "plate"
	| "rearMarker"

-- A piece of the light mesh in a lamp role, and the glow it shows there.
export type Piece = { name: string, glow: GlowName }

-- Which pieces play each lamp role (Effects/CarLamps). A piece may play several: it shows the
-- brightest of them, and only its indicator while that side's indicator runs. The beams leave
-- the projector pieces, the tail glows the tail pieces, the amber glows the indicator pieces and
-- the reversing light the reverse pieces.
export type Pieces = {
	drlLeft: { Piece },
	drlRight: { Piece },
	projector: { Piece },
	left: { Piece },
	right: { Piece },
	position: { Piece },
	tail: { Piece },
	stop: { Piece },
	reverse: { Piece },
	-- A sequential turn lamp, each side's pieces inner to outer: on the turn signal they light one
	-- after another every `sweepStep` seconds from the start of each flash; on the hazards they
	-- flash together. Optional.
	sweepLeft: { Piece }?,
	sweepRight: { Piece }?,
	sweepStep: number?,
}

-- A rear rain light: how it shows while switched on, and the red light it throws at night.
export type RainLight = { pattern: CarLights.RainPattern, range: number, brightness: number, color: Rgb }

-- One car's lamps (its entry's lights): each lamp's glow, and the Roblox lights its lamps throw.
export type Lights = {
	-- The light pieces (Light_<Corner>_<Lamp>) the lamps cannot work without; the car lights nothing
	-- until all of them have streamed in. Every other piece glows when the model has it.
	required: { string },
	glow: {
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
	headlight: { range: number, angle: number, brightness: number, color: Rgb, pitch: number },
	highBeam: { range: number, angle: number, brightness: number, pitch: number },
	tail: { range: number, brightness: number, brakeRange: number, brakeBrightness: number, color: Rgb },
	-- The glow each indicator piece throws; `rearColor`, where the rear ones differ (red on a US car).
	indicator: { range: number, brightness: number, color: Rgb, rearColor: Rgb? },
	reverse: { range: number, angle: number, brightness: number, color: Rgb },
	cabin: { range: number, angle: number, brightness: number, color: Rgb },
	-- A car with a rain light switch lights its rear fog lamp pieces as the rain light (their
	-- glow is `glow.fog`); without one they never glow.
	rain: RainLight?,
	-- The cockpit's tell-tales, by the switch they show (the model binding's panelLamps).
	tellTales: { [string]: Glow }?,
	-- A car whose light mesh is not split into the house pieces (HOUSE_PIECES). Optional.
	pieces: Pieces?,
}

export type CarLightsConfig = {
	TUNING: CarLights.Tuning,
	-- The pieces of a car without its own `pieces`: Light_<Corner>_<Lamp> as the SVJ and DR458 are
	-- split (tools/blender/split_lights.py).
	HOUSE_PIECES: Pieces,
	-- Lighting.Brightness of the night and the dimmest day presets (Config/Atmosphere).
	NIGHT_BRIGHTNESS: number,
	DAY_BRIGHTNESS: number,
	-- The Ys as tail lamps, a share of their brake output.
	TAIL_SHARE: number,
	PAD_HOLD_SECONDS: number,
}

local HOUSE_PIECES: Pieces = {
	drlLeft = { { name = "Light_FrontLeft_Drl", glow = "drl" } },
	drlRight = { { name = "Light_FrontRight_Drl", glow = "drl" } },
	projector = {
		{ name = "Light_FrontLeft_Projector", glow = "projector" },
		{ name = "Light_FrontRight_Projector", glow = "projector" },
	},
	left = {
		{ name = "Light_FrontLeft_Modules", glow = "frontIndicator" },
		{ name = "Light_RearLeft_Indicator", glow = "rearIndicator" },
	},
	right = {
		{ name = "Light_FrontRight_Modules", glow = "frontIndicator" },
		{ name = "Light_RearRight_Indicator", glow = "rearIndicator" },
	},
	position = {
		{ name = "Light_FrontLeft_Marker", glow = "frontMarker" },
		{ name = "Light_FrontRight_Marker", glow = "frontMarker" },
		{ name = "Light_RearLeft_Marker", glow = "rearMarker" },
		{ name = "Light_RearRight_Marker", glow = "rearMarker" },
		{ name = "Light_RearLeft_Plate", glow = "plate" },
		{ name = "Light_RearRight_Plate", glow = "plate" },
	},
	tail = {
		{ name = "Light_RearLeft_Tail", glow = "tail" },
		{ name = "Light_RearRight_Tail", glow = "tail" },
	},
	stop = {
		{ name = "Light_RearLeft_Bar", glow = "stop" },
		{ name = "Light_RearRight_Bar", glow = "stop" },
	},
	reverse = {
		{ name = "Light_RearLeft_Reverse", glow = "reverse" },
		{ name = "Light_RearRight_Reverse", glow = "reverse" },
	},
}

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
		-- The projector's lens glows brighter on high beam: one bi-xenon unit does both beams
		-- (a shutter moves), so the same lens shows more light.
		highBeamLevel = 1.6,
	}),
	HOUSE_PIECES = table.freeze(HOUSE_PIECES),
	NIGHT_BRIGHTNESS = 0.6,
	DAY_BRIGHTNESS = 1.6,
	-- A stop lamp is at least five times the tail lamp (UN R148 4.8.11; FMVSS 108 table IX).
	TAIL_SHARE = 0.2,
	PAD_HOLD_SECONDS = 0.5,
})

return Config
