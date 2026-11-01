--!strict
--[[
	Speed a car loses to the steering at speed. The keyboard's D tapped for 0.4 s or held for 1 s,
	then released for 2 s, through the keyboard's input help (its steering limit included), against
	the same run with no steering; throttle held (W) and lifted. Prints the speed change per second
	over each phase with the steering's own share of it, the peak lateral g, how long ESC acted and
	the speed its braking took. Then a 3 s sweeper at a steady 0.45 g with W held, and the lateral g
	at which ESC first acts in a slow steer at a held speed.

	    lune run games/drive-lab/tools/steer_scrub [--fields]

	`--fields` reruns the Boss 302 with one group of the SVJ's handling values at a time, to find
	which difference moves its loss.
]]
local Boss302 = require("../src/shared/Config/Cars/Boss302/Physics")
local DriveSim = require("./DriveSim")
local InputHelp = require("../src/shared/Config/InputHelp")
local SVJ = require("../src/shared/Config/Cars/SVJ/Physics")
local Steering = require("../src/shared/Vehicle/Steering")
local Types = require("../src/shared/Config/Cars/Types")
local World = require("../src/shared/Config/World")
local process = require("@lune/process")

local KMH = 1 / 3.6
local DT = 1 / 60
local AFTER_SECONDS = 2

type Run = {
	gear: number,
	shifts: number,
	steerRate: number,
	afterRate: number,
	peakG: number,
	escSeconds: number,
	escLoss: number,
}

-- The gear the automatic holds at this throttle: the highest whose rpm stays over its downshift
-- point.
local function gearFor(car: Types.CarConfig, mode: Types.DrivingMode, speed: number, throttle: number): number
	local points = car.modes[mode].downshiftRpm
	local down = points.light + (points.full - points.light) * throttle
	local chosen = 1
	for gear, ratio in car.gearbox.ratios do
		local rpm = speed / car.rear.tyre.radius * car.driveline.rearReduction * ratio * 60 / (2 * math.pi)
		if rpm >= down then
			chosen = gear
		end
	end
	return chosen
end

local function lateralG(sim: DriveSim.Sim, vx: number, vy: number): number
	local heading = sim.body.heading
	local lateral = ((sim.body.vy - vy) * math.cos(heading) - (sim.body.vx - vx) * math.sin(heading)) / DT
	return math.abs(lateral) / World.GRAVITY_MPS2
end

-- Speed (km/h) ESC's braking takes off the car this frame, as a force at the road.
local function escLoss(sim: DriveSim.Sim): number
	local car, loss = sim.car, 0
	for wheel, torque in sim.model.electronics.escBrake do
		local radius = if wheel <= 2 then car.front.tyre.radius else car.rear.tyre.radius
		loss += torque / radius / car.mass * DT / KMH
	end
	return loss
end

local function run(
	car: Types.CarConfig,
	mode: Types.DrivingMode,
	kmh: number,
	throttle: number,
	steer: number,
	steerSeconds: number
): Run
	local sim = DriveSim.new(car, InputHelp.keyboard)
	DriveSim.setSpeed(sim, kmh * KMH, gearFor(car, mode, kmh * KMH, throttle))
	-- The pedal already where it is held, so the automatic never shifts on its ramp.
	sim.model.controls.throttle = throttle
	local turning = DriveSim.input({ throttle = throttle, steer = steer, drivingMode = mode })
	local released = DriveSim.input({ throttle = throttle, drivingMode = mode })
	for _ = 1, 15 do
		DriveSim.frame(sim, released, DT)
	end
	local start, startSpeed = sim.time, DriveSim.forwardSpeed(sim)
	local result: Run = {
		gear = sim.model.gearbox.gear,
		shifts = 0,
		steerRate = 0,
		afterRate = 0,
		peakG = 0,
		escSeconds = 0,
		escLoss = 0,
	}
	local releaseSpeed = startSpeed
	while sim.time - start < steerSeconds + AFTER_SECONDS - 1e-9 do
		local steering = sim.time - start < steerSeconds - 1e-9
		local vx, vy = sim.body.vx, sim.body.vy
		local frame = DriveSim.frame(sim, if steering then turning else released, DT)
		result.peakG = math.max(result.peakG, lateralG(sim, vx, vy))
		if frame.telemetry.escActive then
			result.escSeconds += DT
		end
		if frame.telemetry.gear ~= result.gear then
			result.shifts += 1
			result.gear = frame.telemetry.gear
		end
		result.escLoss += escLoss(sim)
		if steering and sim.time - start >= steerSeconds - 1e-9 then
			releaseSpeed = DriveSim.forwardSpeed(sim)
		end
	end
	result.steerRate = (releaseSpeed - startSpeed) / KMH / steerSeconds
	result.afterRate = (DriveSim.forwardSpeed(sim) - releaseSpeed) / KMH / AFTER_SECONDS
	return result
end

-- Steering input that turns a neutral car at `g` at this speed.
local function steerFor(car: Types.CarConfig, speed: number, g: number): number
	local perInput = Steering.maxWheelAngle(car.steering) / Steering.ratio(car.steering, speed)
	return car.wheelbase * g * World.GRAVITY_MPS2 / (speed * speed) / perInput
end

-- Lateral g when ESC first acts: the road wheels turned in slowly (a neutral car's 1 g in 8 s)
-- with the throttle holding the speed. nil when it never acts below the tyres' limit.
local function escOnset(car: Types.CarConfig, mode: Types.DrivingMode, kmh: number): number?
	local speed = kmh * KMH
	local sim = DriveSim.new(car)
	DriveSim.setSpeed(sim, speed, gearFor(car, mode, speed, 0.5))
	local fullG = steerFor(car, speed, 1)
	local throttle = 0.3
	while sim.time < 8 do
		throttle = math.clamp(throttle + (speed - DriveSim.forwardSpeed(sim)) * 5 * DT, 0, 1)
		local input =
			DriveSim.input({ throttle = throttle, steer = fullG * sim.time / 8, drivingMode = mode })
		local vx, vy = sim.body.vx, sim.body.vy
		local frame = DriveSim.frame(sim, input, DT)
		if frame.telemetry.escActive then
			return lateralG(sim, vx, vy)
		end
	end
	return nil
end

-- A sweeper: W held for 3 s, the wheel turned in and then held, steered by the lateral g toward
-- `g`. Returns the speed change per second against the same run straight, the mean lateral g over
-- the last second, how long ESC acted and the speed its braking took.
local function sweeper(
	car: Types.CarConfig,
	mode: Types.DrivingMode,
	kmh: number,
	g: number
): (number, number, number, number)
	local function drive(target: number): (number, number, number, number)
		local speed = kmh * KMH
		local sim = DriveSim.new(car)
		DriveSim.setSpeed(sim, speed, gearFor(car, mode, speed, 1))
		sim.model.controls.throttle = 1
		local unit = steerFor(car, speed, 1)
		local steer, measured = 0, 0
		local lateral, samples, acting, loss = 0, 0, 0, 0
		while sim.time < 3 - 1e-9 do
			steer = math.clamp(steer + (target - measured) * unit * 4 * DT, 0, 1)
			local input = DriveSim.input({ throttle = 1, steer = steer, drivingMode = mode })
			local vx, vy = sim.body.vx, sim.body.vy
			local frame = DriveSim.frame(sim, input, DT)
			measured = lateralG(sim, vx, vy)
			if sim.time > 2 then
				lateral += measured
				samples += 1
			end
			if frame.telemetry.escActive then
				acting += DT
			end
			loss += escLoss(sim)
		end
		return (DriveSim.forwardSpeed(sim) - speed) / KMH / 3, lateral / samples, acting, loss
	end
	local rate, lateral, acting, loss = drive(g)
	local straight = drive(0)
	return rate - straight, lateral, acting, loss
end

local function report(label: string, car: Types.CarConfig, mode: Types.DrivingMode)
	for _, steerSeconds in { 0.4, 1 } do
		for _, kmh in { 120, 160 } do
			for _, throttle in { 1, 0 } do
				local turned = run(car, mode, kmh, throttle, 1, steerSeconds)
				local straight = run(car, mode, kmh, throttle, 0, steerSeconds)
				print(
					("%s | D %.1f s | %d | %s | %d (%d) | %+.1f (%+.1f) | %+.1f (%+.1f) | %.2f | %.2f s | %.2f km/h"):format(
						label,
						steerSeconds,
						kmh,
						if throttle > 0 then "W held" else "lifted",
						turned.gear,
						turned.shifts,
						turned.steerRate,
						turned.steerRate - straight.steerRate,
						turned.afterRate,
						turned.afterRate - straight.afterRate,
						turned.peakG,
						turned.escSeconds,
						turned.escLoss
					)
				)
			end
		end
	end
	for _, kmh in { 120, 160 } do
		local rate, lateral, acting, loss = sweeper(car, mode, kmh, 0.45)
		print(
			("%s | sweeper | %d | W held | the curve's cost %+.1f km/h/s | at %.2f g | ESC acting %.2f s | ESC braking %.2f km/h"):format(
				label,
				kmh,
				rate,
				lateral,
				acting,
				loss
			)
		)
	end
	local onsets = {}
	for _, kmh in { 80, 120, 160 } do
		local g = escOnset(car, mode, kmh)
		table.insert(onsets, if g then ("%d km/h %.2f g"):format(kmh, g) else ("%d km/h none"):format(kmh))
	end
	print(`{label} | ESC first acts at | {table.concat(onsets, ", ")}`)
end

local function copy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for key, inner in value :: any do
		out[key] = copy(inner)
	end
	return out :: any
end

-- The Boss with `change` applied to a writable copy.
local function variant(change: (any) -> ()): Types.CarConfig
	local car = copy(Boss302) :: any
	change(car)
	return Types.define(car)
end

print(
	"Car | steer | km/h | throttle | gear (shifts) | steering, km/h/s (its share) | 2 s after release | peak lateral g | ESC acting | ESC braking"
)
report("SVJ Strada", SVJ, "Strada")
report("Boss Normal", Boss302, "Normal")

if table.find(process.args, "--fields") then
	local svj = SVJ :: any
	local fields: { { string | (any) -> () } } = {
		{
			"steering ratio",
			function(car)
				car.steering.lowSpeedRatio = svj.steering.lowSpeedRatio
				car.steering.highSpeedRatio = svj.steering.highSpeedRatio
				car.steering.lockToLockTurns = svj.steering.lockToLockTurns
			end,
		},
		{
			"ESC reference speed",
			function(car)
				car.electronics.characteristicSpeed = svj.electronics.characteristicSpeed
			end,
		},
		{
			"roll stiffness",
			function(car)
				car.suspension.rollGradient = svj.suspension.rollGradient
				car.suspension.frontRollShare = svj.suspension.frontRollShare
			end,
		},
		{
			"differential",
			function(car)
				car.driveline.lsdPreload = svj.driveline.lsdPreload
				car.driveline.lsdPowerRamp = svj.driveline.lsdPowerRamp
				car.driveline.lsdCoastRamp = svj.driveline.lsdCoastRamp
			end,
		},
		{
			"aero drag",
			function(car)
				car.aero.dragArea = svj.aero.dragArea
			end,
		},
		{
			"ESC thresholds (Strada's)",
			function(car)
				car.modes.Normal.escOversteer = svj.modes.Strada.escOversteer
				car.modes.Normal.escUndersteer = svj.modes.Strada.escUndersteer
				car.modes.Normal.escSideslip = svj.modes.Strada.escSideslip
			end,
		},
	}
	for _, field in fields do
		report(`Boss, SVJ {field[1]}`, variant(field[2] :: (any) -> ()), "Normal")
	end
end
