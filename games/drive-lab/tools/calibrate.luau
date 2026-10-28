--!strict
--[[
	Prints the SVJ's calibration against its targets, the same runs at four frame rates, and
	the cost of one Model.step. `lune run games/drive-lab/tools/calibrate` from the repo root.
	The step cost is measured first: on a laptop that throttles under sustained load, a timing
	taken after the long runs reads several times slower than the CPU really is.
]]
local DriveSim = require("./DriveSim")
local Model = require("../src/shared/Vehicle/Model")
local SVJ = require("../src/shared/Config/Cars/SVJ")

local KMH = 1 / 3.6
local G = 9.81

local function stepCost(dt: number): number
	local sim = DriveSim.new(SVJ)
	DriveSim.setSpeed(sim, 25, 2)
	local input = DriveSim.input({ throttle = 1, steer = 0.1 })
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

local function line(text: string)
	print(text)
end

line(
	("Model.step cost: %.0f us per frame at 60 FPS, %.0f us at 30 FPS"):format(
		stepCost(1 / 60),
		stepCost(1 / 30)
	)
)

local dt = 1 / 60
local launch = DriveSim.launch(SVJ, dt)
local stop = DriveSim.brake(SVJ, 100 * KMH, dt)
local stopNoAbs = DriveSim.brake(SVJ, 100 * KMH, dt, { abs = false })
local topSpeed, topRpm, topGear = DriveSim.topSpeed(SVJ, 300 * KMH, dt)
line("")
line("Target | Source | Result")
line(("0-100 km/h 2.8 s | OEM 02 P1 | %.2f s"):format(launch.time100))
line(("0-200 km/h 8.6 s | OEM 02 P2 | %.2f s"):format(launch.time200))
line(
	("100-0 km/h 30 m | OEM 02 P7 | %.1f m with ABS (peak %.2f g), %.1f m without"):format(
		stop.distance,
		stop.peakDeceleration / G,
		stopNoAbs.distance
	)
)
line(
	("Top speed > 350 km/h | OEM 02 P9 | %.1f km/h in %d at %.0f rpm"):format(topSpeed / KMH, topGear, topRpm)
)
local limiter = SVJ.engine.limiterRpm * 2 * math.pi / 60
for gear = 1, 6 do
	local theory = limiter * SVJ.rear.tyre.radius / (SVJ.gearbox.ratios[gear] * SVJ.driveline.rearReduction)
	local top = DriveSim.gearTop(SVJ, gear, dt)
	line(
		("Gear %d at 8,700 rpm %.1f km/h | DER 02 §2.5 | %.1f km/h (%+.2f %%)"):format(
			gear,
			theory / KMH,
			top / KMH,
			(top / theory - 1) * 100
		)
	)
end
line(("Skidpad 40 m 1.10 g | EST 02 P10 | %.3f g"):format(DriveSim.skidpad(SVJ, 40, dt)))
local drift, jitter = DriveSim.rest(SVJ, 30, dt)
line(("Parked 30 s | 01 §3.3 | drift %.2f mm, speed %.1e m/s"):format(drift * 1000, jitter))

line("")
line("FPS | 0-100 s | 0-200 s | 100-0 m | skidpad g")
for _, fps in { 30, 60, 120, 240 } do
	local frame = 1 / fps
	local run = DriveSim.launch(SVJ, frame)
	local halt = DriveSim.brake(SVJ, 100 * KMH, frame)
	line(
		("%d | %.3f | %.3f | %.2f | %.3f"):format(
			fps,
			run.time100,
			run.time200,
			halt.distance,
			DriveSim.skidpad(SVJ, 40, frame)
		)
	)
end
