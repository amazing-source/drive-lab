--!strict
--[[
	The Boss 302's sound pack (Config/CarAudio Pack), packed by tools/audio/pack_boss302.py
	(manifest.json beside the files): the engine is iRacer5's HPE 650 Assetto Corsa bank, cut by
	tools/audio/cut_boss302.py (its exterior exhaust loops and LS9 off-throttle loops, not its
	supercharger or turbo: the Laguna Seca is naturally aspirated); the start-up a Ford 5.0 V8's
	(Freesound 455925, credited in the README); the gear sounds, grind, pops and backfires the A3DR
	mod's. Every loop sits in one packed bank, each in its own region, matched to -18 LUFS. The
	bank's last region, a lumpy cold idle for the TracKey mode, is not played.
]]
local CarAudio = require("../../CarAudio")
local SVJ = require("../SVJ/Audio")

local BANK = "rbxassetid://76323385151102"
local EVENTS = "rbxassetid://83051264425723"

local svjTriggers = SVJ.popTriggers

-- dB over its loops' matched level that the car plays at, as the DR458 does.
local LEVEL_DB = 8

-- The off-throttle loops are another engine's recordings (LS9), so their raw level says nothing
-- about the Boss's: inside the A3DR bank's own off-to-on ratios (0.54 to 0.69), high enough to keep
-- the engine 6 dB over the wind coasting at top speed (tests/RoadAudio.spec.luau).
local OFF_VOLUME = 0.65

-- The SVJ's drive modes onto the Boss's, quietest to loudest: Normal is the road calibration, as
-- Strada is; TracKey the track calibration, as Corsa is.
local function byMode(chances: { [string]: number }): { [string]: number }
	return { Normal = chances.Strada, Sport = chances.Sport, TracKey = chances.Corsa }
end

local Audio: CarAudio.Pack = {
	engineLayers = {
		{
			name = "Idle",
			soundId = BANK,
			rpm = 818,
			load = "Both",
			volume = 1,
			crossoverRpm = 1250,
			region = { from = 0, to = 2.345986 },
		},
		{
			name = "On1505",
			soundId = BANK,
			rpm = 1505,
			load = "On",
			volume = 1,
			region = { from = 2.595987, to = 3.472993 },
		},
		{
			name = "On2250",
			soundId = BANK,
			rpm = 2250,
			load = "On",
			volume = 1,
			region = { from = 3.722994, to = 4.576258 },
		},
		{
			name = "On3019",
			soundId = BANK,
			rpm = 3019,
			load = "On",
			volume = 1,
			region = { from = 4.826259, to = 5.223718 },
		},
		{
			name = "On3540",
			soundId = BANK,
			rpm = 3540,
			load = "On",
			volume = 1,
			region = { from = 5.473719, to = 6.321201 },
		},
		{
			name = "On4050",
			soundId = BANK,
			rpm = 4050,
			load = "On",
			volume = 1,
			region = { from = 6.571202, to = 7.429455 },
		},
		{
			name = "On5069",
			soundId = BANK,
			rpm = 5069,
			load = "On",
			volume = 1,
			region = { from = 7.679456, to = 8.508049 },
		},
		{
			name = "On6083",
			soundId = BANK,
			rpm = 6083,
			load = "On",
			volume = 1,
			region = { from = 8.75805, to = 9.547074 },
		},
		{
			name = "On7113",
			soundId = BANK,
			rpm = 7113,
			load = "On",
			volume = 1,
			region = { from = 9.797075, to = 10.842517 },
		},
		{
			name = "Off2849",
			soundId = BANK,
			rpm = 2849,
			load = "Off",
			volume = OFF_VOLUME,
			region = { from = 11.092518, to = 15.506394 },
		},
		{
			name = "Off3786",
			soundId = BANK,
			rpm = 3786,
			load = "Off",
			volume = OFF_VOLUME,
			region = { from = 15.756395, to = 18.189115 },
		},
		{
			name = "Off6056",
			soundId = BANK,
			rpm = 6056,
			load = "Off",
			volume = OFF_VOLUME,
			region = { from = 18.439116, to = 20.620022 },
		},
	},
	engineTuning = {
		crossfadeOctaves = 0.5,
		minSpeed = 0.1,
		maxSpeed = 2.5,
		quietRpm = 700,
		quietDb = -12,
		loudRpm = 7000,
		loudDb = 0,
		liftHalfLife = 0.025,
		pressHalfLife = 0.06,
		volumeHalfLife = 0.03,
		speedHalfLife = 0.012,
	},
	engineVolume = 10 ^ (LEVEL_DB / 20),
	-- The top on loop raised to 7,500 rpm and gated at 15 Hz.
	limiter = {
		soundId = BANK,
		rpm = 7500,
		volume = 1,
		onDuck = 0.3,
		halfLife = 0.03,
		region = { from = 20.870023, to = 21.861519 },
	},
	-- Its exterior on-throttle loops from 4,050 to 7,113 rpm summed and low-passed: no single
	-- pitch, so it plays at its own speed.
	far = {
		soundId = BANK,
		speed = 1,
		volume = 0.7,
		fromDistance = 60,
		toDistance = 250,
		region = { from = 22.11152, to = 22.900544 },
	},
	eventsSoundId = EVENTS,
	-- The 5.0's start as recorded, from behind the car: starter, catch, a flare to about 1,500 rpm
	-- and a settle at about 1,230; its last 0.8 s fade out while the idle loop fades in. Peak-limited
	-- in its file, so its settled end sits 7.9 dB under the loops' level.
	startup = {
		region = { from = 0, to = 5.299977 },
		boostDb = 7.9,
		handOver = 4.5,
		-- Over the start-up's own flare, so only the driver's revs cut it short.
		abortRpm = 1700,
		abortHalfLife = 0.08,
	},
	gear = {
		region = { from = 5.799978, to = 6.096077 },
		downRegion = { from = 6.596078, to = 6.789886 },
		volume = 0.5,
		upSpeed = 1,
		downSpeed = 1,
	},
	-- The first 0.45 s of the mod's grind, about as long as a refused lever is held at the gate.
	grind = { region = { from = 7.289887, to = 7.739887 }, volume = 0.5, fadeOut = 0.08 },
	shiftDip = { gain = 0.5, downHalfLife = 0.012, upHalfLife = 0.05 },
	pops = {
		regions = {
			{ from = 10.315874, to = 10.504671 },
			{ from = 11.004672, to = 11.169183 },
			{ from = 11.669184, to = 11.857981 },
			{ from = 12.357982, to = 12.478684 },
			{ from = 12.978685, to = 13.088979 },
			{ from = 13.58898, to = 13.96619 },
			{ from = 14.466191, to = 14.813492 },
			{ from = 15.313493, to = 15.79229 },
		},
		volume = { from = 1, to = 1.25 },
		speed = { from = 0.95, to = 1.05 },
	},
	-- The SVJ's timing, mode by mode (byMode).
	popTriggers = {
		liftChance = byMode(svjTriggers.liftChance),
		upshiftChance = byMode(svjTriggers.upshiftChance),
		downshiftChance = byMode(svjTriggers.downshiftChance),
		liftTrain = svjTriggers.liftTrain,
		downshiftTrain = svjTriggers.downshiftTrain,
		gap = svjTriggers.gap,
		upshiftMinRpm = svjTriggers.upshiftMinRpm,
		upshiftMinThrottle = svjTriggers.upshiftMinThrottle,
		minRpm = svjTriggers.minRpm,
		closedThrottle = svjTriggers.closedThrottle,
	},
	events = { liftFrom = 0.6, liftTo = 0.1, liftMinRpm = 3500, limiterHold = 0.15 },
	-- The loops are exterior exhaust recordings: as recorded outside, muffled in the cabin.
	cockpit = {
		engine = { low = 2, mid = -1, high = -6 },
		events = { low = 2, mid = -3, high = -10 },
		far = 0,
	},
	outside = { engine = { low = 0, mid = 0, high = 0 }, events = { low = 0, mid = 0, high = 0 }, far = 1 },
	rollOff = { from = 30, to = 600 },
	farRollOff = { from = 60, to = 2000 },
	-- Front-engined, two outlets at the tail. EST until the binding has its exhaust outlets.
	enginePosition = { forward = 1.3, up = 0.5 },
	exhaustPosition = { forward = -2.3, up = 0.3 },
}

return Audio
