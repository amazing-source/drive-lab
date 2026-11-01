--!strict
--[[
	Ford Mustang Boss 302 Laguna Seca, 2012. Every number comes from the researcher's note
	(drive-lab-assets/boss302/research/references_data_vfx.md, section 1); the tag after it is that
	note's confidence (documented, likely, inferred, unknown), or EST where the value is ours, a
	starting point for calibration and not data. The Laguna Seca's own parts are used where they
	differ from the plain Boss: the Torsen, the R-compound tyres, the larger splitter and spoiler.
]]
local Types = require("../Types")

-- Shift points of the automatic for the H box (`gearboxMode = "auto"`); the human shift itself
-- comes from `gearbox.manual.timing`, so the ISR times below only fill the shared shape. At full
-- throttle it shifts 100 rpm under the limiter, as the other cars do.
local function mode(settings: {
	upshiftRpm: Types.ShiftPoints,
	downshiftRpm: Types.ShiftPoints,
	brakeDownshiftRpm: number,
	holdOnLift: boolean,
	tcSlipRatio: number,
	escOversteer: number,
	escUndersteer: number,
	escSideslip: number,
	idleRpm: number?,
}): Types.ModeConfig
	return {
		upshiftTime = 0.5,
		downshiftTime = 0.5,
		upshiftRpm = settings.upshiftRpm,
		downshiftRpm = settings.downshiftRpm,
		brakeDownshiftRpm = settings.brakeDownshiftRpm,
		holdOnLift = settings.holdOnLift,
		-- Rear drive.
		frontShareDrive = 0,
		frontShareCoast = 0,
		-- EST: the dampers are set by screwdriver (5 positions, 2 from the factory, likely), never
		-- from the seat, so every mode has the same. Firm, as a track car's: at 0.45 the soft springs
		-- pitched enough at 30 FPS to stop 4 % longer from 100 km/h than at 240 FPS.
		damperRatio = 0.6,
		tcSlipRatio = settings.tcSlipRatio,
		escOversteer = settings.escOversteer,
		escUndersteer = settings.escUndersteer,
		escSideslip = settings.escSideslip,
		idleRpm = settings.idleRpm,
	}
end

return Types.define({
	name = "Ford Mustang Boss 302 Laguna Seca",
	-- EST: 1,647 kg curb (documented, the Boss with the manual) and a 75 kg driver.
	mass = 1720,
	-- Likely: 55/45 ("est." on Ford's sheet).
	frontWeightShare = 0.55,
	-- EST, §1.3: a 1.40 m tall front-engine coupe, and a dynamic index of 0.9-1.0.
	cgHeight = 0.51,
	yawInertia = 2900,
	pitchInertia = 2650,
	rollInertia = 580,
	-- Documented: 107.1 in.
	wheelbase = 2.720,

	front = {
		-- Documented (the LS sheet): 61.9 in.
		track = 1.572,
		-- EST: 19 in wheel, iron hub, a big Brembo disc.
		wheelInertia = 1.4,
		unsprungMass = 50,
		-- EST, §1.4: from the LS springs (24.0 N/mm, likely) and a motion ratio of 1.
		rideFrequency = 1.2,
		tyre = {
			-- Inferred: about 0.330 m loaded (255/40ZR19, 0.343 m free).
			radius = 0.330,
			-- EST: Pirelli P Zero Corsa System, which Ford calls R-compound (documented). Set so the
			-- car holds about the 0.98-0.99 g skidpad (likely) and stops at about 1.18 g (inferred).
			peakMuX = 1.30,
			peakMuY = 1.12,
			slipRatioAtPeak = 0.10,
			slipAngleAtPeak = math.rad(6.5),
			slidingRatioX = 0.80,
			slidingRatioY = 0.82,
			curvatureX = -0.5,
			curvatureY = -0.5,
			-- About the static corner load, so peakMu applies at rest.
			referenceLoad = 4640,
			loadSensitivity = 0.85,
			relaxationLengthX = 0.15,
			relaxationLengthY = 0.30,
			carcassDampingRatio = 0.5,
			rollingResistance = 0.012,
			rollingResistancePerSpeed = 4.3e-4,
		},
	},

	rear = {
		-- Documented (the LS sheet): 62.5 in.
		track = 1.588,
		wheelInertia = 1.6,
		-- EST: a live axle carries far more unsprung mass than a strut.
		unsprungMass = 75,
		-- EST, §1.4: from the LS springs (33.4 N/mm, likely) and a motion ratio of 0.85.
		rideFrequency = 1.35,
		tyre = {
			-- Inferred: about 0.330 m loaded (285/35ZR19, 0.341 m free).
			radius = 0.330,
			-- The front's compound on a wider, lighter-loaded tyre, by the tyres' own load sensitivity:
			-- (4640 / 3800)^0.15 for the lighter reference load and (285 / 255)^0.15 for the width
			-- spreading it, 1.048 times the front's in both directions (#220).
			peakMuX = 1.36,
			peakMuY = 1.17,
			slipRatioAtPeak = 0.10,
			slipAngleAtPeak = math.rad(6.5),
			slidingRatioX = 0.80,
			slidingRatioY = 0.82,
			curvatureX = -0.5,
			curvatureY = -0.5,
			referenceLoad = 3800,
			loadSensitivity = 0.85,
			relaxationLengthX = 0.15,
			relaxationLengthY = 0.30,
			carcassDampingRatio = 0.5,
			rollingResistance = 0.012,
			rollingResistancePerSpeed = 4.3e-4,
		},
	},

	suspension = {
		-- EST: no travel figure is published. The soft LS springs need room both ways, as the model
		-- has no anti-dive or anti-squat: 1.2 g of braking on a 0.51 m CG moves 1.9 kN per corner,
		-- 8.5 cm of rear droop on its 22 N/mm wheel rate and 7.9 cm of front dive on its 24 N/mm,
		-- onto the bump stop.
		travel = 0.190,
		staticCompression = 0.100,
		bumpStopStart = 0.170,
		bumpStopRate = 30000,
		-- Capped as the SVJ's is (ω·dt about 1 at 30 FPS), on a 473 kg front corner.
		bumpStopMaxRate = 400000,
		bumpStopProgression = 2.0e7,
		damperKneeSpeed = 0.08,
		damperFastRatio = 0.4,
		damperReboundRatio = 1.5,
		-- EST: softer in roll than the two supercars; the 34.6 mm front bar (documented) against a
		-- 26 mm rear (documented, LS) puts most of the roll stiffness at the front.
		rollGradient = math.rad(1.4),
		frontRollShare = 0.58,
	},

	engine = {
		-- EST shape (§1.1) through two documented anchors: 515 Nm at 4,500 rpm and 444 hp at
		-- 7,400 rpm (427 Nm). Below 3,000 rpm the shape has no source.
		torqueCurve = {
			{ rpm = 1000, torque = 330 },
			{ rpm = 1500, torque = 365 },
			{ rpm = 2000, torque = 400 },
			{ rpm = 2500, torque = 435 },
			{ rpm = 3000, torque = 465 },
			{ rpm = 3500, torque = 488 },
			{ rpm = 4000, torque = 505 },
			{ rpm = 4500, torque = 515 },
			{ rpm = 5000, torque = 513 },
			{ rpm = 5500, torque = 505 },
			{ rpm = 6000, torque = 493 },
			{ rpm = 6500, torque = 474 },
			{ rpm = 7000, torque = 450 },
			{ rpm = 7400, torque = 427 },
			{ rpm = 7500, torque = 421 },
		},
		-- EST, as the others: 2 bar of friction and pumping at idle rising to 4 bar at the top,
		-- 39.4 Nm per bar on 4,951 cm³.
		dragLow = { rpm = 700, torque = 79 },
		dragHigh = { rpm = 7500, torque = 158 },
		-- EST: a V8's flywheel and clutch.
		inertia = 0.20,
		-- Unknown: no idle is published. TracKey's lopey idle is its drive mode's `idleRpm`.
		idleRpm = 700,
		-- EST: the 7,500 rpm redline (documented, "projected"); the fuel cut is not published.
		limiterRpm = 7500,
		limiterHysteresis = 150,
		-- Documented (TracKey sheet): Ford suggests about 2,600 rpm for its launch control.
		launchRpm = 2600,
		-- Documented: 155 mph top speed, a limit rather than the gearing's (inferred: 5th reaches it
		-- at the redline). EST: the throttle fades over the last 2 km/h.
		governor = { speed = 155 * 1.609344 / 3.6, band = 2 / 3.6 },
	},

	gearbox = {
		kind = "manual",
		manual = {
			-- The MT-82's H (documented): reverse far left and up, behind a push-down lockout; 1-2,
			-- 3-4 and 5-6 left to right. The lever rests on the rail in the 3-4 plane.
			gates = {
				[-1] = { column = -1, row = 1 },
				[0] = { column = 1, row = 0 },
				[1] = { column = 0, row = 1 },
				[2] = { column = 0, row = -1 },
				[3] = { column = 1, row = 1 },
				[4] = { column = 1, row = -1 },
				[5] = { column = 2, row = 1 },
				[6] = { column = 2, row = -1 },
			},
			-- EST: a quick human shift on a short-throw box (documented short-throw), as a road test's
			-- driver makes it: about 0.37 s from the clutch going down to fully up for 1-2 with the hand
			-- and foot already there, 0.47 s for 2-3 across the gate. A 0.5 s 1-2 left the standing start
			-- a tenth slow per shift against the published runs (#220). The reach and the foot's move
			-- are the driver animation's to confirm.
			timing = {
				reach = 0.30,
				release = 0.35,
				footMove = 0.20,
				clutchIn = 0.08,
				leave = 0.06,
				push = 0.10,
				crossBase = 0.05,
				crossPerColumn = 0.05,
				enter = 0.08,
				clutchOut = 0.15,
				linger = 1.5,
			},
			-- EST: the clutch bites from 0.6 of the pedal and holds fully from 0.3.
			bitePoint = 0.6,
			biteWidth = 0.3,
			-- EST: under 450 rpm with the clutch biting, the engine dies.
			stallRpm = 450,
			-- The 2012 car has no rev-matching.
			revMatch = false,
			-- The clutch on a key is offered for the owner to try; false takes it out of the modes.
			playerClutch = true,
		},
		-- Documented: 3.66, 2.43, 1.69, 1.32, 1.00, 0.65.
		ratios = { 3.66, 2.43, 1.69, 1.32, 1.00, 0.65 },
		-- Likely (forum): 3.32.
		reverseRatio = 3.32,
		-- As the other cars: 40 km/h is the owner's reverse limit (#70), not a car figure.
		reverseMaxSpeed = 40 / 3.6,
		reverseCutBand = 4 / 3.6,
		-- EST: the "race-inspired" clutch (documented) at about 1.45 × the peak torque.
		clutchTorque = 750,
		-- The automatic clutch's creep and slip band, as the others'.
		clutchCreepRpm = 1200,
		clutchSlipBand = 0.2,
		-- EST: the race clutch closes in 0.12 s. At the others' 0.25 s, a traction-control cut on the
		-- start opened it and it came back too slowly, a cycle that made the start chaotic (#220).
		clutchCloseTime = 0.12,
		selectorMaxSpeed = 1.0,
		upshiftHoldTime = 1.0,
		-- The ISR's shares fill the shared shape; the H box does not read them.
		shiftOpenShare = 0.2,
		shiftNeutralShare = 0.4,
		inputInertia = 0.02,
	},

	driveline = {
		-- Documented: 3.73:1.
		rearReduction = 3.73,
		-- No front drive.
		frontReduction = 3.73,
		-- EST.
		efficiency = 0.88,
		propshaftInertia = 0.05,
		frontShaftInertia = 0.02,
		-- The Laguna Seca's Torsen (documented): a helical diff locks in proportion to torque and has
		-- no preload. EST: the same ramp on power and coast.
		lsdPreload = 0,
		lsdPowerRamp = 0.40,
		lsdCoastRamp = 0.40,
	},

	brakes = {
		-- EST: enough to lock all four wheels on the R-compound (Brembo 355 mm front, 300 mm rear,
		-- documented).
		maxTorque = 9500,
		-- EST: the static 55 % plus the transfer under about 1.2 g on a 0.51 m CG.
		frontShare = 0.64,
		-- EST: a console lever on the rear discs.
		handbrakeTorque = 1800,
	},

	electronics = {
		-- EST, as the others' (01 §2.4); the Boss's own TC and ESC calibrations are not published.
		absReleaseSlip = 0.14,
		absReapplySlip = 0.07,
		absRate = 250,
		absReleaseTime = 0.04,
		absApplyTime = 0.08,
		absMinSpeed = 1.5,
		tcRate = 100,
		tcGain = 4.0,
		tcCutFactor = 2.5,
		tcRecoveryTime = 0.25,
		tcSpeedFloor = 3.0,
		escRate = 50,
		escMinSpeed = 4.0,
		-- EST: a nose-heavy car understeers more than the mid-engined two.
		characteristicSpeed = 28,
		escBrakeGain = 6000,
		escMaxBrakeTorque = 2500,
		escFullCutError = 0.6,
		escSideslipGain = 2.0,
	},

	aero = {
		airDensity = 1.2,
		-- Inferred, §1.7: Cd 0.35-0.358 on 2.26 m² (likely, the GT coupe).
		dragArea = 0.80,
		-- Inferred, §1.7: the Laguna Seca's "as much as 90 pounds at 140 mph" (documented), 400 N at
		-- 62.6 m/s. EST: 45 % of it on the front.
		liftArea = 0.17,
		frontBalance = 0.45,
		-- No active aero.
		alaDragFactor = 1,
		alaRearLiftFactor = 1,
		alaTime = 0.15,
		alaMinSpeed = math.huge,
		alaMinThrottle = 1,
		alaMaxLateral = 0,
	},

	steering = {
		-- Inferred, §1.8: about 31° of lock at 15.9:1 (documented) is about 2.8 turns.
		lockToLockTurns = 2.8,
		lowSpeedRatio = 15.9,
		highSpeedRatio = 15.9,
		lowRatioSpeed = 50 / 3.6,
		highRatioSpeed = 200 / 3.6,
		maxRoadWheelAngle = math.rad(31),
		ackermann = 0.5,
		rearGain = { { speed = 0, gain = 0 } },
		rearMaxOpposite = 0,
		rearMaxSame = 0,
		rearActuatorTime = 0.005,
	},

	-- Normal is the factory calibration with AdvanceTrac in full; Sport is AdvanceTrac's sport mode
	-- (documented: less intervention); TracKey is the track calibration (documented): launch
	-- control, the pit limiter (Switches) and the lopey idle, here with AdvanceTrac's sport
	-- thresholds as on a track day. All thresholds are EST; only their order is sourced.
	modes = {
		Normal = mode({
			upshiftRpm = { light = 2200, full = 7400 },
			downshiftRpm = { light = 1100, full = 3500 },
			brakeDownshiftRpm = 2800,
			holdOnLift = false,
			tcSlipRatio = 0.10,
			escOversteer = 0.06,
			escUndersteer = 0.08,
			escSideslip = math.rad(5),
		}),
		Sport = mode({
			upshiftRpm = { light = 3200, full = 7400 },
			downshiftRpm = { light = 1800, full = 4500 },
			brakeDownshiftRpm = 3800,
			holdOnLift = true,
			tcSlipRatio = 0.18,
			escOversteer = 0.25,
			escUndersteer = 0.12,
			escSideslip = math.rad(12),
		}),
		TracKey = mode({
			upshiftRpm = { light = 3500, full = 7400 },
			downshiftRpm = { light = 2200, full = 4500 },
			brakeDownshiftRpm = 4200,
			holdOnLift = true,
			tcSlipRatio = 0.18,
			escOversteer = 0.25,
			escUndersteer = 0.12,
			escSideslip = math.rad(12),
			-- EST: the "lopey" idle (documented) is higher and rougher; the audio reads the rpm.
			idleRpm = 1000,
		}),
	},
	modeOrder = { "Normal", "Sport", "TracKey" },

	-- TracKey's launch control (documented): stationary in first, the clutch (here the brake, which
	-- holds the automatic clutch open) and a floored throttle hold the rpm until release. Ford asks
	-- for nothing to be switched off. The slip is the tyres' peak; the 100 km/h end is the other
	-- cars' game rule.
	launch = {
		mode = "TracKey",
		slipRatio = 0.10,
		endSpeed = 100 / 3.6,
		autoUpshift = true,
		withEsc = true,
	},

	-- The shared arcade drift (Vehicle/Drift): game values, not car data, as the other cars' to
	-- start with.
	drift = {
		turnRate = 1.6,
		turnAccel = 36,
		alignRate = 3.0,
		scrub = 10,
		frontGrip = 0.8,
		rearGrip = 0.5,
		tcSlip = 0.3,
		frontShare = 0,
	},

	simulation = {
		maxSubstep = 0.001,
		solverIterations = 4,
		maxFrameTime = 1 / 15,
		loadFilterTime = 0.015,
		lowSpeedFade = 3.0,
		slipSpeedFloor = 1.0,
	},
})
