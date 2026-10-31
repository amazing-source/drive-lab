--!strict
--[[
	The SVJ's sound pack (Config/CarAudio Pack): the uploaded set (made by tools/audio/cut_loops.py
	from the owner's Assetto Corsa mod bank, gbe_lamborghini_aventador_svj_f1; manifest.json beside
	the files), how the loops map to rpm, and the tuning of every event. Volumes are linear; the
	files are loudness-matched (loops at -18 LUFS, pops at -20 LUFS on their loudest 400 ms).
]]
local CarAudio = require("../../CarAudio")

local Audio: CarAudio.Pack = {
	-- One on and one off take is all the bank holds: each is a single steady rpm (measured off
	-- the firing order; the mod's own auto-pitch plays them at x1 at 7,600 and 7,400). The idle
	-- is played at x1 at the car's 950 rpm idle, as the mod does; its firing line would put it
	-- at 1,547 rpm (or half that), which is the owner's to judge by ear.
	engineLayers = {
		{
			name = "Idle",
			soundId = "rbxassetid://123221049271080",
			rpm = 950,
			load = "Both",
			volume = 1,
			-- The idle hands over early: past about 1,550 rpm it would be pitched up by over 60 %.
			crossoverRpm = 1300,
		},
		{ name = "On", soundId = "rbxassetid://73085619329523", rpm = 7558, load = "On", volume = 1 },
		{ name = "Off", soundId = "rbxassetid://95100012663530", rpm = 7268, load = "Off", volume = 1 },
	},
	engineTuning = {
		crossfadeOctaves = 0.5,
		minSpeed = 0.1,
		maxSpeed = 2.5,
		quietRpm = 1000,
		quietDb = -12,
		loudRpm = 8000,
		loudDb = 0,
		liftHalfLife = 0.025,
		pressHalfLife = 0.06,
		volumeHalfLife = 0.03,
		speedHalfLife = 0.012,
	},
	engineVolume = 1,
	-- The on loop raised to 8,700 rpm and gated at 17 Hz: it replaces the on loop's flapping
	-- between fuel cuts, which the frame rate would alias.
	limiter = {
		soundId = "rbxassetid://115677959152238",
		rpm = 8700,
		volume = 1,
		onDuck = 0.3,
		halfLife = 0.03,
	},
	-- A broadband distant roar; the mod plays it 2.5 semitones down.
	far = {
		soundId = "rbxassetid://96220967528313",
		speed = 0.866,
		volume = 0.7,
		fromDistance = 60,
		toDistance = 250,
	},
	eventsSoundId = "rbxassetid://104848480098013",
	-- The starter (its first 0.75 s), the flare, then the cold idle settling; its last 2 s fade
	-- out while the idle loop fades in. Played from the moment START is pressed (Rules/CarEntry).
	startup = {
		region = { from = 0, to = 11 },
		-- The start-up was cut 5.4 dB quieter than the idle loop's gain to keep its flare in range; it
		-- plays 2 dB under that match.
		boostDb = 3.4,
		handOver = 9.0,
		abortRpm = 1400,
		abortHalfLife = 0.08,
	},
	-- The bank's up and down gear sounds are the same file.
	gear = { region = { from = 11.5, to = 11.6938 }, volume = 0.6, upSpeed = 1, downSpeed = 0.92 },
	shiftDip = { gain = 0.5, downHalfLife = 0.012, upHalfLife = 0.05 },
	pops = {
		regions = {
			{ from = 12.1938, to = 12.828 },
			{ from = 13.328, to = 13.674 },
			{ from = 14.174, to = 14.5707 },
			{ from = 15.0707, to = 15.5495 },
			{ from = 16.0495, to = 16.3969 },
			{ from = 16.8969, to = 18.1001 },
		},
		-- Pops are cut 2 dB below the loops and need to stand out of them.
		volume = { from = 1, to = 1.8 },
		speed = { from = 0.92, to = 1.08 },
	},
	-- A stock SVJ pops on every lift and downshift in Sport and Corsa, and Corsa cracks on every
	-- upshift under load; Strada keeps its valves shut longest and is the quietest (road tests,
	-- docs/evidence/audio-pops-flames/research_exhaust.md). The Strada and Sport shares, the
	-- trains and every rpm are our choice: no source gives a number. Each pop throws a flame,
	-- also our choice.
	popTriggers = {
		liftChance = { Strada = 0.35, Sport = 1, Corsa = 1 },
		upshiftChance = { Strada = 0, Sport = 0.6, Corsa = 1 },
		downshiftChance = { Strada = 0.25, Sport = 1, Corsa = 1 },
		liftTrain = { from = 0.35, to = 1.1 },
		downshiftTrain = { from = 0.3, to = 0.8 },
		gap = { from = 0.06, to = 0.22 },
		upshiftMinRpm = 4000,
		upshiftMinThrottle = 0.6,
		-- Strada's braking downshifts come back at 3,200 to 3,500 rpm from seventh to third: under
		-- the old 3,500 they could never pop.
		minRpm = 3000,
		closedThrottle = 0.1,
	},
	events = { liftFrom = 0.6, liftTo = 0.1, liftMinRpm = 4000, limiterHold = 0.15 },
	-- The engine loops are cabin recordings: dry inside. Outside they lose the cabin's boom and
	-- get the exhaust's rasp back; the one-shots are exterior recordings, muffled inside.
	cockpit = { engine = { low = 0, mid = 0, high = 0 }, events = { low = 2, mid = -4, high = -14 }, far = 0 },
	outside = { engine = { low = -5, mid = 1.5, high = 5 }, events = { low = 0, mid = 0, high = 0 }, far = 1 },
	rollOff = { from = 30, to = 600 },
	farRollOff = { from = 60, to = 2000 },
	enginePosition = { forward = -0.6, up = 0.3 },
	exhaustPosition = { forward = -2.2, up = 0.5 },
	-- The start-up's flap lifting and START pressed under it, with the DR458's picks for its guard and
	-- START (Roblox's Pro Sound Effects library), each 6 LU under the idle loop by its measured loudness
	-- (tests/fixtures/control_sounds.json).
	controls = {
		press = {
			-- "Switch Impact On Flip Up Large Metal 2".
			StartFlap = { soundId = "rbxassetid://9119727134", region = { from = 0, to = 0.3 }, db = -13.3 },
			-- "1979 Ford F-150 Pick Up Door Lock Button".
			ENGINE_START = { soundId = "rbxassetid://9125343291", region = { from = 0, to = 0.3 }, db = -3.5 },
		},
	},
}

return table.freeze(Audio)
