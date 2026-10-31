--!strict
--[[
	Lamborghini Aventador SVJ (LP 770-4 coupé). Every number comes from
	research_notes/Drive lab/02_aventador_svj_data.md; the tag after it is that file's status
	(OEM, OEM-S = carried over from the Aventador S, DER = derived, EST = estimated, PRESS) and
	its table row or section. EST values are starting points for calibration, not data, and stay
	marked as such. Tyre grip, aero and CG/inertia are the least certain inputs (02 §2.15).
]]
local Types = require("../Types")

return Types.define({
	name = "Lamborghini Aventador SVJ",
	-- 1,770 kg measured kerb with fluids + 75 kg driver. DER/EST, 02 M7.
	mass = 1845,
	-- OEM, 02 M2 (43.4 % with the driver, 02 §2.2).
	frontWeightShare = 0.43,
	-- EST, lumped-mass model, 02 §2.3. Whole-vehicle values, wheels included.
	cgHeight = 0.444,
	yawInertia = 2720,
	pitchInertia = 2307,
	rollInertia = 616,
	-- OEM, 02 D5.
	wheelbase = 2.700,

	front = {
		-- OEM-S, 02 D6.
		track = 1.720,
		-- EST, 02 I7 and §2.3.
		wheelInertia = 1.5,
		unsprungMass = 48,
		-- EST: 02 §2.8 lists 1.7 Hz (Strada) and 1.9 Hz (Corsa) sets, but springs do not change
		-- with the drive mode on the real car (only the magnetorheological dampers do), so one
		-- set between them. Damping per mode is in `modes`.
		rideFrequency = 1.8,
		tyre = {
			-- 255/30 ZR20: DER/EST dynamic radius, 02 W9.
			radius = 0.322,
			-- EST. No tyre data is published (02 §2.6). Longitudinal peak from 100-0 km/h in
			-- 30 m (1.31 g mean, 02 P7 and §2.15: "a tyre peak of about 1.35-1.45 with ABS");
			-- lateral peak from the 1.10 g working skidpad value (02 P10, itself EST).
			peakMuX = 1.40,
			peakMuY = 1.22,
			-- EST, 01 §2.1 typical ranges for a performance road tyre.
			slipRatioAtPeak = 0.10,
			slipAngleAtPeak = math.rad(6.5),
			slidingRatioX = 0.80,
			slidingRatioY = 0.82,
			curvatureX = -0.5,
			curvatureY = -0.5,
			-- About the static corner load, so peakMu applies at rest.
			referenceLoad = 3900,
			-- EST, 01 §2.1: force grows as load^0.7-0.9.
			loadSensitivity = 0.85,
			-- EST, 01 §2.1: 0.12-0.45 m, about the wheel radius laterally.
			relaxationLengthX = 0.15,
			relaxationLengthY = 0.30,
			carcassDampingRatio = 0.5,
			-- DER from the EPA 4,250 lb coast-down (02 §2.10): F0 = 237 N and F1 = 8.14 N per m/s
			-- on 1,928 kg. Includes the driveline drag behind the gearbox, which a coast-down in
			-- neutral cannot separate.
			rollingResistance = 0.0125,
			rollingResistancePerSpeed = 4.3e-4,
		},
	},

	rear = {
		-- OEM-S, 02 D7.
		track = 1.680,
		wheelInertia = 2.2,
		unsprungMass = 55,
		rideFrequency = 2.0,
		tyre = {
			-- 355/25 ZR21: DER, consistent with the EPA N/V ratio, 02 W9.
			radius = 0.346,
			peakMuX = 1.40,
			peakMuY = 1.22,
			slipRatioAtPeak = 0.10,
			slipAngleAtPeak = math.rad(6.5),
			slidingRatioX = 0.80,
			slidingRatioY = 0.82,
			curvatureX = -0.5,
			curvatureY = -0.5,
			referenceLoad = 5150,
			loadSensitivity = 0.85,
			relaxationLengthX = 0.15,
			relaxationLengthY = 0.30,
			carcassDampingRatio = 0.5,
			rollingResistance = 0.0125,
			rollingResistancePerSpeed = 4.3e-4,
		},
	},

	suspension = {
		-- EST: 115 mm ground clearance (02 D8) leaves room for about 50 mm of droop and 40 mm
		-- of bump before the stops; no travel figure is published.
		travel = 0.110,
		staticCompression = 0.050,
		-- EST, 01 §2.2: 10-30 mm of usable bump rubber.
		bumpStopStart = 0.090,
		bumpStopRate = 30000,
		-- Capped so the stop stays stable when the engine holds its force for a 30 FPS frame
		-- (01 §5.2 point 5): ω·dt about 1 on a 470 kg corner.
		bumpStopMaxRate = 400000,
		bumpStopProgression = 2.0e7,
		-- EST, 01 §2.2: knee 0.05-0.1 m/s; rebound stiffer than bump.
		damperKneeSpeed = 0.08,
		damperFastRatio = 0.4,
		damperReboundRatio = 1.5,
		-- EST, 02 §2.8: roll gradient 0.8-1.0 deg/g, front roll share 48-52 %.
		rollGradient = math.rad(0.9),
		frontRollShare = 0.50,
	},

	engine = {
		-- EST shape through two OEM anchors (720 Nm at 6,750; 566 kW at 8,500), 02 §2.4.
		-- Below 4,000 rpm the shape has no source (low confidence).
		torqueCurve = {
			{ rpm = 1000, torque = 400 },
			{ rpm = 1500, torque = 450 },
			{ rpm = 2000, torque = 500 },
			{ rpm = 2500, torque = 545 },
			{ rpm = 3000, torque = 580 },
			{ rpm = 3500, torque = 610 },
			{ rpm = 4000, torque = 635 },
			{ rpm = 4500, torque = 655 },
			{ rpm = 5000, torque = 675 },
			{ rpm = 5500, torque = 693 },
			{ rpm = 6000, torque = 708 },
			{ rpm = 6500, torque = 717 },
			{ rpm = 6750, torque = 720 },
			{ rpm = 7000, torque = 719 },
			{ rpm = 7500, torque = 700 },
			{ rpm = 8000, torque = 665 },
			{ rpm = 8250, torque = 652 },
			{ rpm = 8500, torque = 636 },
			{ rpm = 8700, torque = 612 },
		},
		-- EST, 02 §2.4: 2 bar of friction and pumping near idle rising to 4 bar at 8,500 rpm,
		-- 51.7 Nm per bar on 6,498 cm³.
		dragLow = { rpm = 950, torque = 103 },
		dragHigh = { rpm = 8500, torque = 207 },
		-- EST, 02 I6: 0.10-0.22 kg·m², lightened flywheel.
		inertia = 0.15,
		-- EST, 02 E10 (warm idle).
		idleRpm = 950,
		-- PRESS, 02 E9 (fuel cut).
		limiterRpm = 8700,
		limiterHysteresis = 150,
		-- Anecdotal: no Lamborghini figure is published; one owner reports about 5,200 rpm held on
		-- an LP700-4's launch control (research note 2026-10-29, section 1). Tunable.
		launchRpm = 5000,
	},

	gearbox = {
		-- OEM-S, 02 T2/T3.
		ratios = { 3.909, 2.438, 1.810, 1.458, 1.185, 0.967, 0.844 },
		reverseRatio = 2.929,
		-- Not a car figure: no reverse limit is documented for the Aventador (research note
		-- 2026-10-29, §3). 40 km/h is the owner's choice (#70); the cut over the last 4 km/h is
		-- the systems agent's, so the car settles on the limit without a step.
		reverseMaxSpeed = 40 / 3.6,
		reverseCutBand = 4 / 3.6,
		-- EST: dry twin-plate, 235 mm (02 T7); capacity about 1.4 × peak engine torque.
		clutchTorque = 1000,
		clutchCreepRpm = 1500,
		clutchSlipBand = 0.2,
		clutchCloseTime = 0.15,
		selectorMaxSpeed = 1.0,
		-- Not a car figure; no ISR source. Production gearbox controllers stop hunting with a
		-- timed hold after a shift (e.g. US4041810, US6123644). In Sport at full throttle the rear
		-- slip read through the gearbox drops after the 1-2 upshift and took the input under the
		-- downshift point for up to 0.34 s (#35); 1 s is three times that and ten Sport upshifts.
		upshiftHoldTime = 1.0,
		-- EST: shift time split into cut-and-open, neutral and re-engagement (01 §2.3).
		shiftOpenShare = 0.2,
		shiftNeutralShare = 0.4,
		-- EST: gearbox input shaft and gears, reflected through the selected ratio.
		inputInertia = 0.02,
	},

	driveline = {
		-- DER, 02 T5 and §2.5: the published 2.867 final drive cannot match the EPA N/V ratio
		-- or the front axle ratio; 3.52 does.
		rearReduction = 3.52,
		-- OEM-S, 02 T4.
		frontReduction = 3.273,
		-- EST: no figure published; checked against the 350 km/h top speed.
		efficiency = 0.88,
		propshaftInertia = 0.05,
		frontShaftInertia = 0.02,
		-- EST, 02 §2.5: "start at about 25 % drive / 45 % coast"; preload from 01 §2.3 range.
		lsdPreload = 100,
		lsdPowerRamp = 0.25,
		lsdCoastRamp = 0.45,
	},

	brakes = {
		-- EST: enough to lock all four wheels at 1.4 μ; not published.
		maxTorque = 12000,
		-- EST, 02 B5: 62 % front working value (ideal at 1.31 g is about 65 %).
		frontShare = 0.62,
		-- EST: per rear wheel, about enough to lock a rear at its static load.
		handbrakeTorque = 2500,
	},

	electronics = {
		-- EST, 01 §2.4 (AC example: ABS slip 0.12 at 250 Hz, TC 100 Hz).
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
		-- EST: mild understeer for the ESC reference model, about 1.3 deg/g.
		characteristicSpeed = 35,
		escBrakeGain = 6000,
		escMaxBrakeTorque = 2500,
		escFullCutError = 0.6,
		escSideslipGain = 2.0,
	},

	aero = {
		-- EST: 20 °C at sea level.
		airDensity = 1.2,
		-- DER, 02 A6/A7 and §2.10: EPA coast-down gives an upper bound of 0.68-0.74 m²
		-- (FichaCompleta 0.686).
		dragArea = 0.69,
		-- PRESS, unverified, 02 A8: about 350 kg at 300 km/h.
		liftArea = 0.82,
		-- EST, 02 §2.10: split not published, 40/60 to start.
		frontBalance = 0.40,
		-- EST, 02 §2.10: ALA open cuts drag 5-8 % and rear downforce about 30 %.
		alaDragFactor = 0.935,
		alaRearLiftFactor = 0.70,
		-- OEM, 02 A2: flaps move in under 500 ms; a 0.15 s lag reaches 96 % by then.
		alaTime = 0.15,
		-- PRESS, 02 A5: aero-vectoring works above 71 km/h; used here for the whole ALA.
		alaMinSpeed = 71 / 3.6,
		alaMinThrottle = 0.8,
		alaMaxLateral = 3.0,
	},

	steering = {
		-- OEM-S/PRESS, 02 S6/S7: 2.1-2.4 turns, 10:1 to 18:1 variable.
		lockToLockTurns = 2.3,
		lowSpeedRatio = 10,
		highSpeedRatio = 18,
		-- EST: the Dynamic Steering curve is not published.
		lowRatioSpeed = 50 / 3.6,
		highRatioSpeed = 200 / 3.6,
		-- DER from the 11.5 m turning circle (02 S9) with 3° of opposite rear steer, taken as
		-- kerb to kerb. At 10:1 the full 414° of wheel would ask for 41°, so at low speed the
		-- rack lock is reached before the steering wheel's.
		maxRoadWheelAngle = math.rad(30),
		-- EST: share of ideal Ackermann.
		ackermann = 0.5,
		-- EST gain curve through the PRESS endpoints, 02 S11/S12: up to 3.0° opposite at low
		-- speed, up to 1.5° in phase at speed, switching near 125-135 km/h.
		rearGain = {
			{ speed = 0, gain = -0.10 },
			{ speed = 60 / 3.6, gain = -0.10 },
			{ speed = 130 / 3.6, gain = 0 },
			{ speed = 180 / 3.6, gain = 0.15 },
			{ speed = 250 / 3.6, gain = 0.25 },
		},
		rearMaxOpposite = math.rad(3.0),
		rearMaxSame = math.rad(1.5),
		-- OEM-S, 02 S10: actuators react in 5 ms.
		rearActuatorTime = 0.005,
	},

	-- 02 §2.12. Shift times are EST from 02 §2.5 (only "up to 50 ms" in Corsa is OEM-S); AWD
	-- shares are OEM-S/PRESS (02 T10/T11); damping is EST from 02 §2.8 (0.3 of critical in
	-- Strada, 0.6-0.7 in Corsa), raised in Strada and Sport after the owner found the body's
	-- motion a little much (2026-10-27). Electronics thresholds are EST; their ordering is sourced
	-- (issue #21, 2026-10-28): Strada intervenes most; Sport is the mode that slides, oversteer and
	-- drifting made easy (Lamborghini, Aventador S release) with traction control slacker than
	-- Corsa's (Car and Driver, SVJ); Corsa trims less than Strada but keeps the car on its line, with
	-- narrow drift angles (Auto Bild, SVJ).
	modes = {
		Strada = {
			upshiftTime = 0.225,
			downshiftTime = 0.25,
			-- Full throttle holds each gear past the 8500 rpm redline, short of the limiter, as an
			-- automatic does on kickdown.
			upshiftRpm = { light = 2500, full = 8600 },
			downshiftRpm = { light = 1200, full = 3500 },
			brakeDownshiftRpm = 2800,
			holdOnLift = false,
			frontShareDrive = 0.40,
			frontShareCoast = 0.40,
			damperRatio = 0.40,
			tcSlipRatio = 0.08,
			escOversteer = 0.05,
			escUndersteer = 0.08,
			escSideslip = math.rad(4),
		},
		Sport = {
			upshiftTime = 0.10,
			downshiftTime = 0.12,
			upshiftRpm = { light = 3500, full = 8600 },
			downshiftRpm = { light = 2000, full = 5000 },
			brakeDownshiftRpm = 3800,
			holdOnLift = true,
			-- "Up to 93 % rear" (PRESS, 02 T11), and less forward on lift-off.
			frontShareDrive = 0.07,
			frontShareCoast = 0.0,
			damperRatio = 0.50,
			tcSlipRatio = 0.18,
			escOversteer = 0.25,
			escUndersteer = 0.10,
			escSideslip = math.rad(12),
		},
		Corsa = {
			upshiftTime = 0.055,
			downshiftTime = 0.07,
			upshiftRpm = { light = 4500, full = 8650 },
			downshiftRpm = { light = 3000, full = 5000 },
			brakeDownshiftRpm = 4500,
			holdOnLift = true,
			frontShareDrive = 0.20,
			frontShareCoast = 0.20,
			damperRatio = 0.65,
			tcSlipRatio = 0.15,
			escOversteer = 0.15,
			escUndersteer = 0.15,
			escSideslip = math.rad(8),
		},
	},
	modeOrder = { "Strada", "Sport", "Corsa" },

	-- Launch control (research note 2026-10-29, section 1, the LP700-4's procedure; nothing
	-- SVJ-specific was found). Corsa with ESC off, as documented. The slip is the tyres' own peak
	-- (slipRatioAtPeak, front and rear). The 100 km/h end and the automatic's upshifts during a
	-- launch are our choices (the coordinator's, 2026-10-29): the real Corsa is a manual mode and
	-- whether it shifts by itself in a launch is undocumented.
	launch = {
		mode = "Corsa",
		slipRatio = 0.10,
		endSpeed = 100 / 3.6,
		autoUpshift = true,
	},

	-- The shared arcade drift (Vehicle/Drift): game values, not car data. In Sport the coupling
	-- already sends 7 % forward; drifting caps it at 10 %.
	drift = {
		turnRate = 1.6,
		turnAccel = 36,
		alignRate = 3.0,
		scrub = 10,
		frontGrip = 0.8,
		rearGrip = 0.5,
		tcSlip = 0.3,
		frontShare = 0.10,
	},

	simulation = {
		maxSubstep = 0.001,
		solverIterations = 4,
		maxFrameTime = 1 / 15,
		-- 01 §5.3 point 7: a 10-20 ms low-pass on tyre load.
		loadFilterTime = 0.015,
		lowSpeedFade = 3.0,
		slipSpeedFloor = 1.0,
	},
})
