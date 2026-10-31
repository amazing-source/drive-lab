--!strict
--[[
	An offline candidate of the drift plan's balancing law (docs/research/13_drifting.md §5), to
	find its starting values per car. Not the implementation: the law lives in this tool only, and
	it reaches the car through inputs the model already has (the rear wheels' surface grip, the
	steering, the assist flags).

	While the drift button is held above `minKmh` with the steering past `steerGate`, an engagement
	rises over `riseTime` and falls over `fallTime` once released. Engaged, the player's steering
	picks a target body slip: `minAngle` with the steering centred, up to the car's `maxAngle` at
	full lock toward the turn, none when steered the other way or once the button is released. The
	front wheels point along the front axle's own path plus a slip toward the turn of `frontSlip`
	of their peak at the target, less by `steerGain` per 10 degrees over it and per 100 degrees a
	second of growth (the geometry of InputFilter.steerBounds), and the rear tyres' grip share
	follows the target too: `holdShare` at the target, lower below it and higher above
	it by `angleGain` per unit of relative error, damped by `rateGain` per degree a second, kept
	between `floorShare` and 1. Past the target the engine's torque fades out over `torqueBand`
	degrees, as a side-slip control reads the angle. ESC stands aside, and the car runs its Drift
	mode: TC relaxed to `tcSlip`, and on all-wheel drive at most `frontShare` of the torque forward.

	The run: straight at a speed in a fixed gear; at 1 s the steering goes to `steer` over 0.3 s and
	the button goes down, throttle `throttle`; at 4 s both are released and the throttle holds the
	speed.

	    lune run games/drive-lab/tools/drift_candidate.luau [fps]
]]
local DR458 = require("../src/shared/Config/Cars/DR458/Physics")
local DriveSim = require("./DriveSim")
local Geometry = require("../src/shared/Vehicle/Geometry")
local Model = require("../src/shared/Vehicle/Model")
local SVJ = require("../src/shared/Config/Cars/SVJ/Physics")
local SmokeConfig = require("../src/shared/Config/TyreSmoke")
local Steering = require("../src/shared/Vehicle/Steering")
local TyreSmoke = require("../src/shared/Rules/TyreSmoke")
local Types = require("../src/shared/Config/Cars/Types")
local process = require("@lune/process")

local DT = 1 / (tonumber(process.args[1]) or 60)
local KMH = 1 / 3.6
local PRESS, RELEASE, STOP = 1, 4, 7

export type Profile = {
	maxAngle: number,
	holdShare: number,
	floorShare: number,
	tcSlip: number,
	frontShare: number,
}

-- The scripted player: speed and gear going in, steering and throttle while the button is held,
-- and whether TC runs at all (the DR458's OFF switches it off).
type Player = { kmh: number, gear: number, steer: number, throttle: number, tc: boolean }

type Shared = {
	minKmh: number,
	steerGate: number,
	riseTime: number,
	fallTime: number,
	minAngle: number,
	angleGain: number,
	rateGain: number,
	torqueBand: number,
	frontSlip: number,
	steerGain: number,
}

type Outcome = {
	entry: number,
	held: number,
	peak: number,
	turned: number,
	lossPerSecond: number,
	snap: number,
	settle: number,
	combined: number,
	slide: number,
	smoke: number,
}

local SHARED: Shared = {
	minKmh = 30,
	steerGate = 0.25,
	riseTime = 0.25,
	fallTime = 0.5,
	minAngle = 15,
	angleGain = 0.8,
	rateGain = 0.01,
	torqueBand = 10,
	frontSlip = 0.6,
	steerGain = 1,
}

local function bodySlip(sim: DriveSim.Sim): number
	local forward, right = DriveSim.localVelocity(sim.body)
	return math.deg(math.atan2(right, math.abs(forward)))
end

local function speedOf(sim: DriveSim.Sim): number
	return math.sqrt(sim.body.vx * sim.body.vx + sim.body.vy * sim.body.vy)
end

-- The player's steering and button at `t`, before the drift law.
local function player(script: Player, t: number): (number, boolean)
	if t < PRESS then
		return 0, false
	elseif t < RELEASE then
		return script.steer * math.min(1, (t - PRESS) / 0.3), true
	end
	return script.steer * math.max(0, 1 - (t - RELEASE) / 0.3), false
end

type LawState = { engagement: number, lastSlip: number, direction: number }

-- One frame of the law: the rear grip share, the steering and the throttle's share, advancing
-- `state`.
local function law(
	car: Types.CarConfig,
	profile: Profile,
	state: LawState,
	held: boolean,
	steer: number,
	sim: DriveSim.Sim
): (number, number, number)
	local speed = speedOf(sim)
	local forward, right = DriveSim.localVelocity(sim.body)
	local slip = math.abs(bodySlip(sim))
	local rate = (slip - state.lastSlip) / DT
	state.lastSlip = slip
	local wants = held and speed >= SHARED.minKmh * KMH and (math.abs(steer) >= SHARED.steerGate or slip > 5)
	if wants and state.engagement == 0 then
		state.direction = if steer ~= 0 then math.sign(steer) else 1
	end
	state.engagement = if wants
		then math.min(1, state.engagement + DT / SHARED.riseTime)
		else math.max(0, state.engagement - DT / SHARED.fallTime)
	if state.engagement == 0 then
		return 1, steer, 1
	end
	local toward = steer * state.direction
	local reach = math.clamp((toward - SHARED.steerGate) / (1 - SHARED.steerGate), 0, 1)
	local target = if wants and toward > -SHARED.steerGate
		then SHARED.minAngle + (profile.maxAngle - SHARED.minAngle) * reach
		else 0
	local over = slip - target
	local share = profile.holdShare + SHARED.angleGain * over / math.max(target, 5) + SHARED.rateGain * rate
	local grip = 1 - state.engagement * (1 - math.clamp(share, profile.floorShare, 1))
	local path =
		math.atan((right + Geometry.frontAxleDistance(car) * sim.body.yawRate) / math.max(forward, 1))
	local command = math.clamp(SHARED.frontSlip - SHARED.steerGain * (over / 10 + rate / 100), -1, 1)
	local angle = path + state.direction * command * car.front.tyre.slipAngleAtPeak
	local assisted = angle * Steering.ratio(car.steering, forward) / Steering.maxWheelAngle(car.steering)
	local wheel = steer + state.engagement * (math.clamp(assisted, -1, 1) - steer)
	local torque = 1 - state.engagement * math.clamp(over / SHARED.torqueBand, 0, 1)
	return grip, wheel, torque
end

-- The car with a Drift mode: its first mode with TC relaxed and the front share capped.
local function withDriftMode(car: Types.CarConfig, profile: Profile): Types.CarConfig
	local variant = table.clone(car)
	local modes = table.clone(car.modes)
	local drift = table.clone(car.modes[car.modeOrder[1]])
	drift.tcSlipRatio = profile.tcSlip
	drift.frontShareDrive = math.min(drift.frontShareDrive, profile.frontShare)
	drift.frontShareCoast = math.min(drift.frontShareCoast, profile.frontShare)
	modes.Drift = drift
	variant.modes = modes
	return variant
end

local function run(base: Types.CarConfig, profile: Profile, script: Player): Outcome
	local car = withDriftMode(base, profile)
	local sim = DriveSim.new(car)
	local mode = car.modeOrder[1]
	DriveSim.setSpeed(sim, script.kmh * KMH, script.gear)
	local outcome: Outcome = {
		entry = math.huge,
		held = 0,
		peak = 0,
		turned = 0,
		lossPerSecond = 0,
		snap = 0,
		settle = math.huge,
		combined = 0,
		slide = 0,
		smoke = 0,
	}
	local state: LawState = { engagement = 0, lastSlip = 0, direction = 1 }
	local heldFrames = 0
	local speedAtPress, speedAtRelease, headingAtPress = 0, 0, 0
	local readings: { TyreSmoke.Wheel } = {}
	local direction = 0
	while sim.time < STOP do
		local t = sim.time
		local steer, held = player(script, t)
		local grip, wheel, torque = law(car, profile, state, held, steer, sim)
		sim.wheelGrip[3], sim.wheelGrip[4] = grip, grip
		local engaged = state.engagement > 0.05
		local forward = DriveSim.forwardSpeed(sim)
		local hold = math.clamp(0.25 + 0.5 * (script.kmh * KMH - forward), 0, 1)
		local options: DriveSim.InputOptions = {
			throttle = if held then script.throttle * torque else hold,
			steer = wheel,
			gearboxMode = "manual",
			drivingMode = if engaged then "Drift" else mode,
			tc = script.tc,
			esc = not engaged,
		}
		local result: Model.StepResult = DriveSim.frame(sim, DriveSim.input(options), DT)
		local slip = bodySlip(sim)
		if t < PRESS + DT then
			speedAtPress, headingAtPress = speedOf(sim), sim.body.heading
		elseif t < RELEASE then
			if math.abs(slip) >= 10 and outcome.entry == math.huge then
				outcome.entry = t - PRESS
			end
			outcome.peak = math.max(outcome.peak, math.abs(slip))
			direction = if slip ~= 0 then math.sign(slip) else direction
			speedAtRelease = speedOf(sim)
			outcome.turned = math.deg(sim.body.heading - headingAtPress)
			if t >= RELEASE - 1.5 then
				heldFrames += 1
				outcome.held += math.abs(slip)
				TyreSmoke.measure(sim.model, result.wheels, readings)
				for rear = 3, 4 do
					outcome.combined += readings[rear].slip / 2
					outcome.slide += readings[rear].slide / 2
					outcome.smoke += TyreSmoke.share(readings[rear], SmokeConfig.THRESHOLDS) / 2
				end
			end
		else
			outcome.snap = math.max(outcome.snap, -direction * slip)
			if math.abs(slip) < 3 and outcome.settle == math.huge then
				outcome.settle = t - RELEASE
			end
		end
	end
	outcome.held /= math.max(heldFrames, 1)
	outcome.combined /= math.max(heldFrames, 1)
	outcome.slide /= math.max(heldFrames, 1)
	outcome.smoke /= math.max(heldFrames, 1)
	outcome.lossPerSecond = (speedAtPress - speedAtRelease) / KMH / (RELEASE - PRESS)
	return outcome
end

local function row(label: string, outcome: Outcome): string
	local entry = if outcome.entry == math.huge then "never" else ("%.2f"):format(outcome.entry)
	local settle = if outcome.settle == math.huge then "> 3" else ("%.2f"):format(outcome.settle)
	return ("%s | %s | %.1f | %.1f | %.0f | %.1f | %.1f | %s | %.1f | %.1f | %.2f"):format(
		label,
		entry,
		outcome.held,
		outcome.peak,
		outcome.turned,
		outcome.lossPerSecond,
		outcome.snap,
		settle,
		outcome.combined,
		outcome.slide,
		outcome.smoke
	)
end

-- Starting values per car (13_drifting.md §5). The SVJ's speed-dependent ratio leaves it less
-- lock at speed, so a smaller maximum angle.
local PROFILES: { [string]: Profile } = {
	SVJ = { maxAngle = 25, holdShare = 0.85, floorShare = 0.45, tcSlip = 0.3, frontShare = 0.1 },
	DR458 = { maxAngle = 28, holdShare = 0.85, floorShare = 0.45, tcSlip = 0.3, frontShare = 0.1 },
}

local CARS = {
	{ label = "SVJ", car = SVJ, gears = { [50] = 1, [80] = 2, [130] = 3 } },
	{ label = "DR458", car = DR458, gears = { [50] = 2, [80] = 3, [130] = 4 } },
}

print(`Drift candidate at {math.round(1 / DT)} FPS: button held {RELEASE - PRESS} s, then released`)
print("Entry: s from the press to 10 deg of body slip. Held: mean body slip over the last 1.5 s held.")
print("Snap: the most body slip the other way after the release. Settle: s from the release to under 3 deg.")
print(
	"Rear combined slip (over the slip of peak grip), slide (m/s) and smoke share: means over the held 1.5 s."
)
for _, entry in CARS do
	local profile = PROFILES[entry.label]
	print("")
	print(
		`{entry.label}: max angle {profile.maxAngle}, hold share {profile.holdShare}, floor {profile.floorShare}, TC slip {profile.tcSlip}`
	)
	print(
		"km/h, steer, throttle | entry s | held deg | peak deg | turned deg | km/h lost per s | snap deg | settle s | combined | slide | smoke"
	)
	for _, kmh in { 50, 80, 130 } do
		for _, steer in { 0, 0.4, 1 } do
			for _, throttle in { 0.3, 1 } do
				local script: Player =
					{ kmh = kmh, gear = entry.gears[kmh], steer = steer, throttle = throttle, tc = true }
				print(row(("%d, %.1f, %.1f"):format(kmh, steer, throttle), run(entry.car, profile, script)))
			end
		end
	end
	local plain = table.clone(profile)
	plain.holdShare, plain.floorShare = 1, 1
	for _, throttle in { 0.3, 1 } do
		local script: Player = { kmh = 80, gear = entry.gears[80], steer = 1, throttle = throttle, tc = true }
		print(row(("80, 1.0, %.1f, no grip cut"):format(throttle), run(entry.car, plain, script)))
	end
	local script: Player = { kmh = 80, gear = entry.gears[80], steer = 1, throttle = 1, tc = false }
	print(row("80, 1.0, 1.0, TC off", run(entry.car, profile, script)))
end
