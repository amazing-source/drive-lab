--!strict
--[[
	What Space does today and how far a rear grip cut alone goes, for the drift plan
	(docs/research/13_drifting.md). Each car settles into a steady 0.5 g right-hand turn at 80 km/h
	in a fixed gear, then one of:
	- the handbrake held 1 s with the steering held, then released;
	- the handbrake held 0.5 s, then full throttle;
	- the rear tyres' grip scaled to a share through the per-wheel surface grip VehicleRunner feeds
	  the model, with the steering held, the car's own assists on or off.
	Reads only: nothing here is the drift mechanic itself (tools/drift_candidate.luau tries one).

	    lune run games/drive-lab/tools/drift_baseline.luau
]]
local DR458 = require("../src/shared/Config/Cars/DR458/Physics")
local DR458Assists = require("../src/shared/Config/Cars/DR458/Assists")
local DriveSim = require("./DriveSim")
local DriverAssists = require("../src/shared/Rules/DriverAssists")
local Model = require("../src/shared/Vehicle/Model")
local SVJ = require("../src/shared/Config/Cars/SVJ/Physics")
local SVJAssists = require("../src/shared/Config/Cars/SVJ/Assists")
local SmokeConfig = require("../src/shared/Config/TyreSmoke")
local TyreSmoke = require("../src/shared/Rules/TyreSmoke")
local Types = require("../src/shared/Config/Cars/Types")
local World = require("../src/shared/Config/World")

local DT = 1 / 60
local KMH = 1 / 3.6
local G = World.GRAVITY_MPS2
local SETTLE = 6
local AFTER = 3
local SPEED = 80

type Car = { label: string, physics: Types.CarConfig, assists: DriverAssists.Tuning, gear: number }
type Event = "handbrake" | "handbrake then power" | "rear grip"
type Outcome = {
	peakSlip: number,
	endSlip: number,
	speedLoss: number,
	rearSlipRatio: number,
	minRpm: number,
	minClutch: number,
	tcShare: number,
	escShare: number,
	rearCombined: number,
	smoke: number,
}

local CARS: { Car } = {
	{ label = "SVJ", physics = SVJ, assists = SVJAssists, gear = 2 },
	{ label = "DR458", physics = DR458, assists = DR458Assists, gear = 3 },
}

local function input(car: Car, assisted: boolean, options: DriveSim.InputOptions): Model.DriverInput
	local mode = car.physics.modeOrder[1]
	local systems = DriverAssists.assists(false, mode, car.assists)
	options.drivingMode = mode
	options.gearboxMode = "manual"
	options.abs = systems.abs
	options.tc = assisted and systems.tc
	options.esc = assisted and systems.esc
	return DriveSim.input(options)
end

local function speedOf(sim: DriveSim.Sim): number
	return math.sqrt(sim.body.vx * sim.body.vx + sim.body.vy * sim.body.vy)
end

-- Body slip (deg): the velocity's angle from the heading, positive when it points right of it.
local function bodySlip(sim: DriveSim.Sim): number
	local forward, right = DriveSim.localVelocity(sim.body)
	return math.deg(math.atan2(right, math.abs(forward)))
end

-- A steady right-hand turn at SPEED: the throttle holds the speed, the steering is wound toward
-- 0.5 g. Returns the sim and the steering it settled on.
local function settle(car: Car, assisted: boolean): (DriveSim.Sim, number)
	local sim = DriveSim.new(car.physics)
	DriveSim.setSpeed(sim, SPEED * KMH, car.gear)
	local steer = 0
	while sim.time < SETTLE do
		local forward = DriveSim.forwardSpeed(sim)
		steer = math.clamp(steer + 0.5 * (0.5 - forward * sim.body.yawRate / G) * DT, -1, 1)
		local throttle = math.clamp(0.25 + 0.5 * (SPEED * KMH - forward), 0, 1)
		DriveSim.frame(sim, input(car, assisted, { throttle = throttle, steer = steer }), DT)
	end
	return sim, steer
end

-- The driver's inputs `t` seconds into the event.
local function controls(event: Event, sim: DriveSim.Sim, held: number, t: number): DriveSim.InputOptions
	if event == "handbrake" then
		return { handbrake = if t < 1 then 1 else 0, steer = held }
	elseif event == "handbrake then power" then
		return if t < 0.5 then { handbrake = 1, steer = held } else { throttle = 1, steer = held }
	end
	local forward = DriveSim.forwardSpeed(sim)
	return { throttle = math.clamp(0.25 + 0.5 * (SPEED * KMH - forward), 0, 1), steer = held }
end

local function run(car: Car, event: Event, rearGrip: number, assisted: boolean): Outcome
	local sim, held = settle(car, assisted)
	local start, startSpeed = sim.time, speedOf(sim)
	local outcome: Outcome = {
		peakSlip = 0,
		endSlip = 0,
		speedLoss = 0,
		rearSlipRatio = 0,
		minRpm = math.huge,
		minClutch = 1,
		tcShare = 0,
		escShare = 0,
		rearCombined = 0,
		smoke = 0,
	}
	local readings: { TyreSmoke.Wheel } = {}
	local frames = 0
	while sim.time - start < AFTER do
		local t = sim.time - start
		local grip = 1 + (rearGrip - 1) * math.min(1, t / 0.2)
		sim.wheelGrip[3], sim.wheelGrip[4] = grip, grip
		local result = DriveSim.frame(sim, input(car, assisted, controls(event, sim, held, t)), DT)
		local telemetry = result.telemetry
		frames += 1
		outcome.peakSlip = math.max(outcome.peakSlip, math.abs(bodySlip(sim)))
		outcome.rearSlipRatio =
			math.min(outcome.rearSlipRatio, result.wheels[3].slipRatio, result.wheels[4].slipRatio)
		outcome.minRpm = math.min(outcome.minRpm, telemetry.rpm)
		outcome.minClutch = math.min(outcome.minClutch, telemetry.clutch)
		outcome.tcShare += (if telemetry.tcActive then 1 else 0) / (AFTER / DT)
		outcome.escShare += (if telemetry.escActive then 1 else 0) / (AFTER / DT)
		TyreSmoke.measure(sim.model, result.wheels, readings)
		for wheel = 3, 4 do
			outcome.rearCombined += readings[wheel].slip / 2
			outcome.smoke += TyreSmoke.share(readings[wheel], SmokeConfig.THRESHOLDS) / 2
		end
	end
	outcome.endSlip = math.abs(bodySlip(sim))
	outcome.speedLoss = (startSpeed - speedOf(sim)) / KMH
	outcome.rearCombined /= frames
	outcome.smoke /= frames
	return outcome
end

local function row(label: string, outcome: Outcome): string
	return ("%s | %.1f | %.1f | %.1f | %.2f | %.0f | %.2f | %.0f %% | %.0f %% | %.1f | %.2f"):format(
		label,
		outcome.peakSlip,
		outcome.endSlip,
		outcome.speedLoss,
		outcome.rearSlipRatio,
		outcome.minRpm,
		outcome.minClutch,
		outcome.tcShare * 100,
		outcome.escShare * 100,
		outcome.rearCombined,
		outcome.smoke
	)
end

print(
	`Drift baseline, DriveSim at {math.round(1 / DT)} FPS: steady 0.5 g right turn at {SPEED} km/h, then {AFTER} s`
)
print("Body slip in degrees; speed lost in km/h over the 3 s; rear slip ratio is the lowest (a lock is -1);")
print("rear combined slip is over the slip of peak grip (Rules/TyreSmoke); smoke is the rear tyres' share.")
for _, car in CARS do
	local _, steer = settle(car, true)
	print("")
	print(
		`{car.label} ({car.physics.modeOrder[1]}, gear {car.gear}, steering {("%.3f"):format(steer)} at 0.5 g)`
	)
	print(
		"Event | assists | peak slip | end slip | speed lost | rear slip ratio | min rpm | min clutch | TC | ESC | rear combined | smoke"
	)
	print(row("handbrake 1 s, steering held | on", run(car, "handbrake", 1, true)))
	print(row("handbrake 0.5 s then full throttle | on", run(car, "handbrake then power", 1, true)))
	for _, share in { 0.8, 0.65, 0.5 } do
		for _, assisted in { true, false } do
			local systems = if assisted then "on" else "off"
			print(
				row(`rear grip x{share}, steering held | {systems}`, run(car, "rear grip", share, assisted))
			)
		end
	end
end
