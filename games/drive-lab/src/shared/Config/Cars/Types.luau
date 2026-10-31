--!strict
--[[
	The shape of a car's data. Every vehicle module reads its numbers from a CarConfig, so a new
	car is a new file that calls `define`. SI units throughout (m, kg, N, N·m, rad, s); rpm only
	where the source data is in rpm. `define` checks the invariants the physics relies on and
	freezes the whole tree, so a module can never tune a car at run time.
]]
local GameFeel = require("../GameFeel")

-- One of the names in the car's `modeOrder`.
export type DrivingMode = string

export type TyreConfig = {
	-- Dynamic rolling radius under load, not the free radius.
	radius: number,
	-- Peak friction coefficients at the reference load, on dry asphalt.
	peakMuX: number,
	peakMuY: number,
	slipRatioAtPeak: number,
	slipAngleAtPeak: number,
	-- Force at a full slide as a share of the peak. Sets the Magic Formula C.
	slidingRatioX: number,
	slidingRatioY: number,
	-- Magic Formula E: closer to 1 holds the force near the peak for longer past it.
	curvatureX: number,
	curvatureY: number,
	referenceLoad: number,
	-- Peak force grows as load^loadSensitivity, so friction falls as load rises.
	loadSensitivity: number,
	relaxationLengthX: number,
	relaxationLengthY: number,
	-- Damping of the contact patch at walking pace, as a share of critical on the corner mass.
	carcassDampingRatio: number,
	-- Rolling resistance coefficient: constant part and part per m/s of speed.
	rollingResistance: number,
	rollingResistancePerSpeed: number,
}

export type AxleConfig = {
	track: number,
	tyre: TyreConfig,
	-- Wheel, tyre and brake disc about the axle.
	wheelInertia: number,
	unsprungMass: number,
	rideFrequency: number,
}

export type SuspensionConfig = {
	travel: number,
	-- Compression at the static ride height.
	staticCompression: number,
	bumpStopStart: number,
	-- Bump-stop rate at first contact, and the ceiling the progressive rate is held to.
	bumpStopRate: number,
	bumpStopMaxRate: number,
	bumpStopProgression: number,
	damperKneeSpeed: number,
	damperFastRatio: number,
	damperReboundRatio: number,
	-- Roll stiffness targets the anti-roll bars are sized from.
	rollGradient: number,
	frontRollShare: number,
}

export type TorquePoint = { rpm: number, torque: number }

export type EngineConfig = {
	torqueCurve: { TorquePoint },
	-- Closed-throttle friction and pumping torque at two speeds, linear between them.
	dragLow: TorquePoint,
	dragHigh: TorquePoint,
	inertia: number,
	idleRpm: number,
	limiterRpm: number,
	limiterHysteresis: number,
	-- Rev limit while the car is held on the brake with the clutch open (launch control).
	launchRpm: number,
}

export type GearboxConfig = {
	ratios: { number },
	reverseRatio: number,
	-- Reverse's top speed (m/s): the engine's torque fades to nothing over the last
	-- `reverseCutBand` below it, as a limiter cuts, and never brakes the car.
	reverseMaxSpeed: number,
	reverseCutBand: number,
	clutchTorque: number,
	-- Engine speed the automatic clutch slips at while the car gets moving: this at a closed
	-- throttle, the engine's launch speed at full throttle.
	clutchCreepRpm: number,
	-- Engine overspeed, as a share of that target, that takes the clutch from carrying the
	-- engine's torque to fully closed.
	clutchSlipBand: number,
	-- Seconds for the automatic clutch to close from open (it opens at once).
	clutchCloseTime: number,
	-- Ground speed below which the selector moves between reverse, neutral and first, and the
	-- brake holds the clutch open.
	selectorMaxSpeed: number,
	-- Seconds after an upshift begins during which the automatic does not shift down again,
	-- except while braking: its guard against hunting between two gears.
	upshiftHoldTime: number,
	-- Shares of a shift's time spent opening, in neutral and closing.
	shiftOpenShare: number,
	shiftNeutralShare: number,
	inputInertia: number,
}

export type DrivelineConfig = {
	-- Effective reductions after the gearbox to each axle.
	rearReduction: number,
	frontReduction: number,
	efficiency: number,
	propshaftInertia: number,
	frontShaftInertia: number,
	lsdPreload: number,
	lsdPowerRamp: number,
	lsdCoastRamp: number,
}

export type BrakesConfig = {
	maxTorque: number,
	frontShare: number,
	handbrakeTorque: number,
}

export type ElectronicsConfig = {
	absReleaseSlip: number,
	absReapplySlip: number,
	absRate: number,
	absReleaseTime: number,
	absApplyTime: number,
	absMinSpeed: number,
	tcRate: number,
	-- Share of torque removed per unit of slip ratio over the threshold, per update.
	tcGain: number,
	-- Above threshold × this, the torque is cut outright.
	tcCutFactor: number,
	tcRecoveryTime: number,
	-- Floor on the speed in the slip denominator, so TC lets a stopped car move.
	tcSpeedFloor: number,
	escRate: number,
	escMinSpeed: number,
	characteristicSpeed: number,
	escBrakeGain: number,
	escMaxBrakeTorque: number,
	-- Yaw-rate excess (rad/s) at which ESC removes all engine torque.
	escFullCutError: number,
	-- Yaw-rate error (rad/s) ESC counts per radian of body slip beyond the mode's limit.
	escSideslipGain: number,
}

export type AeroConfig = {
	airDensity: number,
	dragArea: number,
	liftArea: number,
	frontBalance: number,
	alaDragFactor: number,
	alaRearLiftFactor: number,
	alaTime: number,
	alaMinSpeed: number,
	alaMinThrottle: number,
	alaMaxLateral: number,
}

export type SpeedGain = { speed: number, gain: number }

export type SteeringConfig = {
	lockToLockTurns: number,
	lowSpeedRatio: number,
	highSpeedRatio: number,
	lowRatioSpeed: number,
	highRatioSpeed: number,
	maxRoadWheelAngle: number,
	ackermann: number,
	rearGain: { SpeedGain },
	rearMaxOpposite: number,
	rearMaxSame: number,
	rearActuatorTime: number,
}

export type ShiftPoints = { light: number, full: number }

export type ModeConfig = {
	upshiftTime: number,
	downshiftTime: number,
	upshiftRpm: ShiftPoints,
	downshiftRpm: ShiftPoints,
	-- Under full braking the automatic drops gears whenever the engine falls below this,
	-- scaled down with lighter braking, as the ISR keeps the engine in its band.
	brakeDownshiftRpm: number,
	-- Off the throttle the automatic keeps its gear, as the ISR does in its sporting modes,
	-- instead of shifting up as soon as the pedal lifts.
	holdOnLift: boolean,
	frontShareDrive: number,
	frontShareCoast: number,
	damperRatio: number,
	tcSlipRatio: number,
	escOversteer: number,
	escUndersteer: number,
	escSideslip: number,
	-- Calibrations a mode may set in place of the car's own (`electronics`, `driveline`), as a
	-- manettino position selects its ABS and E-Diff maps.
	absReleaseSlip: number?,
	absReapplySlip: number?,
	lsdPowerRamp: number?,
	lsdCoastRamp: number?,
}

export type Modes = { [DrivingMode]: ModeConfig }

-- Launch control (Vehicle/Launch). The rpm it holds is the engine's `launchRpm`.
export type LaunchConfig = {
	-- The drive mode it arms in; ESC must be switched off too.
	mode: DrivingMode,
	-- Slip ratio traction control holds the tyres at during a launch, even with TC off.
	slipRatio: number,
	-- Ground speed (m/s) past which the launch ends and the assists are the driver's again.
	endSpeed: number,
	-- Whether the automatic shifts up by itself during a launch; manual never does.
	autoUpshift: boolean,
}

-- The car's own numbers for the shared drift (Vehicle/Drift, Config/Drift).
export type DriftProfile = {
	-- Body slip (rad) at full lock toward the turn. The steering lock bounds it: past about the lock
	-- less the front tyres' peak slip, the front wheels cannot follow the car's path any more.
	maxAngle: number,
	-- Share of the rear tyres' grip at the target angle: lower is looser.
	holdShare: number,
	-- Traction control's slip threshold while drifting.
	tcSlip: number,
	-- Most of the gearbox's torque the coupling may send forward while drifting.
	frontShare: number,
}

-- When the slide assist (Vehicle/SlideAssist) takes the steering at one game-feel notch.
export type SlideAssistNotch = {
	-- Rear axle slip angle, as a share of the rear tyres' peak, past which a rear sliding more than
	-- the front starts the assist.
	rearSlipStart: number,
	-- Yaw rate (rad/s) off ESC's reference past which the assist starts.
	yawErrorStart: number,
}

-- The car's own numbers for the slide assist; each notch above Realistic has its entry.
export type SlideAssistProfile = {
	-- How much further past each start the assist reaches its full share.
	rearSlipBand: number,
	yawErrorBand: number,
	-- Steering (rad at the road wheels) taken off per rad/s of yaw rate, so a catch eases off as
	-- the rotation stops instead of whipping the car the other way.
	yawDamping: number,
	-- Seconds per full lock the wheel moves while the assist acts, and the share of it spent
	-- speeding up and slowing down: a driver's quick hands, not the filter's turn-in pace.
	steerTime: number,
	steerEaseShare: number,
	-- Seconds the assist takes to hand the steering back once the slide has gone.
	holdTime: number,
	-- Below this forward speed (m/s) there is no slide to catch.
	minSpeed: number,
	notches: { [string]: SlideAssistNotch },
}

export type SimulationConfig = {
	maxSubstep: number,
	solverIterations: number,
	maxFrameTime: number,
	loadFilterTime: number,
	-- Below this contact speed the patch is a damped spring rather than a slip curve.
	lowSpeedFade: number,
	slipSpeedFloor: number,
}

export type CarConfig = {
	name: string,
	mass: number,
	frontWeightShare: number,
	cgHeight: number,
	yawInertia: number,
	pitchInertia: number,
	rollInertia: number,
	wheelbase: number,
	front: AxleConfig,
	rear: AxleConfig,
	suspension: SuspensionConfig,
	engine: EngineConfig,
	gearbox: GearboxConfig,
	driveline: DrivelineConfig,
	brakes: BrakesConfig,
	electronics: ElectronicsConfig,
	aero: AeroConfig,
	steering: SteeringConfig,
	modes: Modes,
	-- The order the drive-mode control steps through the modes; a car starts in the first.
	modeOrder: { DrivingMode },
	-- A car without launch control never arms one.
	launch: LaunchConfig?,
	-- A car without a profile never drifts: its drift button stays the handbrake.
	drift: DriftProfile?,
	-- A car without a profile drives at every game-feel notch as at Realistic.
	slideAssist: SlideAssistProfile?,
	simulation: SimulationConfig,
}

local Types = {}

local function deepFreeze<T>(value: T): T
	if type(value) == "table" and not table.isfrozen(value) then
		for _, child in value :: { [unknown]: unknown } do
			deepFreeze(child)
		end
		table.freeze(value)
	end
	return value
end

local function checkTyre(tyre: TyreConfig, axle: string)
	assert(tyre.radius > 0, `{axle} tyre radius must be positive`)
	-- At 1 the curve never peaks, so the slip at peak cannot place it.
	assert(tyre.slidingRatioX > 0 and tyre.slidingRatioX < 1, `{axle} slidingRatioX must be in (0, 1)`)
	assert(tyre.slidingRatioY > 0 and tyre.slidingRatioY < 1, `{axle} slidingRatioY must be in (0, 1)`)
	assert(tyre.curvatureX < 1 and tyre.curvatureY < 1, `{axle} tyre curvature must be below 1`)
	assert(tyre.relaxationLengthX > 0 and tyre.relaxationLengthY > 0, `{axle} relaxation lengths`)
end

-- The drive-mode control steps through every mode the car has, each once.
local function checkModes(car: CarConfig)
	local listed: { [string]: boolean } = {}
	for _, name in car.modeOrder do
		assert(car.modes[name], `the mode order names "{name}", which the car has no mode for`)
		assert(not listed[name], `the mode order names "{name}" twice`)
		listed[name] = true
	end
	for name in car.modes do
		assert(listed[name], `the mode order leaves out the "{name}" mode`)
	end
	local launch = car.launch
	if launch then
		assert(
			car.modes[launch.mode],
			`launch control arms in "{launch.mode}", which the car has no mode for`
		)
	end
end

-- Every notch above Realistic has its values, and nothing else does.
local function checkSlideAssist(profile: SlideAssistProfile)
	assert(profile.rearSlipBand > 0 and profile.yawErrorBand > 0, "slide assist bands must be positive")
	assert(profile.yawDamping >= 0, "slide assist damping must not be negative")
	assert(profile.steerTime > 0 and profile.holdTime > 0, "slide assist times must be positive")
	assert(
		profile.steerEaseShare >= 0 and profile.steerEaseShare <= 0.5,
		"slide assist ease share must be in [0, 0.5]"
	)
	for _, notch in GameFeel.ORDER do
		local values = profile.notches[notch]
		if notch == "Realistic" then
			assert(values == nil, "the Realistic notch has no slide assist")
		else
			assert(values, `the slide assist has no values for the {notch} notch`)
			assert(
				values.rearSlipStart > 0 and values.yawErrorStart > 0,
				`{notch}: slide assist starts must be positive`
			)
		end
	end
	for name in profile.notches do
		assert(
			table.find(GameFeel.ORDER, name),
			`the slide assist names "{name}", which is no game-feel notch`
		)
	end
end

-- Validates a car and freezes it. Errors name the field, so a bad config fails at load time.
function Types.define(car: CarConfig): CarConfig
	assert(car.mass > 0, "mass must be positive")
	assert(car.frontWeightShare > 0 and car.frontWeightShare < 1, "frontWeightShare must be in (0, 1)")
	checkTyre(car.front.tyre, "front")
	checkTyre(car.rear.tyre, "rear")
	local ratios = car.gearbox.ratios
	assert(#ratios >= 1, "gearbox needs at least one forward ratio")
	for index = 2, #ratios do
		assert(ratios[index] < ratios[index - 1], "gear ratios must fall from first to top")
	end
	local curve = car.engine.torqueCurve
	for index = 2, #curve do
		assert(curve[index].rpm > curve[index - 1].rpm, "torque curve rpm must rise")
	end
	local suspension = car.suspension
	assert(
		suspension.staticCompression > 0 and suspension.staticCompression < suspension.bumpStopStart,
		"static compression must sit between full extension and the bump stop"
	)
	assert(suspension.bumpStopStart < suspension.travel, "bump stop must start inside the travel")
	assert(
		car.gearbox.shiftOpenShare + car.gearbox.shiftNeutralShare < 1,
		"shift shares leave no time to close"
	)
	assert(
		car.gearbox.reverseCutBand > 0 and car.gearbox.reverseCutBand < car.gearbox.reverseMaxSpeed,
		"the reverse cut must fit between a standstill and reverse's top speed"
	)
	local launch = car.launch
	if launch then
		assert(launch.slipRatio > 0 and launch.endSpeed > 0, "launch control needs a slip and an end speed")
	end
	checkModes(car)
	local drift = car.drift
	if drift then
		assert(drift.maxAngle > 0, "a drift needs a maximum angle")
		assert(drift.holdShare > 0 and drift.holdShare <= 1, "a drift's hold share must be in (0, 1]")
		assert(drift.frontShare >= 0 and drift.frontShare <= 1, "a drift's front share must be in [0, 1]")
	end
	local slideAssist = car.slideAssist
	if slideAssist then
		checkSlideAssist(slideAssist)
	end
	return deepFreeze(car)
end

return table.freeze(Types)
