--!strict
--[[
	An analog cluster: needles on printed dials (the binding's needles), faces and needles lit from
	behind with the ignition, and small live screens (a message centre, a digital readout); the
	third kind of car display beside Config/Cluster's dial face and Config/Binnacle's screen. What
	the car does not publish (fuel, temperatures, oil pressure) comes from Rules/EngineGauges.
	Temperatures are °C, pressures kPa, speeds km/h inside; a dial converts to its printed unit.
]]
local CarLights = require("./CarLights")
local Cluster = require("./Cluster")

-- What a needle shows: the car's speed and the instruments' revs, or a simulated reading.
export type Reading = "speed" | "rpm" | "fuel" | "coolant" | "oilPressure"

export type Unit = "kmh" | "mph" | "rpm" | "share" | "degC" | "degF" | "kPa" | "psi"

export type Dial = {
	-- One of the binding's needles.
	needle: string,
	reading: Reading,
	unit: Unit,
	-- Readings in `unit`, rising, each with the share of the needle's travel it sits at: linear
	-- between, held at the ends. A flat stretch is a buffered gauge.
	scale: { { number } },
	-- The needle's time constant (seconds, critically damped) and its top speed (shares of its
	-- travel a second), as a stepper motor's; the time constant until the needle first meets its
	-- reading after the ignition.
	response: number,
	maxRate: number,
	catchUp: number,
}

-- Parts lit from behind while the cluster is on, by name, and how their SurfaceAppearance glows.
export type Backlight = { parts: { string }, glow: CarLights.Glow }

-- Seven-segment digits on one of the binding's displays, right-aligned.
export type Readout = {
	display: string,
	shows: "longitudinalG",
	digits: number,
	decimals: number,
	lit: Cluster.Rgb,
	-- How much of an unlit segment shows through the lens: 1 hides it.
	unlitTransparency: number,
	brightness: number,
}

-- Two lines of text on one of the binding's displays.
export type Message = {
	display: string,
	-- After a start with `key`, `keyLines` show until the car first passes moveOffKmh; otherwise
	-- the trip (from this drive) and the odometer, in miles.
	key: string,
	keyLines: { string },
	moveOffKmh: number,
	tripLabel: string,
	odometerMiles: number,
	-- A font family asset (rbxasset://fonts/families/<name>.json), so Lune can load the entry.
	font: string,
	text: Cluster.Rgb,
	brightness: number,
}

-- An engine's oil pressure at one oil temperature (°C): it rises with rpm toward the relief
-- valve's `relief` (kPa), reaching 63 % of it at `rpmScale`.
export type PressurePoint = { temperature: number, relief: number, rpmScale: number }

-- What Rules/EngineGauges simulates from: the tank, the fuel burned for the engine's power, and a
-- lumped coolant mass heated by a share of it, cooled through the thermostat and the radiator.
export type Engine = {
	tankLitres: number,
	-- Share of the tank at the car's first drive on this client; the fuel never falls below
	-- reserveLitres, so the car never runs dry.
	startFuel: number,
	reserveLitres: number,
	-- kg/L, kg/s, kg per joule of brake work, J/kg.
	fuelDensity: number,
	idleFlow: number,
	bsfc: number,
	fuelEnergy: number,
	-- Watts at full power, for the oil's load.
	fullPower: number,
	heatShare: number,
	-- °C: the air, and the engine at its first drive.
	ambient: number,
	-- J/K; W/K to the air through the block with the thermostat shut.
	heatCapacity: number,
	shellLoss: number,
	-- °C: the thermostat starts to open, and is fully open.
	thermostat: { opens: number, open: number },
	-- W/K through the radiator fully open, at rest and per m/s of speed; the fan's (°C, W/K).
	radiator: number,
	radiatorPerSpeed: number,
	fan: { on: number, conductance: number },
	-- The oil follows the coolant with this time constant (s), loadRise °C hotter at full load.
	oil: { lag: number, loadRise: number },
	oilPressure: { cold: PressurePoint, hot: PressurePoint },
	-- Seconds: an engine left off cools toward the air with this time constant.
	coolDown: number,
}

export type Cluster = {
	dials: { Dial },
	-- The red zone starts here; the HUD's rev segments turn red here too.
	redlineRpm: number,
	-- The start-up control whose first move lights the cluster: the key reaching ON.
	lightsWith: string,
	-- Seconds a needle sweep to full scale and back takes as the cluster lights; nil for none.
	sweep: number?,
	backlight: { Backlight },
	readout: Readout?,
	message: Message?,
	engine: Engine,
}

export type Gauges = {
	-- Seconds between redraws of the screens' text; the needles move every frame.
	TEXT_INTERVAL: number,
	-- Seconds between looks for needles and backlit parts that have not streamed in yet.
	RESCAN_INTERVAL: number,
	-- A needle within this share of its reading has met it (Dial.catchUp).
	MET: number,
	-- The longest step the simulation takes; a longer frame is split.
	MAX_STEP: number,
	-- A display's canvas pixels per metre of its screen, so the canvas always has its shape.
	PIXELS_PER_METRE: number,
	-- A seven-segment digit: its bars' thickness and the gap at their corners (shares of its
	-- height), its width over its height, the space between digits (share of a digit's width)
	-- and the digits' height on the screen (share of its height).
	SEGMENT: { thickness: number, gap: number, aspect: number, spacing: number, height: number },
}

local Gauges: Gauges = table.freeze({
	TEXT_INTERVAL = 1 / 30,
	RESCAN_INTERVAL = 1,
	MET = 0.005,
	MAX_STEP = 0.1,
	PIXELS_PER_METRE = 4000,
	SEGMENT = table.freeze({ thickness = 0.14, gap = 0.015, aspect = 0.55, spacing = 0.3, height = 0.8 }),
})

return Gauges
