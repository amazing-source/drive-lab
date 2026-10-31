--!strict
--[[
	Prints the Boss 302 Laguna Seca against the published data (research note §1.10) and the cost
	of one Model.step. `lune run games/drive-lab/tools/boss302_calibrate` from the repo root.
	Standing starts are flat out in the automatic, TracKey's with its launch control armed on the
	brake first; distances and times are from the start, with no one-foot rollout.
]]
local Boss302 = require("../src/shared/Config/Cars/Boss302/Physics")
local DriveSim = require("./DriveSim")
local Model = require("../src/shared/Vehicle/Model")

local KMH = 1 / 3.6
local MPH = 1.609344 / 3.6
local G = 9.81
local QUARTER_MILE = 402.336

local function stepCost(dt: number): number
	local sim = DriveSim.new(Boss302)
	DriveSim.setSpeed(sim, 25, 2)
	local input = DriveSim.input({ throttle = 1, steer = 0.1, drivingMode = "Normal" })
	for _ = 1, 30 do
		DriveSim.frame(sim, input, dt)
	end
	local runs = 2000
	local start = os.clock()
	for _ = 1, runs do
		Model.step(sim.model, input, sim.contacts, sim.chassis, dt)
	end
	return (os.clock() - start) / runs * 1e6
end

local function standingStart(mode: string, launch: boolean, dt: number): (number, number, number, string)
	local sim = DriveSim.new(Boss302)
	if launch then
		local hold = DriveSim.input({ throttle = 1, brake = 1, drivingMode = mode })
		while sim.time < 1.5 do
			DriveSim.frame(sim, hold, dt)
		end
	end
	local go = DriveSim.input({ throttle = 1, drivingMode = mode })
	local start, startX = sim.time, sim.body.x
	local time60, gear = math.huge, 1
	local shifts: { string } = {}
	while sim.time - start < 20 do
		local before = DriveSim.forwardSpeed(sim)
		local result = DriveSim.frame(sim, go, dt)
		local after = DriveSim.forwardSpeed(sim)
		if before < 60 * MPH and after >= 60 * MPH then
			time60 = sim.time - dt * (after - 60 * MPH) / (after - before) - start
		end
		if result.telemetry.gear ~= gear then
			gear = result.telemetry.gear
			table.insert(shifts, ("%d at %.2f s, %.0f km/h"):format(gear, sim.time - start, after / KMH))
		end
		if sim.body.x - startX >= QUARTER_MILE then
			return time60, sim.time - start, after, table.concat(shifts, "; ")
		end
	end
	return time60, math.huge, 0, table.concat(shifts, "; ")
end

local function topSpeed(dt: number): number
	local sim = DriveSim.new(Boss302)
	DriveSim.setSpeed(sim, 240 * KMH, 6)
	local drive = DriveSim.input({ throttle = 1, drivingMode = "Normal", gearboxMode = "manual" })
	while sim.time < 30 do
		DriveSim.frame(sim, drive, dt)
	end
	return DriveSim.forwardSpeed(sim)
end

print(
	("Model.step cost: %.0f us per frame at 60 FPS, %.0f us at 30 FPS"):format(
		stepCost(1 / 60),
		stepCost(1 / 30)
	)
)
local dt = 1 / 60
print("")
print("Target | Source | Result")
for _, case in { { "TracKey", true }, { "Normal", false } } do
	local time60, quarter, trap, shifts = standingStart(case[1], case[2], dt)
	local how = if case[2] then "TracKey, launch control" else "Normal, from rest"
	print(("0-60 mph 4.0-4.6 s | MT, Edmunds | %.2f s (%s)"):format(time60, how))
	print(
		("1/4 mile 12.3-12.7 s @ 112.9-115.8 mph | MT, Edmunds | %.2f s @ %.1f mph"):format(
			quarter,
			trap / MPH
		)
	)
	print(("  shifts: %s"):format(shifts))
end
print(("Top speed 155 mph (249.4 km/h), a limit | Ford | %.1f km/h in 6th"):format(topSpeed(dt) / KMH))
local limiter = Boss302.engine.limiterRpm * 2 * math.pi / 60
for gear = 1, 5 do
	local ratio = Boss302.gearbox.ratios[gear] * Boss302.driveline.rearReduction
	local theory = limiter * Boss302.rear.tyre.radius / ratio
	local top = DriveSim.gearTop(Boss302, gear, dt)
	print(
		("Gear %d at 7,500 rpm %.1f km/h | ratios | %.1f km/h (%+.2f %%)"):format(
			gear,
			theory / KMH,
			top / KMH,
			(top / theory - 1) * 100
		)
	)
end
print(("Skidpad 200 ft 0.98 g | Edmunds | %.3f g"):format(DriveSim.skidpad(Boss302, 30.48, dt, "Normal")))
local stop60 = DriveSim.brake(Boss302, 60 * MPH, dt, { drivingMode = "Normal" })
local stop100 = DriveSim.brake(Boss302, 100 * KMH, dt, { drivingMode = "Normal" })
print(
	("60-0 mph 32.0 m (105 ft) | Edmunds | %.1f m (peak %.2f g)"):format(
		stop60.distance,
		stop60.peakDeceleration / G
	)
)
print(("100-0 km/h 33.3 m | Sport Auto | %.1f m"):format(stop100.distance))
local drift, jitter = DriveSim.rest(Boss302, 30, dt)
print(("Parked 30 s | 01 §3.3 | drift %.2f mm, speed %.1e m/s"):format(drift * 1000, jitter))

print("")
print("FPS | 0-100 km/h s (launch) | 0-200 km/h s | 100-0 km/h m")
for _, fps in { 30, 60, 120, 240 } do
	local frame = 1 / fps
	local launch = DriveSim.launch(Boss302, frame)
	local stop = DriveSim.brake(Boss302, 100 * KMH, frame)
	print(("%d | %.3f | %.3f | %.2f"):format(fps, launch.time100, launch.time200, stop.distance))
end
