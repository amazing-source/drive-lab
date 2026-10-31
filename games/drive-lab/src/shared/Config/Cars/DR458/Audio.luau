--!strict
--[[
	The DR458's sound pack (Config/CarAudio Pack), made by tools/audio/cut_dr458_gdc.py from Pole
	Position Production's Ferrari 458 recordings in the Sonniss GDC bundles (manifest.json beside the
	files): onboard full-throttle and coast-down ramps at the straight-pipe exhaust, with the stock
	car's intake under them. Every loop sits in one packed file, each in its own region, cut where
	the ramps cross its rpm and matched to -18 LUFS; the volumes keep the mix's levels. Its pops,
	their timing and its flames are the SVJ's.
]]
local CarAudio = require("../../CarAudio")
local SVJ = require("../SVJ/Audio")

local BANK = "rbxassetid://134452098270493"
local EVENTS = "rbxassetid://79771227703971"

local corsa = SVJ.popTriggers

-- dB over its loops' matched level that the car plays at: its engine, and everything that follows its
-- level (Config/CarAudio carGain).
local LEVEL_DB = 8

-- dB under the SVJ's pop level against its engine: the DR458's off-throttle loops play 3.5 to 6.5 dB
-- under its on ones, so the same pops stood further out of its overrun than out of the SVJ's.
local POPS_GAIN_DB = -4.5
local popsGain = 10 ^ (POPS_GAIN_DB / 20)

-- The wheel's push buttons ("1965 Jaguar E-Type Car Interior Switches 19") and the panel's toggles
-- ("Moviola Toggle Switch Single Clicks Sharp 10").
local WHEEL_BUTTON: CarAudio.ControlSound =
	{ soundId = "rbxassetid://9112955977", region = { from = 0, to = 0.25 }, db = 7.9 }
local PANEL_TOGGLE: CarAudio.ControlSound =
	{ soundId = "rbxassetid://9117028855", region = { from = 0, to = 0.25 }, db = -4.5 }

local function everyPosition(chances: { [string]: number }): { [string]: number }
	return { ["1"] = chances.Corsa, ["2"] = chances.Corsa, OFF = chances.Corsa }
end

local Audio: CarAudio.Pack = {
	engineLayers = {
		{
			name = "Idle",
			soundId = BANK,
			rpm = 1000,
			load = "Both",
			volume = 1.3958,
			crossoverRpm = 1250,
			region = { from = 0, to = 2.4475 },
		},
		{
			name = "On1500",
			soundId = BANK,
			rpm = 1500,
			load = "On",
			volume = 1.4089,
			region = { from = 2.6975, to = 4.4005 },
		},
		{
			name = "On2250",
			soundId = BANK,
			rpm = 2250,
			load = "On",
			volume = 1.1037,
			region = { from = 4.6505, to = 6.666 },
		},
		{
			name = "On3000",
			soundId = BANK,
			rpm = 3000,
			load = "On",
			volume = 0.9684,
			region = { from = 6.916, to = 9.233 },
		},
		{
			name = "On3750",
			soundId = BANK,
			rpm = 3750,
			load = "On",
			volume = 0.964,
			region = { from = 9.483, to = 12.58 },
		},
		{
			name = "On4500",
			soundId = BANK,
			rpm = 4500,
			load = "On",
			volume = 1.03,
			region = { from = 12.83, to = 16.428999 },
		},
		{
			name = "On5250",
			soundId = BANK,
			rpm = 5250,
			load = "On",
			volume = 1,
			region = { from = 16.679, to = 20.982 },
		},
		{
			name = "On6000",
			soundId = BANK,
			rpm = 6000,
			load = "On",
			volume = 1.0554,
			region = { from = 21.232, to = 26.16 },
		},
		{
			name = "On6750",
			soundId = BANK,
			rpm = 6750,
			load = "On",
			volume = 1.0116,
			region = { from = 26.41, to = 32.02 },
		},
		{
			name = "On7500",
			soundId = BANK,
			rpm = 7500,
			load = "On",
			volume = 0.9789,
			region = { from = 32.270001, to = 38.5495 },
		},
		{
			name = "On8250",
			soundId = BANK,
			rpm = 8250,
			load = "On",
			volume = 0.9864,
			region = { from = 38.7995, to = 46.036 },
		},
		{
			name = "On8800",
			soundId = BANK,
			rpm = 8800,
			load = "On",
			volume = 0.937,
			region = { from = 46.286, to = 51.2465 },
		},
		{
			name = "Off1500",
			soundId = BANK,
			rpm = 1500,
			load = "Off",
			volume = 0.8186,
			region = { from = 51.4965, to = 53.6795 },
		},
		{
			name = "Off2500",
			soundId = BANK,
			rpm = 2500,
			load = "Off",
			volume = 0.6399,
			region = { from = 53.9295, to = 59.448 },
		},
		{
			name = "Off3500",
			soundId = BANK,
			rpm = 3500,
			load = "Off",
			volume = 0.47,
			region = { from = 59.698, to = 66.1615 },
		},
		{
			name = "Off4500",
			soundId = BANK,
			rpm = 4500,
			load = "Off",
			volume = 0.47,
			region = { from = 66.411501, to = 74.0025 },
		},
		{
			name = "Off5500",
			soundId = BANK,
			rpm = 5500,
			load = "Off",
			volume = 0.8158,
			region = { from = 74.2525, to = 82.1405 },
		},
		{
			name = "Off6500",
			soundId = BANK,
			rpm = 6500,
			load = "Off",
			volume = 0.8985,
			region = { from = 82.3905, to = 89.1645 },
		},
		{
			name = "Off7500",
			soundId = BANK,
			rpm = 7500,
			load = "Off",
			volume = 0.955,
			region = { from = 89.4145, to = 95.19 },
		},
		{
			name = "Off8500",
			soundId = BANK,
			rpm = 8500,
			load = "Off",
			volume = 0.8709,
			region = { from = 95.44, to = 103.033 },
		},
	},
	engineTuning = {
		crossfadeOctaves = 0.5,
		minSpeed = 0.1,
		maxSpeed = 2.5,
		quietRpm = 1000,
		quietDb = -12,
		loudRpm = 8500,
		loudDb = 0,
		liftHalfLife = 0.025,
		pressHalfLife = 0.06,
		volumeHalfLife = 0.03,
		speedHalfLife = 0.012,
	},
	engineVolume = 10 ^ (LEVEL_DB / 20),
	-- The top on loop raised to 9,000 rpm and gated at 15 Hz.
	limiter = {
		soundId = BANK,
		rpm = 9000,
		volume = 0.937,
		onDuck = 0.3,
		halfLife = 0.03,
		region = { from = 103.283, to = 108.083 },
	},
	-- The previous bank's exterior on-throttle loops from 4,300 to 7,000 rpm summed and low-passed:
	-- no single pitch, so it plays at its own speed.
	far = {
		soundId = "rbxassetid://89771951443554",
		speed = 1,
		volume = 0.7,
		fromDistance = 60,
		toDistance = 250,
	},
	eventsSoundId = EVENTS,
	-- A Ferrari F40 LM's start (flat-plane V8) from its onboard microphone: starter, catch and a
	-- settle from about 1,290 rpm, played at the speed that lands it on the car's 1,000 rpm idle; its
	-- last 0.8 s fade out while the idle loop fades in.
	startup = {
		region = { from = 0, to = 5.87125 },
		boostDb = 6,
		handOver = 5.0713,
		abortRpm = 1400,
		abortHalfLife = 0.08,
	},
	gear = { region = { from = 6.37125, to = 6.59175 }, volume = 0.38, upSpeed = 1, downSpeed = 0.92 },
	shiftDip = { gain = 0.5, downHalfLife = 0.012, upHalfLife = 0.05 },
	pops = {
		soundId = SVJ.eventsSoundId,
		regions = SVJ.pops.regions,
		volume = { from = SVJ.pops.volume.from * popsGain, to = SVJ.pops.volume.to * popsGain },
		speed = SVJ.pops.speed,
	},
	-- The SVJ's Corsa timing in every manettino position: a race exhaust has no valve to close.
	popTriggers = {
		liftChance = everyPosition(corsa.liftChance),
		upshiftChance = everyPosition(corsa.upshiftChance),
		downshiftChance = everyPosition(corsa.downshiftChance),
		liftTrain = corsa.liftTrain,
		downshiftTrain = corsa.downshiftTrain,
		gap = corsa.gap,
		upshiftMinRpm = corsa.upshiftMinRpm,
		upshiftMinThrottle = corsa.upshiftMinThrottle,
		minRpm = corsa.minRpm,
		closedThrottle = corsa.closedThrottle,
	},
	events = { liftFrom = 0.6, liftTo = 0.1, liftMinRpm = 4000, limiterHold = 0.15 },
	-- The loops are already shaped toward the exhaust; a stripped race cabin keeps its boom.
	cockpit = {
		engine = { low = 1, mid = 0, high = -2 },
		events = { low = 2, mid = -3, high = -10 },
		far = 0,
	},
	outside = { engine = { low = -4, mid = 1.5, high = 3 }, events = { low = 0, mid = 0, high = 0 }, far = 1 },
	rollOff = { from = 30, to = 600 },
	farRollOff = { from = 60, to = 2000 },
	-- Mid-engined: the V8 sits behind the cabin, the two outlets low in the centre of the tail.
	enginePosition = { forward = -0.5, up = 0.3 },
	exhaustPosition = { forward = -2.2, up = 0.35 },
	-- Roblox's licensed Pro Sound Effects library, but the wiper motor (in the events file). Each
	-- `db` lands its loudest 100 ms 6 LU under the idle loop (the loops 12 LU, the radio's hiss 14
	-- and its tail 8), by the loudness tools/audio/measure_control_sounds.py measured
	-- (tests/fixtures/dr458_control_sounds.json).
	controls = {
		press = {
			HIGH_BEAM = WHEEL_BUTTON,
			PIT_LIMITER = WHEEL_BUTTON,
			DISPLAY_PAGE = WHEEL_BUTTON,
			WASHER = WHEEL_BUTTON,
			WIPER = WHEEL_BUTTON,
			RAIN_LIGHT = PANEL_TOGGLE,
			PanelSwitch_Ignition = PANEL_TOGGLE,
			HEADLIGHTS = PANEL_TOGGLE,
			-- "Rotary Switch 2".
			DRIVING_MODE = { soundId = "rbxassetid://9118727603", region = { from = 0, to = 0.25 }, db = 0.4 },
			-- "Ferrari 308 Car Ignition Keys Movement 4": the key's turn.
			TunnelKey_Master = {
				soundId = "rbxassetid://9114402893",
				region = { from = 2.15, to = 2.6 },
				db = -10.7,
			},
			-- "Switch Impact On Flip Up Large Metal 2".
			PanelGuard_Ignition = {
				soundId = "rbxassetid://9119727134",
				region = { from = 0, to = 0.3 },
				db = -13.3,
			},
			-- "1979 Ford F-150 Pick Up Door Lock Button".
			ENGINE_START = { soundId = "rbxassetid://9125343291", region = { from = 0, to = 0.3 }, db = -3.5 },
		},
		-- "Police Radio Button Pushes Walkie Talkie 2", "Radio Static 1" and "Radio Squelches 32".
		radio = {
			press = { soundId = "rbxassetid://9117795848", region = { from = 0, to = 0.15 }, db = 3.5 },
			hiss = { soundId = "rbxassetid://9118026602", region = { from = 0.2, to = 2.2 }, db = -17.6 },
			release = { soundId = "rbxassetid://9118021986", region = { from = 0.27, to = 1 }, db = -11.9 },
		},
		-- One wipe of the recording lasts 1.42 s: the rates fit it to the 1.33 s and 0.92 s wipes.
		wiperMotor = {
			soundId = "rbxassetid://79771227703971",
			region = { from = 7.09175, to = 14.19175 },
			db = -12,
			rates = { 1.065, 1.538 },
		},
		-- "Water Hose Gun 1".
		washerPump = { soundId = "rbxassetid://9120563177", region = { from = 0, to = 0.4 }, db = -15.6 },
	},
}

return table.freeze(Audio)
