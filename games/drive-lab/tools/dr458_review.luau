--!strict
--[[
	Measures the DR458 on tools/DriveSim for its driving review
	(docs/evidence/dr458-driving-review/README.md): straight-line times and the automatic's shift
	points per manettino position, each gear's top, braking from 100 and 200 km/h, steady lateral
	acceleration at a low and a high speed, and what each position does to traction. Reads only.

	    lune run games/drive-lab/tools/dr458_review.luau [fps]
]]
local Assists = require("../src/shared/Config/Cars/DR458/Assists")
local DR458 = require("../src/shared/Config/Cars/DR458/Physics")
local DriveSim = require("./DriveSim")
local DriverAssists = require("../src/shared/Rules/DriverAssists")
local Model = require("../src/shared/Vehicle/Model")
local Tyre = require("../src/shared/Vehicle/Tyre")
local Types = require("../src/shared/Config/Cars/Types")
local World = require("../src/shared/Config/World")
local process = require("@lune/process")

local KMH = 1 / 3.6
local G = World.GRAVITY_MPS2
local RPM = 2 * math.pi / 60
local DT = 1 / (tonumber(process.args[1]) or 60)
local REAR = { 3, 4 }

type Shift = { gear: number, rpm: number, kmh: number }
type Traction = { meanSlip: number, peakSlip: number, tcShare: number }

-- The systems the driving client runs in `mode`, with `options` on top.
local function inputFor(mode: Types.DrivingMode, options: DriveSim.InputOptions): DriveSim.InputOptions
	local assists = DriverAssists.assists(false, mode, Assists)
	options.drivingMode = mode
	options.abs = if options.abs == nil then assists.abs else options.abs
	options.tc = if options.tc == nil then assists.tc else options.tc
	options.esc = assists.esc
	return options
end

local function rearSlip(result: Model.StepResult): number
	local wheels = result.wheels
	return (wheels[REAR[1]].slipRatio + wheels[REAR[2]].slipRatio) / 2
end

-- Folds one frame into a traction tally; `count` is the frame number from 1.
local function tally(into: Traction, result: Model.StepResult, count: number)
	local slip = rearSlip(result)
	into.meanSlip += (slip - into.meanSlip) / count
	into.peakSlip = math.max(into.peakSlip, slip)
	into.tcShare += ((if result.telemetry.tcActive then 1 else 0) - into.tcShare) / count
end

-- DriveSim.launch's start (brake and full throttle for 1.5 s, then the brake released) logging the
-- rpm and speed on the last frame before each upshift begins (the shift cuts the engine within its
-- first frame), the time to 50 km/h, and the rear tyres over the first 3 s after the release.
local function launchLog(mode: Types.DrivingMode): ({ Shift }, Traction, number)
	local sim = DriveSim.new(DR458)
	local hold = DriveSim.input(inputFor(mode, { throttle = 1, brake = 1 }))
	while sim.time < 1.5 do
		DriveSim.frame(sim, hold, DT)
	end
	local go = DriveSim.input(inputFor(mode, { throttle = 1 }))
	local shifts: { Shift } = {}
	local traction: Traction = { meanSlip = 0, peakSlip = 0, tcShare = 0 }
	local start, frames, time50, wasShifting = sim.time, 0, math.huge, false
	local lastGear, lastRpm, lastKmh = 0, 0, 0
	while sim.time - start < 25 do
		local result = DriveSim.frame(sim, go, DT)
		local t = result.telemetry
		local kmh = DriveSim.forwardSpeed(sim) / KMH
		if t.shifting and not wasShifting and not shifts[lastGear] then
			shifts[lastGear] = { gear = lastGear, rpm = lastRpm, kmh = lastKmh }
		end
		wasShifting, lastGear, lastRpm, lastKmh = t.shifting, t.gear, t.rpm, kmh
		if kmh >= 50 and time50 == math.huge then
			time50 = sim.time - start
		end
		if sim.time - start <= 3 then
			frames += 1
			tally(traction, result, frames)
		end
	end
	return shifts, traction, time50
end

-- Force over peak force along each tyre's own slip curve, at the slips listed.
local function curveRow(
	label: string,
	curve: Tyre.Curve,
	slips: { number },
	toSlip: (number) -> number
): string
	local cells = {}
	for _, slip in slips do
		table.insert(cells, ("%.2f"):format(Tyre.shape(curve, toSlip(slip))))
	end
	return `{label} | {table.concat(cells, " | ")}`
end

-- DriveSim.brake's 0.5 s coast in `gear` before the pedal (#128: it loses speed in gear).
local function settle(speed: number, gear: number): DriveSim.Sim
	local sim = DriveSim.new(DR458)
	DriveSim.setSpeed(sim, speed, gear)
	local coast = DriveSim.input(inputFor("1", {}))
	while sim.time < 0.5 do
		DriveSim.frame(sim, coast, DT)
	end
	return sim
end

-- Full brake with the pedal going down at `speed`: the coast starts faster by its own loss,
-- corrected twice. Returns the distance (m), the peak 0.1 s deceleration (g) and the speed the
-- pedal went down at (km/h).
local function brake(speed: number, gear: number, abs: boolean): (number, number, number)
	local start = speed
	local sim = settle(start, gear)
	for _ = 1, 2 do
		start += speed - DriveSim.forwardSpeed(sim)
		sim = settle(start, gear)
	end
	local pedal = DriveSim.forwardSpeed(sim) / KMH
	local stop = DriveSim.input(inputFor("1", { brake = 1, abs = abs }))
	local startX, start = sim.body.x, sim.time
	local window = math.max(1, math.floor(0.1 / DT + 0.5))
	local history: { number } = {}
	local peak = 0
	while sim.time - start < 15 and DriveSim.forwardSpeed(sim) > 0.05 do
		DriveSim.frame(sim, stop, DT)
		table.insert(history, DriveSim.forwardSpeed(sim))
		if #history > window then
			peak = math.max(peak, (history[#history - window] - history[#history]) / (window * DT))
		end
	end
	return sim.body.x - startX, peak / G, pedal
end

-- Constant speed in a fixed gear, steering wound on at `rate` per second (ISO 4138's constant-speed
-- method), assists off as on DriveSim.skidpad. Returns the best 1 s mean lateral g held, the body
-- slip there (deg), the downforce there (kg), the steering there, and why the run ended.
local function steadyTurn(kmh: number, gear: number, rate: number): (number, number, number, number, string)
	local sim = DriveSim.new(DR458)
	local target = kmh * KMH
	DriveSim.setSpeed(sim, target, gear)
	local window = math.floor(1 / DT + 0.5)
	local samples: { number } = {}
	local sum, best, bestSlip, bestDown, bestSteer, steer = 0, 0, 0, 0, 0, 0
	local ended = "120 s"
	while sim.time < 120 do
		local forward, right = DriveSim.localVelocity(sim.body)
		steer = math.min(1, steer + rate * DT)
		local throttle = math.clamp(0.3 + 0.5 * (target - forward), 0, 1)
		local options = { throttle = throttle, steer = steer, gearboxMode = "manual" :: "manual" }
		local result = DriveSim.frame(sim, DriveSim.input(inputFor("1", options)), DT)
		local slip = math.deg(math.atan2(right, forward))
		table.insert(samples, forward * sim.body.yawRate)
		sum += samples[#samples]
		if #samples > window then
			sum -= table.remove(samples, 1) :: number
		end
		if #samples == window and sum / window > best then
			best, bestSlip, bestSteer = sum / window, slip, steer
			bestDown = (result.downforceFront + result.downforceRear) / G
		end
		if math.abs(slip) > 12 or forward < 0.9 * target then
			ended = if math.abs(slip) > 12 then "body slip over 12 deg" else "speed under 90 %"
			break
		end
	end
	return best / G, bestSlip, bestDown, bestSteer, `{ended}, steering {("%.2f"):format(steer)}`
end

-- Full throttle for 1.5 s in a fixed gear from `kmh`, straight ahead.
local function rollOn(mode: Types.DrivingMode, kmh: number, gear: number): Traction
	local sim = DriveSim.new(DR458)
	DriveSim.setSpeed(sim, kmh * KMH, gear)
	local go = DriveSim.input(inputFor(mode, { throttle = 1, gearboxMode = "manual" }))
	local traction: Traction = { meanSlip = 0, peakSlip = 0, tcShare = 0 }
	local frames = 0
	while sim.time < 1.5 do
		frames += 1
		tally(traction, DriveSim.frame(sim, go, DT), frames)
	end
	return traction
end

-- A steady turn at `kmh` in 2nd with the steering held, then full throttle for 2 s with the
-- steering still held. Returns the lateral g before, and the peak body slip (deg) and rear slip
-- ratio after.
local function powerStep(mode: Types.DrivingMode, kmh: number, steer: number): (number, number, number)
	local sim = DriveSim.new(DR458)
	local target = kmh * KMH
	DriveSim.setSpeed(sim, target, 2)
	local lateral = 0
	while sim.time < 5 do
		local forward = DriveSim.forwardSpeed(sim)
		local throttle = math.clamp(0.25 + 0.5 * (target - forward), 0, 1)
		local options = { throttle = throttle, steer = steer, gearboxMode = "manual" :: "manual" }
		DriveSim.frame(sim, DriveSim.input(inputFor(mode, options)), DT)
		lateral = forward * sim.body.yawRate / G
	end
	local go = DriveSim.input(inputFor(mode, { throttle = 1, steer = steer, gearboxMode = "manual" }))
	local peakSlip, peakRear = 0, 0
	local stop = sim.time + 2
	while sim.time < stop do
		local result = DriveSim.frame(sim, go, DT)
		local forward, right = DriveSim.localVelocity(sim.body)
		peakSlip = math.max(peakSlip, math.abs(math.deg(math.atan2(right, math.abs(forward)))))
		peakRear = math.max(peakRear, rearSlip(result))
	end
	return lateral, peakSlip, peakRear
end

local function gearSpeed(gear: number, rpm: number): number
	return rpm
		* RPM
		* DR458.rear.tyre.radius
		/ (DR458.gearbox.ratios[gear] * DR458.driveline.rearReduction)
		/ KMH
end

print(`DR458 driving review, DriveSim at {math.round(1 / DT)} FPS`)
print("")
print(
	"Manettino | 0-50 km/h s | 0-100 km/h s | 0-200 km/h s | launch rear slip mean / peak | TC acting share"
)
local shiftsByMode: { [string]: { Shift } } = {}
for _, mode in DR458.modeOrder do
	local launch = DriveSim.launch(DR458, DT, inputFor(mode, {}))
	local shifts, traction, time50 = launchLog(mode)
	shiftsByMode[mode] = shifts
	print(
		("%s | %.2f | %.2f | %.2f | %.3f / %.3f | %.0f %%"):format(
			mode,
			time50,
			launch.time100,
			launch.time200,
			traction.meanSlip,
			traction.peakSlip,
			traction.tcShare * 100
		)
	)
end

print("")
print("Gear | at 9,000 rpm km/h | at 9,200 rpm (limiter) km/h | manual top km/h | auto shift rpm | at km/h")
for gear = 1, #DR458.gearbox.ratios do
	local shift = shiftsByMode["1"][gear]
	local top = if gear < #DR458.gearbox.ratios
		then ("%.1f"):format(DriveSim.gearTop(DR458, gear, DT) / KMH)
		else "-"
	print(
		("%d | %.1f | %.1f | %s | %s | %s"):format(
			gear,
			gearSpeed(gear, 9000),
			gearSpeed(gear, DR458.engine.limiterRpm),
			top,
			if shift then ("%.0f"):format(shift.rpm) else "-",
			if shift then ("%.1f"):format(shift.kmh) else "-"
		)
	)
end
local topSpeed, topRpm, topGear = DriveSim.topSpeed(DR458, 250 * KMH, DT)
print(
	("Top speed: %.1f km/h in %d at %.0f rpm (from 250 km/h in 7th)"):format(topSpeed / KMH, topGear, topRpm)
)

print("")
print("Braking, manettino 1, pedal down at the speed shown | ABS on: m, peak g | ABS off: m, peak g")
local stops = { { kmh = 100, gear = 3 }, { kmh = 200, gear = 5 } }
for _, run in stops do
	local onDistance, onPeak, pedal = brake(run.kmh * KMH, run.gear, true)
	local offDistance, offPeak = brake(run.kmh * KMH, run.gear, false)
	print(
		("%.1f-0 km/h (in %d) | %.1f, %.2f | %.1f, %.2f"):format(
			pedal,
			run.gear,
			onDistance,
			onPeak,
			offDistance,
			offPeak
		)
	)
end
local reference = DriveSim.brake(DR458, 100 * KMH, DT, inputFor("1", {}))
local coasted = DriveSim.forwardSpeed(settle(100 * KMH, 3)) / KMH
print(
	("DriveSim.brake(100 km/h), as the calibration spec runs it: pedal at %.1f km/h, %.1f m"):format(
		coasted,
		reference.distance
	)
)

print("")
print("Lateral, assists off | g | body slip deg | downforce kg | steering at best | run ended on")
local skidpad = DriveSim.skidpad(DR458, 40, DT, "1")
print(("40 m skidpad, speed ramp (DriveSim.skidpad) | %.3f | - | - | - | -"):format(skidpad))
local turns = {
	{ kmh = 100, gear = 3, rate = 0.02 },
	{ kmh = 200, gear = 5, rate = 0.01 },
	{ kmh = 250, gear = 6, rate = 0.008 },
}
for _, run in turns do
	local g, slip, down, steer, ended = steadyTurn(run.kmh, run.gear, run.rate)
	print(
		("%d km/h, steering ramp | %.3f | %.1f | %.0f | %.2f | %s"):format(
			run.kmh,
			g,
			slip,
			down,
			steer,
			ended
		)
	)
end

print("")
print("Traction by position | 2nd from 50 km/h, 1.5 s full: rear slip mean / peak, TC share | power step")
for _, mode in DR458.modeOrder do
	local roll = rollOn(mode, 50, 2)
	local lateral, slip, rear = powerStep(mode, 60, 0.15)
	print(
		("%s | %.3f / %.3f, %.0f %% | %.2f g before, body slip peak %.1f deg, rear slip peak %.2f"):format(
			mode,
			roll.meanSlip,
			roll.peakSlip,
			roll.tcShare * 100,
			lateral,
			slip,
			rear
		)
	)
end

print("")
local ratios = { 0.04, 0.08, 0.16, 0.3, 0.6, 1, 2 }
local angles = { 2, 5.5, 8, 12, 20, 30, 45, 60 }
local front = Tyre.prepare(DR458.front.tyre, 1)
local rear = Tyre.prepare(DR458.rear.tyre, 1)
local function same(slip: number): number
	return slip
end
print(`Slip ratio | {table.concat(ratios, " | ")}`)
print(curveRow("Front Fx / peak", front.x, ratios, same))
print(curveRow("Rear Fx / peak", rear.x, ratios, same))
print(`Slip angle deg | {table.concat(angles, " | ")}`)
print(curveRow("Front Fy / peak", front.y, angles, math.rad))
print(curveRow("Rear Fy / peak", rear.y, angles, math.rad))
