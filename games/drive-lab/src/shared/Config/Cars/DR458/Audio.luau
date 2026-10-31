--!strict
--[[
	The DR458's sound pack (Config/CarAudio Pack), made by tools/audio/cut_dr458.py from two Assetto
	Corsa 458 Italia banks and shaped toward the Challenge's race exhaust (manifest.json beside the
	files). The loops are cabin recordings at the rpm their 4th engine order gives; every file is
	loudness-matched (loops at -18 LUFS, pops at -20 LUFS on their loudest 400 ms). Its pops, their
	timing and its flames are the SVJ's.
]]
local CarAudio = require("../../CarAudio")
local SVJ = require("../SVJ/Audio")

local corsa = SVJ.popTriggers

-- dB under the SVJ's own pop level: its off-throttle loops play 3.5 to 6.5 dB under its on ones,
-- so the same pops stood further out of its overrun than out of the SVJ's.
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
		-- The bank has no loop between 800 and 2,000 rpm: through this hand-over the loudest loop
		-- plays up to 58 % fast (the idle) or 45 % slow (the 2,100 rpm loops).
		{
			name = "Idle",
			soundId = "rbxassetid://76328100926971",
			rpm = 799,
			load = "Both",
			volume = 1,
			crossoverRpm = 1175,
		},
		{ name = "On2100", soundId = "rbxassetid://126505420610187", rpm = 2124, load = "On", volume = 1 },
		{ name = "On2900", soundId = "rbxassetid://107339137326473", rpm = 2826, load = "On", volume = 1 },
		{ name = "On4900", soundId = "rbxassetid://83543110847082", rpm = 4929, load = "On", volume = 1 },
		{ name = "On5900", soundId = "rbxassetid://115953926555510", rpm = 5902, load = "On", volume = 1 },
		{ name = "On6900", soundId = "rbxassetid://99354028570947", rpm = 6932, load = "On", volume = 1 },
		{ name = "On8100", soundId = "rbxassetid://108261031727266", rpm = 8057, load = "On", volume = 1 },
		-- The bank's off-throttle takes are this much quieter than its on-throttle ones at the
		-- same rpm; the files themselves are matched.
		{
			name = "Off2000",
			soundId = "rbxassetid://138317459424823",
			rpm = 2026,
			load = "Off",
			volume = 0.477,
		},
		{
			name = "Off3800",
			soundId = "rbxassetid://97883472987350",
			rpm = 3838,
			load = "Off",
			volume = 0.47,
		},
		{
			name = "Off5000",
			soundId = "rbxassetid://129930475034531",
			rpm = 5029,
			load = "Off",
			volume = 0.485,
		},
		{
			name = "Off7000",
			soundId = "rbxassetid://109696677626619",
			rpm = 7004,
			load = "Off",
			volume = 0.672,
		},
		{
			name = "Off9000",
			soundId = "rbxassetid://88011935964948",
			rpm = 9005,
			load = "Off",
			volume = 0.674,
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
	engineVolume = 1,
	-- The top on loop raised to 9,000 rpm and gated at 15 Hz.
	limiter = {
		soundId = "rbxassetid://95790750398183",
		rpm = 9000,
		volume = 1,
		onDuck = 0.3,
		halfLife = 0.03,
	},
	-- The bank's exterior on-throttle loops from 4,300 to 7,000 rpm summed and low-passed: no
	-- single pitch, so it plays at its own speed.
	far = {
		soundId = "rbxassetid://89771951443554",
		speed = 1,
		volume = 0.7,
		fromDistance = 60,
		toDistance = 250,
	},
	eventsSoundId = "rbxassetid://94561113743905",
	startup = {
		-- The fallback: a real Ferrari 360's start (flat-plane V8), starter, catch, flare and
		-- settle; its last 0.8 s fade out while the idle loop fades in.
		region = { from = 0.5, to = 4.85 },
		boostDb = 0.95,
		handOver = 3.55,
		abortRpm = 1400,
		abortHalfLife = 0.08,
		-- "FERRARI 458 STARTUP", a Creator Store upload by another creator: moderation or its
		-- uploader can take it down at any time, and then the region above plays. It ends at a
		-- settling idle, so it hands over where it passes the car's 1,000 rpm idle.
		sound = {
			id = "rbxassetid://126032464409866",
			volume = 3.98,
			from = 0.47,
			starterEnds = 1.17,
			catchAt = 1.18,
			handOver = 3.0,
			to = 3.45,
		},
	},
	gear = { region = { from = 5.35, to = 5.5705 }, volume = 0.38, upSpeed = 1, downSpeed = 0.92 },
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
