--!strict
--[[
	The Boss 302 Laguna Seca's analog cluster (Config/Gauges): the cluster's speedometer,
	tachometer, fuel and coolant gauges and the dash-top pod's oil pressure and water temperature,
	from Ford's 2012 Boss 302 owner's supplement (p.8-18) and the face atlas's measured sweeps; the
	pod's performance gauge in its real-time mode, and the tachometer's message centre. The needles'
	timings and the engine's heat are estimates (EST): no source gives them.
]]
local Gauges = require("../../Gauges")

local function rgb(r: number, g: number, b: number): { r: number, g: number, b: number }
	return table.freeze({ r = r, g = g, b = b })
end

local Boss302Gauges: Gauges.Cluster = {
	dials = {
		-- 0 to 180 mph across the face's half turn (km/h is printed inside, read off the same needle).
		{
			needle = "Needle_Speedo",
			reading = "speed",
			unit = "mph",
			scale = { { 0, 0 }, { 180, 1 } },
			response = 0.2,
			maxRate = 3,
			catchUp = 0.2,
		},
		{
			needle = "Needle_Tach",
			reading = "rpm",
			unit = "rpm",
			scale = { { 0, 0 }, { 9000, 1 } },
			response = 0.06,
			maxRate = 3.3,
			catchUp = 0.06,
		},
		-- EST: E with about 6 % left, as Ford's gauges keep a reserve under E. Damped against the
		-- fuel's slosh; at the ignition the slow needles reach their reading in a second or two.
		{
			needle = "Needle_Fuel",
			reading = "fuel",
			unit = "share",
			scale = { { 0.06, 0 }, { 1, 1 } },
			response = 20,
			maxRate = 1,
			catchUp = 0.25,
		},
		-- Inferred: Ford's cluster holds the needle mid across the normal band (the band is EST);
		-- the pod's water gauge shows the true temperature.
		{
			needle = "Needle_Temp",
			reading = "coolant",
			unit = "degF",
			scale = { { 100, 0 }, { 165, 0.5 }, { 235, 0.5 }, { 260, 1 } },
			response = 2,
			maxRate = 0.6,
			catchUp = 0.25,
		},
		{
			needle = "Needle_Oil",
			reading = "oilPressure",
			unit = "psi",
			scale = { { 0, 0 }, { 100, 1 } },
			response = 0.15,
			maxRate = 2,
			catchUp = 0.15,
		},
		{
			needle = "Needle_Water",
			reading = "coolant",
			unit = "degF",
			scale = { { 100, 0 }, { 260, 1 } },
			response = 1,
			maxRate = 0.6,
			catchUp = 0.25,
		},
	},
	-- The face's red zone and the documented redline.
	redlineRpm = 7500,
	-- The cluster lights at ON, before the key goes on to START (Config/Cars/Boss302/Startup).
	lightsWith = "Key_Ignition",
	-- No source shows the 2012 cluster sweeping its needles at the ignition.
	sweep = nil,
	backlight = {
		{
			parts = {
				"Cluster_Face_Speedo",
				"Cluster_Face_Tach",
				"Cluster_Face_FuelTemp",
				"Pod_Face_Oil",
				"Pod_Face_Digital",
				"Pod_Face_Water",
			},
			-- The face atlas's printed cyan.
			glow = table.freeze({ tint = rgb(130, 206, 220), day = 2.5, night = 1 }),
		},
		{
			parts = {
				"Needle_Speedo",
				"Needle_Tach",
				"Needle_Fuel",
				"Needle_Temp",
				"Needle_Oil",
				"Needle_Water",
			},
			glow = table.freeze({ tint = rgb(255, 60, 40), day = 3, night = 1.2 }),
		},
	},
	-- Real-time mode, where the performance gauge starts: acceleration in g on three red digits,
	-- "0.00" at rest (photos bat4_079, hag1_082, where unlit segments show faintly).
	readout = {
		display = "PodReadout",
		shows = "longitudinalG",
		digits = 3,
		decimals = 2,
		lit = rgb(255, 48, 36),
		unlitTransparency = 0.93,
		brightness = 2,
	},
	-- The TracKey's start message (Ford Racing's TracKey instructions); TRIP A and the odometer as
	-- in the photos, from the reference car's 1,313.9 miles (photo hag3_041).
	message = {
		display = "MessageCentre",
		key = "TracKey",
		keyLines = { "TRACKEY ACTIVE", "TRACK USE ONLY" },
		moveOffKmh = 5,
		tripLabel = "TRIP A",
		odometerMiles = 1313.9,
		font = "rbxasset://fonts/families/RobotoMono.json",
		text = rgb(205, 235, 255),
		brightness = 1.6,
	},
	engine = {
		-- Documented: 16.0 gallons (supplement p.32).
		tankLitres = 60.5,
		startFuel = 0.8,
		reserveLitres = 4,
		fuelDensity = 0.745,
		-- EST: about 2.9 litres an hour at idle; 320 g/kWh, a naturally aspirated V8 at full load.
		idleFlow = 0.0006,
		bsfc = 0.32 / 3.6e6,
		fuelEnergy = 43e6,
		-- Documented: 444 hp.
		fullPower = 331e3,
		heatShare = 0.35,
		ambient = 21,
		heatCapacity = 120e3,
		shellLoss = 30,
		thermostat = { opens = 91, open = 103 },
		radiator = 500,
		radiatorPerSpeed = 24,
		fan = { on = 100, conductance = 600 },
		oil = { lag = 240, loadRise = 30 },
		-- Documented: 80 to 100 psi, and more, is normal on a cold start (supplement p.9). Warm, EST:
		-- about 25 psi at idle, a 75 psi relief valve.
		oilPressure = {
			cold = { temperature = 20, relief = 758, rpmScale = 520 },
			hot = { temperature = 100, relief = 517, rpmScale = 1730 },
		},
		coolDown = 1800,
	},
}

return table.freeze(Boss302Gauges)
