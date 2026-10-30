--!strict
--[[
	The DR458's sound pack (Config/CarAudio Pack), made by tools/audio/cut_dr458.py from two Assetto
	Corsa 458 Italia banks and shaped toward the Challenge's race exhaust (manifest.json beside the
	files). The loops are cabin recordings at the rpm their 4th engine order gives; every file is
	loudness-matched (loops at -18 LUFS, pops at -20 LUFS on their loudest 400 ms).

	The sound ids stay empty until the owner approves the upload: an empty id plays nothing.
]]
local CarAudio = require("../../CarAudio")

local Audio: CarAudio.Pack = {
	engineLayers = {
		-- The bank has no loop between 800 and 2,000 rpm: through this hand-over the loudest loop
		-- plays up to 58 % fast (the idle) or 45 % slow (the 2,100 rpm loops).
		{ name = "Idle", soundId = "", rpm = 799, load = "Both", volume = 1, crossoverRpm = 1175 },
		{ name = "On2100", soundId = "", rpm = 2124, load = "On", volume = 1 },
		{ name = "On2900", soundId = "", rpm = 2826, load = "On", volume = 1 },
		{ name = "On4900", soundId = "", rpm = 4929, load = "On", volume = 1 },
		{ name = "On5900", soundId = "", rpm = 5902, load = "On", volume = 1 },
		{ name = "On6900", soundId = "", rpm = 6932, load = "On", volume = 1 },
		{ name = "On8100", soundId = "", rpm = 8057, load = "On", volume = 1 },
		-- The bank's off-throttle takes are this much quieter than its on-throttle ones at the
		-- same rpm; the files themselves are matched.
		{ name = "Off2000", soundId = "", rpm = 2026, load = "Off", volume = 0.477 },
		{ name = "Off3800", soundId = "", rpm = 3838, load = "Off", volume = 0.47 },
		{ name = "Off5000", soundId = "", rpm = 5029, load = "Off", volume = 0.485 },
		{ name = "Off7000", soundId = "", rpm = 7004, load = "Off", volume = 0.672 },
		{ name = "Off9000", soundId = "", rpm = 9005, load = "Off", volume = 0.674 },
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
	limiter = { soundId = "", rpm = 9000, volume = 1, onDuck = 0.3, halfLife = 0.03 },
	-- The bank's exterior on-throttle loops from 4,300 to 7,000 rpm summed and low-passed: no
	-- single pitch, so it plays at its own speed.
	far = { soundId = "", speed = 1, volume = 0.7, fromDistance = 60, toDistance = 250 },
	eventsSoundId = "",
	-- Synthesised: the starter cranks for 0.85 s, then the engine flares to 3,200 rpm and settles
	-- to 1,000; its last 2 s fade out while the idle loop fades in.
	startup = {
		region = { from = 0.5, to = 11 },
		boostDb = 0,
		handOver = 8.5,
		abortRpm = 1400,
		abortHalfLife = 0.08,
	},
	gear = { region = { from = 11.5, to = 11.7205 }, volume = 0.6, upSpeed = 1, downSpeed = 0.92 },
	shiftDip = { gain = 0.5, downHalfLife = 0.012, upHalfLife = 0.05 },
	pops = {
		regions = {
			{ from = 12.2205, to = 12.8424 },
			{ from = 13.3424, to = 13.7787 },
			{ from = 14.2787, to = 15.1643 },
			{ from = 15.6643, to = 16.0599 },
			{ from = 16.5599, to = 16.7803 },
			{ from = 17.2803, to = 17.7497 },
			{ from = 18.2497, to = 18.5625 },
			{ from = 19.0625, to = 19.6218 },
			{ from = 20.1218, to = 20.3417 },
		},
		volume = { from = 1, to = 1.8 },
		speed = { from = 0.92, to = 1.08 },
	},
	-- Keyed by the manettino's positions. A race exhaust has no valve, so they all pop alike; when
	-- and how often is our choice: no source on the 458 Challenge gives it.
	popTriggers = {
		liftChance = { ["1"] = 0.7, ["2"] = 0.7, OFF = 0.7 },
		upshiftChance = { ["1"] = 0.3, ["2"] = 0.3, OFF = 0.3 },
		downshiftChance = { ["1"] = 0.8, ["2"] = 0.8, OFF = 0.8 },
		liftTrain = { from = 0.35, to = 1.1 },
		downshiftTrain = { from = 0.3, to = 0.8 },
		gap = { from = 0.06, to = 0.22 },
		upshiftMinRpm = 5000,
		upshiftMinThrottle = 0.6,
		minRpm = 3000,
		closedThrottle = 0.1,
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
}

return table.freeze(Audio)
