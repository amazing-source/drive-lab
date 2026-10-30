--!strict
--[[
	Ferrari 458 Challenge Evo, the unbadged Dream Racing car. Every number comes from
	docs/research/12_dr458_challenge_evo.md, section 1; the tag after it is that note's confidence
	(documented, likely, inferred, unknown), or EST where the value is ours, a starting point for
	calibration and not data. Ferrari published few Challenge figures: the gear ratios are the road
	458's, the downforce, the springs and the tyre curves are unknown, and every one of them is a
	tunable.
]]
local Types = require("../Types")

-- The manettino changes intervention only (12 §1.9: traction control, and the ABS and E-Diff
-- calibrations, never power), so its positions share everything else.
local function position(intervention: {
	tcSlipRatio: number,
	absReleaseSlip: number?,
	absReapplySlip: number?,
	lsdPowerRamp: number?,
	lsdCoastRamp: number?,
}): Types.ModeConfig
	return {
		-- EST: no Challenge shift time is published; the F430 Challenge's 60 ms is context only
		-- (12 §1.2).
		upshiftTime = 0.06,
		downshiftTime = 0.08,
		-- A game automatic: the real car is shifted on its paddles. Full throttle holds each gear
		-- past the 9,000 rpm redline, short of the limiter.
		upshiftRpm = { light = 4000, full = 9100 },
		downshiftRpm = { light = 2500, full = 5500 },
		brakeDownshiftRpm = 5000,
		holdOnLift = true,
		-- Rear drive: the coupling sends nothing forward.
		frontShareDrive = 0,
		frontShareCoast = 0,
		-- EST: "single-rate alloy dampers" (12 §1.8, documented), so one ratio in every position.
		damperRatio = 0.6,
		tcSlipRatio = intervention.tcSlipRatio,
		-- The car has no stability control (12 §1.9 names F1-Trac, ABS/EBD and the E-Diff only):
		-- ESC never runs (Assists), so these never act.
		escOversteer = 0.15,
		escUndersteer = 0.15,
		escSideslip = math.rad(8),
		absReleaseSlip = intervention.absReleaseSlip,
		absReapplySlip = intervention.absReapplySlip,
		lsdPowerRamp = intervention.lsdPowerRamp,
		lsdCoastRamp = intervention.lsdCoastRamp,
	}
end

return Types.define({
	name = "Ferrari 458 Challenge Evo",
	-- Documented, 12 §1.3: the race minimum, with the driver in racing kit, without fuel.
	mass = 1383,
	-- Likely, 12 §1.3.
	frontWeightShare = 0.42,
	-- EST: not published (12 gaps). The SVJ's lumped-mass inertias scaled by mass and body size
	-- (road 458 4,527 x 1,937 x 1,213 mm against the SVJ's 4,943 x 2,098 x 1,136 mm).
	cgHeight = 0.42,
	yawInertia = 1714,
	pitchInertia = 1474,
	rollInertia = 421,
	-- Measured on the 3D model's wheel centres (3D lead, 2026-10-30), not a published figure.
	wheelbase = 2.650,

	front = {
		-- Measured on the 3D model: wheel centres 0.8325 m either side.
		track = 1.665,
		-- EST: 19 in forged centre-lock rim and slick.
		wheelInertia = 1.2,
		unsprungMass = 40,
		-- EST: "stiffer springs", and stiffer front springs on the Evo (12 §1.8, documented);
		-- no rate is published.
		rideFrequency = 2.6,
		tyre = {
			-- Likely, 12 §1.5: 255/650 R19, 650 mm overall.
			radius = 0.325,
			-- EST: slicks, no curves published (12 §1.5). The peaks are set so the car holds
			-- about 1.5 g at skidpad speed, below the documented "up to 1.6G" (12 §1.10).
			peakMuX = 1.70,
			peakMuY = 1.73,
			slipRatioAtPeak = 0.08,
			slipAngleAtPeak = math.rad(5.5),
			slidingRatioX = 0.75,
			slidingRatioY = 0.78,
			curvatureX = -0.5,
			curvatureY = -0.5,
			-- About the static corner load, so peakMu applies at rest.
			referenceLoad = 2850,
			loadSensitivity = 0.85,
			relaxationLengthX = 0.12,
			relaxationLengthY = 0.25,
			carcassDampingRatio = 0.5,
			rollingResistance = 0.012,
			rollingResistancePerSpeed = 4.3e-4,
		},
	},

	rear = {
		-- Measured on the 3D model: wheel centres 0.7984 m either side.
		track = 1.5968,
		wheelInertia = 1.6,
		unsprungMass = 46,
		rideFrequency = 2.8,
		tyre = {
			-- Likely, 12 §1.5: 305/690 R19, 690 mm overall.
			radius = 0.345,
			peakMuX = 1.70,
			peakMuY = 1.73,
			slipRatioAtPeak = 0.08,
			slipAngleAtPeak = math.rad(5.5),
			slidingRatioX = 0.75,
			slidingRatioY = 0.78,
			curvatureX = -0.5,
			curvatureY = -0.5,
			referenceLoad = 3935,
			loadSensitivity = 0.85,
			relaxationLengthX = 0.12,
			relaxationLengthY = 0.25,
			carcassDampingRatio = 0.5,
			rollingResistance = 0.012,
			rollingResistancePerSpeed = 4.3e-4,
		},
	},

	suspension = {
		-- EST: the race ride heights (front 86 mm, rear 118 mm, 12 §1.4) leave less travel than
		-- the SVJ's.
		travel = 0.080,
		staticCompression = 0.035,
		bumpStopStart = 0.065,
		bumpStopRate = 30000,
		-- Capped as the SVJ's is (ω·dt about 1 at 30 FPS), on a 290 kg front corner.
		bumpStopMaxRate = 260000,
		bumpStopProgression = 2.0e7,
		damperKneeSpeed = 0.08,
		damperFastRatio = 0.4,
		damperReboundRatio = 1.5,
		-- EST: a race car's roll stiffness; the rear bar is the only part that may be removed
		-- (12 §1.8).
		rollGradient = math.rad(0.5),
		frontRollShare = 0.50,
	},

	engine = {
		-- Three anchors (12 §1.1): at least 432 Nm from 3,250 rpm (likely), 540 Nm at 6,000
		-- (documented) and about 445 Nm at 9,000, from 570 CV there (inferred). The shape between
		-- and below them is EST.
		torqueCurve = {
			{ rpm = 1000, torque = 300 },
			{ rpm = 1500, torque = 340 },
			{ rpm = 2000, torque = 380 },
			{ rpm = 2500, torque = 410 },
			{ rpm = 3000, torque = 428 },
			{ rpm = 3250, torque = 435 },
			{ rpm = 3500, torque = 450 },
			{ rpm = 4000, torque = 480 },
			{ rpm = 4500, torque = 505 },
			{ rpm = 5000, torque = 525 },
			{ rpm = 5500, torque = 536 },
			{ rpm = 6000, torque = 540 },
			{ rpm = 6500, torque = 538 },
			{ rpm = 7000, torque = 530 },
			{ rpm = 7500, torque = 515 },
			{ rpm = 8000, torque = 495 },
			{ rpm = 8500, torque = 470 },
			{ rpm = 9000, torque = 445 },
			{ rpm = 9200, torque = 430 },
		},
		-- EST, as the SVJ's: 2 bar of friction and pumping near idle rising to 4 bar at the top,
		-- 35.8 Nm per bar on 4,499 cm³.
		dragLow = { rpm = 1000, torque = 72 },
		dragHigh = { rpm = 9000, torque = 143 },
		inertia = 0.12,
		-- Unknown (12 §1.1): no idle or limiter figure. The 9,200 rpm is the old ledger's,
		-- user-supplied and unverified; both are tunables.
		idleRpm = 1000,
		limiterRpm = 9200,
		limiterHysteresis = 150,
		-- The rpm the engine holds at a standstill with the brake holding the clutch open. Not a
		-- launch control figure: the car has none (below). EST.
		launchRpm = 5000,
	},

	gearbox = {
		-- The road 458's ratios (12 §1.2, likely for the road car): Ferrari changed the Challenge's
		-- for more torque at lower revs, and its numbers are not published. Not factory Challenge
		-- values.
		ratios = { 3.08, 2.18, 1.63, 1.29, 1.03, 0.84, 0.69 },
		-- EST: not published.
		reverseRatio = 2.80,
		-- As the SVJ's: 40 km/h is the owner's reverse limit (#70), not a car figure.
		reverseMaxSpeed = 40 / 3.6,
		reverseCutBand = 4 / 3.6,
		-- EST: the dual-clutch "F1" gearbox (12 §1.2), about 1.5 x peak engine torque.
		clutchTorque = 800,
		clutchCreepRpm = 1500,
		clutchSlipBand = 0.2,
		clutchCloseTime = 0.12,
		selectorMaxSpeed = 1.0,
		-- As the SVJ's: a timed hold after a shift stops the automatic hunting (#35).
		upshiftHoldTime = 1.0,
		-- EST: a dual clutch hands over with almost no time in neutral.
		shiftOpenShare = 0.2,
		shiftNeutralShare = 0.2,
		inputInertia = 0.02,
	},

	driveline = {
		-- The road 458's 5.14 final drive (12 §1.2, likely for the road car, not the Challenge).
		rearReduction = 5.14,
		-- No front drive: the front shaft only turns with the free front wheels.
		frontReduction = 5.14,
		-- EST: rear drive, no transfer case.
		efficiency = 0.90,
		propshaftInertia = 0.04,
		frontShaftInertia = 0.02,
		-- EST: the E-Diff (12 §1.9, documented) as a locking differential. Position 1's maps;
		-- OFF and 2 set their own (`modes`).
		lsdPreload = 80,
		lsdPowerRamp = 0.30,
		lsdCoastRamp = 0.40,
	},

	brakes = {
		-- EST: carbon-ceramic discs, 398 mm front and 380 mm rear (12 §1.6, documented); enough
		-- torque to lock all four wheels on slicks at speed.
		maxTorque = 10000,
		-- EST: the static 42 % plus the transfer under about 1.6 g on a 0.42 m CG.
		frontShare = 0.62,
		handbrakeTorque = 1800,
	},

	electronics = {
		-- EST, as the SVJ's (01 §2.4), with the slips nearer a slick's peak. These are the
		-- "high performance for dry surfaces" ABS (12 §1.9, likely); position 2 sets the
		-- "low grip" one.
		absReleaseSlip = 0.12,
		absReapplySlip = 0.06,
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
		characteristicSpeed = 35,
		escBrakeGain = 6000,
		escMaxBrakeTorque = 2500,
		escFullCutError = 0.6,
		escSideslipGain = 2.0,
	},

	aero = {
		airDensity = 1.2,
		-- EST: no drag or downforce figure exists (12 §1.4). The road 458's shape with the Evo's
		-- GT-style wing and splitter: about 300 kg of downforce at 250 km/h, 38 % on the front.
		dragArea = 0.85,
		liftArea = 1.0,
		frontBalance = 0.38,
		-- The Evo's wing is "mounted solidly to the chassis" (12 §1.4, likely): no active aero.
		alaDragFactor = 1,
		alaRearLiftFactor = 1,
		alaTime = 0.15,
		alaMinSpeed = math.huge,
		alaMinThrottle = 1,
		alaMaxLateral = 0,
	},

	steering = {
		-- The road 458's 2.0 turns and 11.5:1 (12 §1.7, likely for the road car), one ratio at
		-- every speed.
		lockToLockTurns = 2.0,
		lowSpeedRatio = 11.5,
		highSpeedRatio = 11.5,
		lowRatioSpeed = 50 / 3.6,
		highRatioSpeed = 200 / 3.6,
		-- Inferred, 12 §1.7: a full turn either way over 11.5:1, about 31.3°.
		maxRoadWheelAngle = math.rad(360 / 11.5),
		ackermann = 0.5,
		-- No rear steering.
		rearGain = { { speed = 0, gain = 0 } },
		rearMaxOpposite = 0,
		rearMaxSame = 0,
		rearActuatorTime = 0.005,
	},

	-- The manettino (12 §1.9, documented): OFF switches traction control off (Assists); 1 and 2
	-- intervene progressively more, 2 being for new or worn tyres and rain (likely). The
	-- calibrations per position are EST.
	modes = {
		["1"] = position({ tcSlipRatio = 0.12 }),
		["2"] = position({
			tcSlipRatio = 0.08,
			absReleaseSlip = 0.10,
			absReapplySlip = 0.05,
			lsdPowerRamp = 0.25,
			lsdCoastRamp = 0.50,
		}),
		OFF = position({ tcSlipRatio = 0.12, lsdPowerRamp = 0.35, lsdCoastRamp = 0.35 }),
	},
	-- One key steps the knob 1, 2, OFF and back to 1, so a drive starts in 1, not with traction
	-- control off. The real rotary reads OFF, 1, 2.
	modeOrder = { "1", "2", "OFF" },

	-- No launch control: none is documented for the Challenge, whose races start rolling.
	launch = nil,

	simulation = {
		maxSubstep = 0.001,
		solverIterations = 4,
		maxFrameTime = 1 / 15,
		loadFilterTime = 0.015,
		lowSpeedFade = 3.0,
		slipSpeedFloor = 1.0,
	},
})
