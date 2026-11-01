--!strict
--[[
	The Boss 302 Laguna Seca driven on tools/DriveSim (issue #209): its numbers against the Ford and
	magazine data in the researcher's note (drive-lab-assets/boss302/research/references_data_vfx.md
	§1.10), and its H box in the car: the automatic shifting through the plan, the automatic clutch
	that never stalls, the player's clutch that does, the TracKey hooks and the frame rate.
]]
local Assists = require("../src/shared/Config/Cars/Boss302/Assists")
local Boss302 = require("../src/shared/Config/Cars/Boss302/Physics")
local Boss302Audio = require("../src/shared/Config/Cars/Boss302/Audio")
local CarAudioEvents = require("../src/shared/Rules/CarAudioEvents")
local Catalog = require("../src/shared/Config/Cars/Catalog")
local DriveSim = require("../tools/DriveSim")
local DriverAssists = require("../src/shared/Rules/DriverAssists")
local ExhaustFlames = require("../src/shared/Rules/ExhaustFlames")
local ExhaustPops = require("../src/shared/Rules/ExhaustPops")
local InputHelp = require("../src/shared/Config/InputHelp")
local Model = require("../src/shared/Vehicle/Model")
local Steering = require("../src/shared/Vehicle/Steering")
local T = require("../../../tools/test/T")
local Types = require("../src/shared/Config/Cars/Types")
local World = require("../src/shared/Config/World")

local describe, it, expect = T.describe, T.it, T.expect

local DT = 1 / 60
local KMH = 1 / 3.6
local MPH = 1.609344 / 3.6
local QUARTER_MILE = 402.336
-- The first foot of a road test's run, which MT and Edmunds take off their times as a drag strip does.
local ROLLOUT = 0.3048
local MANUAL = Boss302.gearbox.manual :: Types.ManualGearboxConfig

local function inputFor(mode: Types.DrivingMode, options: DriveSim.InputOptions): DriveSim.InputOptions
	local assists = DriverAssists.assists(false, mode, Assists)
	options.drivingMode = mode
	options.abs, options.tc, options.esc = assists.abs, assists.tc, assists.esc
	return options
end

-- A standing start flat out in `mode` (with TracKey's launch control armed on the brake first when
-- `launch`): the 0-60 mph time, the quarter mile's time and trap speed, all from rest, the time the
-- first foot took, and every frame's telemetry.
type Run =
	{ time60: number, quarter: number, trap: number, rollout: number, frames: { Types.CarConfig | any } }

local function standingStart(mode: Types.DrivingMode, launch: boolean, dt: number, seconds: number?): Run
	local sim = DriveSim.new(Boss302)
	if launch then
		local hold = DriveSim.input(inputFor(mode, { throttle = 1, brake = 1 }))
		while sim.time < 1.5 do
			DriveSim.frame(sim, hold, dt)
		end
	end
	local go = DriveSim.input(inputFor(mode, { throttle = 1 }))
	local start, startX = sim.time, sim.body.x
	local run: Run = { time60 = math.huge, quarter = math.huge, trap = 0, rollout = math.huge, frames = {} }
	while sim.time - start < (seconds or 20) do
		local before = DriveSim.forwardSpeed(sim)
		local result = DriveSim.frame(sim, go, dt)
		local after = DriveSim.forwardSpeed(sim)
		table.insert(run.frames, result.telemetry)
		if sim.body.x - startX >= ROLLOUT and run.rollout == math.huge then
			run.rollout = sim.time - start
		end
		if before < 60 * MPH and after >= 60 * MPH then
			run.time60 = sim.time - dt * (after - 60 * MPH) / (after - before) - start
		end
		if sim.body.x - startX >= QUARTER_MILE and run.quarter == math.huge then
			run.quarter, run.trap = sim.time - start, after
			if seconds == nil then
				break
			end
		end
	end
	return run
end

describe("Boss 302 against the data", function()
	it("tops 1st to 5th within 2 % under the speed the ratios give at 7,500 rpm (tyre slip)", function()
		local limiter = Boss302.engine.limiterRpm * 2 * math.pi / 60
		for gear = 1, 5 do
			local ratio = Boss302.gearbox.ratios[gear] * Boss302.driveline.rearReduction
			local share = DriveSim.gearTop(Boss302, gear, DT) / (limiter * Boss302.rear.tyre.radius / ratio)
			expect(share > 0.98 and share <= 1).toBe(true)
		end
	end)

	it("holds its 155 mph limit in 6th and never passes it (documented)", function()
		local sim = DriveSim.new(Boss302)
		DriveSim.setSpeed(sim, 240 * KMH, 6)
		local drive = DriveSim.input(inputFor("Normal", { throttle = 1, gearboxMode = "manual" }))
		local fastest = 0
		while sim.time < 30 do
			DriveSim.frame(sim, drive, DT)
			fastest = math.max(fastest, DriveSim.forwardSpeed(sim))
		end
		expect(fastest <= 155 * MPH).toBe(true)
		expect(DriveSim.forwardSpeed(sim) / KMH).toBeNear(249.4 - 1, 1.5)
	end)

	it(
		"grips at the rear as the front's compound on a wider, lighter-loaded tyre, in both directions",
		function()
			local front, rear = Boss302.front.tyre, Boss302.rear.tyre
			local exponent = 1 - front.loadSensitivity
			local share = (front.referenceLoad / rear.referenceLoad) ^ exponent * (285 / 255) ^ exponent
			expect(rear.peakMuX).toBeNear(front.peakMuX * share, 0.005)
			expect(rear.peakMuY).toBeNear(front.peakMuY * share, 0.005)
		end
	)

	it("holds 0.98 g ± 0.04 on a 200 ft skidpad, assists off (Edmunds, likely)", function()
		expect(DriveSim.skidpad(Boss302, 30.48, DT, "Normal")).toBeNear(0.98, 0.04)
	end)

	it(
		"stops from 60 mph in 32.0 m ± 1.5 and from 100 km/h in 33.3 m ± 1.5 (Edmunds, Sport Auto)",
		function()
			expect(DriveSim.brake(Boss302, 60 * MPH, DT, inputFor("Normal", {})).distance).toBeNear(32.0, 1.5)
			expect(DriveSim.brake(Boss302, 100 * KMH, DT, inputFor("Normal", {})).distance).toBeNear(
				33.3,
				1.5
			)
		end
	)

	it("traps the quarter mile at 112.9 mph ± 3 (Edmunds' LS, likely)", function()
		local run = standingStart("TracKey", true, DT)
		expect(run.trap / MPH).toBeNear(112.9, 3)
	end)

	it("runs 0-60 mph and the quarter mile in the road tests' range, timed as they time them", function()
		-- MT and Edmunds take the first foot off: 4.0 and 4.3 s to 60 mph, 12.3 and 12.7 s for the
		-- quarter mile; Edmunds also gives 4.6 s from rest. Each published to a tenth.
		local run = standingStart("TracKey", true, DT)
		local time60, quarter = run.time60 - run.rollout, run.quarter - run.rollout
		expect(time60 > 3.95 and time60 < 4.35).toBe(true)
		expect(quarter > 12.25 and quarter < 12.75).toBe(true)
		expect(run.time60 < 4.65).toBe(true)
	end)

	it("starts the same with the launch rpm 200 either way: 0-100 km/h within 3 %", function()
		local function tuned(rpm: number): Types.CarConfig
			local engine = table.clone(Boss302.engine)
			engine.launchRpm = rpm
			local car = table.clone(Boss302)
			car.engine = engine
			return car
		end
		local reference = DriveSim.launch(Boss302, DT).time100
		for _, rpm in { Boss302.engine.launchRpm - 200, Boss302.engine.launchRpm + 200 } do
			expect(DriveSim.launch(tuned(rpm), DT).time100 / reference).toBeNear(1, 0.03)
		end
	end)

	it("arms TracKey's launch control with ESC on, as Ford asks for nothing to be switched off", function()
		local sim = DriveSim.new(Boss302)
		local hold = DriveSim.input(inputFor("TracKey", { throttle = 1, brake = 1 }))
		expect(hold.assists.esc).toBe(true)
		local phase = "Off"
		while sim.time < 1 do
			phase = DriveSim.frame(sim, hold, DT).telemetry.launch
		end
		expect(phase).toBe("Armed")
		local normal = DriveSim.new(Boss302)
		local other = DriveSim.input(inputFor("Normal", { throttle = 1, brake = 1 }))
		while normal.time < 1 do
			phase = DriveSim.frame(normal, other, DT).telemetry.launch
		end
		expect(phase).toBe("Off")
	end)
end)

describe("Boss 302's H box in the car", function()
	it("shifts itself in auto through the plan: clutch down, hand on the knob, then the gear", function()
		local run = standingStart("Normal", false, DT, 7)
		local changes = 0
		for index = 2, #run.frames do
			local before, now = run.frames[index - 1], run.frames[index]
			if now.gear ~= before.gear then
				changes += 1
				expect(before.shifting).toBe(true)
				expect(before.clutchPedal >= MANUAL.bitePoint).toBe(true)
				expect(now.handAt).toBe(1)
				expect(now.shiftTo).toBe(now.gear)
			end
		end
		expect(changes >= 2).toBe(true)
	end)

	it(
		"holds the revs at the top of the clutch's slip band while the automatic clutch gets it moving",
		function()
			local hold = Boss302.engine.launchRpm * (1 + Boss302.gearbox.clutchSlipBand)
			local run = standingStart("Normal", false, DT, 1)
			local highest = 0
			for _, frame in run.frames do
				highest = math.max(highest, frame.rpm)
			end
			expect(highest < hold * 1.02).toBe(true)
			expect(highest > Boss302.engine.launchRpm).toBe(true)
		end
	)

	it("never locks the rear wheels on the automatic's downshifts braking from 100 km/h", function()
		local sim = DriveSim.new(Boss302)
		DriveSim.setSpeed(sim, 100 * KMH, 3)
		local stop = DriveSim.input(inputFor("TracKey", { brake = 1 }))
		local worst, gears = 0, {}
		while DriveSim.forwardSpeed(sim) > 3 do
			local result = DriveSim.frame(sim, stop, DT)
			gears[result.telemetry.gear] = true
			worst = math.min(worst, result.wheels[3].slipRatio, result.wheels[4].slipRatio)
		end
		expect(gears[1] and gears[2]).toBe(true)
		expect(worst > -0.3).toBe(true)
	end)

	it("breaks drive for under 0.2 s on each automatic upshift, as a modern automatic", function()
		local dt = 1 / 240
		local sim = DriveSim.new(Boss302)
		local go = DriveSim.input(inputFor("Normal", { throttle = 1 }))
		local started, longest, upshifts = nil :: number?, 0, 0
		while sim.time < 9 do
			local telemetry = DriveSim.frame(sim, go, dt).telemetry
			local cut = telemetry.clutch < 0.9 or telemetry.throttle < 0.05
			if telemetry.shifting and cut and started == nil then
				started = sim.time
			elseif started and not telemetry.shifting and not cut then
				longest = math.max(longest, sim.time - started)
				upshifts += 1
				started = nil
			end
		end
		expect(upshifts >= 3).toBe(true)
		expect(longest < 0.2).toBe(true)
	end)

	it("settles its yaw within 0.5 s when the steering is released at 160 km/h, ESC off", function()
		local function settle(throttle: number): number
			local sim = DriveSim.new(Boss302, InputHelp.keyboard)
			DriveSim.setSpeed(sim, 160 * KMH, 5)
			local function input(steer: number): Model.DriverInput
				return DriveSim.input(
					inputFor("Normal", { throttle = throttle, steer = steer, esc = false, tc = false })
				)
			end
			while sim.time < 1 do
				DriveSim.frame(sim, input(0), DT)
			end
			local released = sim.time + 1
			while sim.time < released do
				DriveSim.frame(sim, input(1), DT)
			end
			while sim.time < released + 3 do
				DriveSim.frame(sim, input(0), DT)
				if math.abs(sim.body.yawRate) < 0.02 then
					return sim.time - released
				end
			end
			return math.huge
		end
		expect(settle(1) < 0.5).toBe(true)
		expect(settle(0) < 1).toBe(true)
	end)

	it("leaves ESC alone turning in slowly to 0.45 g at 120 and 160 km/h, as the SVJ's does", function()
		-- The lateral g at which ESC first acts, the wheel turned in at a neutral car's 1 g in 8 s
		-- and the speed held on the throttle, in 6th, where Normal's automatic cruises at both.
		local function onset(kmh: number): number
			local speed = kmh * KMH
			local sim = DriveSim.new(Boss302)
			DriveSim.setSpeed(sim, speed, 6)
			local perInput = Steering.maxWheelAngle(Boss302.steering)
				/ Steering.ratio(Boss302.steering, speed)
			local oneG = Boss302.wheelbase * World.GRAVITY_MPS2 / (speed * speed) / perInput
			local throttle = 0.3
			while sim.time < 8 do
				throttle = math.clamp(throttle + (speed - DriveSim.forwardSpeed(sim)) * 5 * DT, 0, 1)
				local vx, vy, heading = sim.body.vx, sim.body.vy, sim.body.heading
				local frame = DriveSim.frame(
					sim,
					DriveSim.input(inputFor("Normal", { throttle = throttle, steer = oneG * sim.time / 8 })),
					DT
				)
				if frame.telemetry.escActive then
					local lateral = (sim.body.vy - vy) * math.cos(heading)
						- (sim.body.vx - vx) * math.sin(heading)
					return math.abs(lateral / DT) / World.GRAVITY_MPS2
				end
			end
			return math.huge
		end
		expect(onset(120) > 0.45).toBe(true)
		expect(onset(160) > 0.45).toBe(true)
	end)

	it("never stalls with the automatic clutch, braking to a stop in 6th or pulling away in it", function()
		local sim = DriveSim.new(Boss302)
		DriveSim.setSpeed(sim, 40 * KMH, 6)
		local stop = DriveSim.input(inputFor("Normal", { brake = 1, gearboxMode = "manual" }))
		local stalled, lowest = false, math.huge
		while sim.time < 6 do
			local result = DriveSim.frame(sim, stop, DT)
			stalled = stalled or result.telemetry.stalled
			if sim.time > 4 then
				lowest = math.min(lowest, result.telemetry.rpm)
			end
		end
		expect(stalled).toBe(false)
		expect(lowest > 0.9 * Boss302.engine.idleRpm).toBe(true)
		local go = DriveSim.input(inputFor("Normal", { throttle = 1, gearboxMode = "manual" }))
		local start = sim.time
		while sim.time - start < 5 do
			local frameStalled = DriveSim.frame(sim, go, DT).telemetry.stalled
			stalled = stalled or frameStalled
		end
		expect(stalled).toBe(false)
		expect(DriveSim.forwardSpeed(sim) > 10 * KMH).toBe(true)
	end)

	it("stalls with the player's clutch let up in gear at a standstill, and restarts with it down", function()
		local sim = DriveSim.new(Boss302)
		local up = DriveSim.input(inputFor("Normal", { gearboxMode = "manualClutch", clutchPedal = 0 }))
		local result = DriveSim.frame(sim, up, DT)
		while sim.time < 2 do
			result = DriveSim.frame(sim, up, DT)
		end
		expect(result.telemetry.stalled).toBe(true)
		expect(result.telemetry.rpm < 50).toBe(true)
		expect(Model.restart(sim.model, 0)).toBe(false)
		expect(Model.restart(sim.model, 1)).toBe(true)
		local down = DriveSim.input(inputFor("Normal", { gearboxMode = "manualClutch", clutchPedal = 1 }))
		local start = sim.time
		while sim.time - start < 2 do
			result = DriveSim.frame(sim, down, DT)
		end
		expect(result.telemetry.stalled).toBe(false)
		expect(result.telemetry.rpm).toBeNear(Boss302.engine.idleRpm, 60)
	end)

	it("pulls away on the player's clutch let up over 1.5 s at 40 % throttle, without stalling", function()
		local sim = DriveSim.new(Boss302)
		local stalled = false
		while sim.time < 3 do
			local pedal = math.clamp(1 - sim.time / 1.5, 0, 1)
			local input = DriveSim.input(
				inputFor("Normal", { gearboxMode = "manualClutch", clutchPedal = pedal, throttle = 0.4 })
			)
			local frameStalled = DriveSim.frame(sim, input, DT).telemetry.stalled
			stalled = stalled or frameStalled
		end
		expect(stalled).toBe(false)
		expect(DriveSim.forwardSpeed(sim) > 5 * KMH).toBe(true)
	end)

	it("pulls away when the clutch key is let go with the accelerator held, stalls without it", function()
		local function letGo(throttle: number): (boolean, number)
			-- On the keyboard's pedal ramps, the key held down since before the start.
			local sim = DriveSim.new(Boss302, InputHelp.keyboard)
			sim.model.controls.clutch = 1
			local stalled = false
			while sim.time < 4 do
				local key = if sim.time < 0.5 then 1 else 0
				local input = DriveSim.input(
					inputFor(
						"Normal",
						{ gearboxMode = "manualClutch", clutchPedal = key, throttle = throttle }
					)
				)
				local frameStalled = DriveSim.frame(sim, input, DT).telemetry.stalled
				stalled = stalled or frameStalled
			end
			return stalled, DriveSim.forwardSpeed(sim)
		end
		local stalled, speed = letGo(1)
		expect(stalled).toBe(false)
		expect(speed > 30 * KMH).toBe(true)
		expect((letGo(0))).toBe(true)
	end)

	it("works the clutch key's pedal as a foot does: down at once, let up over the release time", function()
		local sim = DriveSim.new(Boss302, InputHelp.keyboard)
		local pedal = 0
		while sim.time < 0.5 + InputHelp.keyboard.clutchReleaseTime / 2 do
			local key = if sim.time < 0.5 then 1 else 0
			local input =
				DriveSim.input(inputFor("Normal", { gearboxMode = "manualClutch", clutchPedal = key }))
			pedal = DriveSim.frame(sim, input, DT).telemetry.clutchPedal
			if sim.time >= 0.25 and sim.time < 0.25 + DT then
				expect(pedal).toBe(1)
			end
		end
		expect(pedal).toBeNear(0.5, 2 * DT / InputHelp.keyboard.clutchReleaseTime)
	end)

	it("idles TracKey's lopey idle higher than Normal's", function()
		local function idle(mode: Types.DrivingMode): number
			local sim = DriveSim.new(Boss302)
			sim.model.gearbox.gear, sim.model.gearbox.target = 0, 0
			local input = DriveSim.input(inputFor(mode, {}))
			local result = DriveSim.frame(sim, input, DT)
			while sim.time < 3 do
				result = DriveSim.frame(sim, input, DT)
			end
			return result.telemetry.rpm
		end
		expect(idle("Normal")).toBeNear(Boss302.engine.idleRpm, 60)
		expect(idle("TracKey")).toBeNear(Boss302.modes.TracKey.idleRpm :: number, 60)
	end)

	it("launches and brakes within 2 % of 240 FPS at 30, 60 and 120 FPS, as the SVJ must", function()
		local launch = DriveSim.launch(Boss302, 1 / 240)
		local brake = DriveSim.brake(Boss302, 100 * KMH, 1 / 240)
		for _, fps in { 30, 60, 120 } do
			local dt = 1 / fps
			local run = DriveSim.launch(Boss302, dt)
			expect(run.time100 / launch.time100).toBeNear(1, 0.02)
			expect(run.time200 / launch.time200).toBeNear(1, 0.02)
			expect(DriveSim.brake(Boss302, 100 * KMH, dt).distance / brake.distance).toBeNear(1, 0.02)
		end
	end)
end)

local function underEveryChance(): number
	return 0
end

-- One downshift from second to first asked of the H box, coasting off the throttle at `rpm`, with
-- every chance drawn as a pop: the Downshift pops it made and whether first engaged.
local function askFirst(mode: Types.DrivingMode, rpm: number): (number, boolean)
	local sim = DriveSim.new(Boss302)
	local ratio = Boss302.gearbox.ratios[2] * Boss302.driveline.rearReduction
	DriveSim.setSpeed(sim, rpm * 2 * math.pi / 60 / ratio * Boss302.rear.tyre.radius, 2)
	local events = CarAudioEvents.new(Boss302Audio.events)
	local pops = ExhaustPops.new(Boss302Audio.popTriggers)
	local count, engaged = 0, false
	for frame = 1, math.round(1.5 / DT) do
		local options = inputFor(mode, { gearboxMode = "manual", shiftDown = frame == 1 })
		local t = DriveSim.frame(sim, DriveSim.input(options), DT).telemetry
		local readout = {
			rpm = t.rpm,
			throttle = t.throttle,
			gear = t.gear,
			shifting = t.shifting,
			limiter = t.limiter,
			tcActive = t.tcActive,
		}
		local happened = CarAudioEvents.step(events, readout, DT)
		engaged = engaged or t.gear == 1
		if
			ExhaustPops.step(pops, happened, readout, mode, sim.time, underEveryChance)
			and pops.kind == "Downshift"
		then
			count += 1
		end
	end
	return count, engaged
end

describe("Boss 302's pops on the H box", function()
	it("keeps a downshift refused for over-revving silent in every mode, and pops an engaged one", function()
		for _, mode in Boss302.modeOrder do
			local refused, intoFirst = askFirst(mode, 6000)
			expect(intoFirst).toBe(false)
			expect(refused).toBe(0)
			local popped, engaged = askFirst(mode, 4000)
			expect(engaged).toBe(true)
			expect(popped > 0).toBe(true)
		end
	end)
end)

-- The unluckiest draw that still pops at a chance of 1.
local function highDraw(): number
	return 0.999
end

type Drive = { gearbox: "auto" | "manual", throttle: number, shiftAt: number? }

-- Pulls away from rest in `mode` for 25 s, the throttle held. The automatic box shifts itself; on the
-- H box an upshift is asked once the revs reach `shiftAt`. Returns the upshifts that engaged, the
-- Upshift pops and the flames they threw.
local function upshifts(mode: Types.DrivingMode, drive: Drive): (number, number, number)
	local sim = DriveSim.new(Boss302)
	local events = CarAudioEvents.new(Boss302Audio.events)
	local pops = ExhaustPops.new(Boss302Audio.popTriggers)
	local flames = Catalog.cars.Boss302.flames
	local engaged, cracks, thrown = 0, 0, 0
	local gear, asked, rpm = 1, false, 0
	while sim.time < 25 do
		local ask = drive.gearbox == "manual"
			and not asked
			and gear < 6
			and rpm >= (drive.shiftAt or math.huge)
		asked = asked or ask
		local options =
			inputFor(mode, { throttle = drive.throttle, gearboxMode = drive.gearbox, shiftUp = ask })
		local t = DriveSim.frame(sim, DriveSim.input(options), DT).telemetry
		local readout = {
			rpm = t.rpm,
			throttle = t.throttle,
			gear = t.gear,
			shifting = t.shifting,
			limiter = t.limiter,
			tcActive = t.tcActive,
		}
		local happened = CarAudioEvents.step(events, readout, DT)
		if t.gear > gear then
			engaged += 1
			asked = false
		end
		gear, rpm = t.gear, t.rpm
		if ExhaustPops.step(pops, happened, readout, mode, sim.time, highDraw) and pops.kind == "Upshift" then
			cracks += 1
			if ExhaustFlames.share(flames, mode, "Upshift", 1, highDraw) then
				thrown += 1
			end
		end
	end
	return engaged, cracks, thrown
end

describe("Boss 302's upshift cracks", function()
	it("cracks and throws a flame on every upshift, in every mode, on both gearboxes", function()
		local drives: { Drive } = {
			{ gearbox = "auto", throttle = 1 },
			{ gearbox = "auto", throttle = 0.5 },
			{ gearbox = "manual", throttle = 1, shiftAt = 6800 },
			{ gearbox = "manual", throttle = 0.6, shiftAt = 3500 },
			{ gearbox = "manual", throttle = 0.4, shiftAt = 2500 },
		}
		for _, mode in Boss302.modeOrder do
			for _, drive in drives do
				local engaged, cracks, thrown = upshifts(mode, drive)
				expect(engaged >= 3).toBe(true)
				expect(cracks).toBe(engaged)
				expect(thrown).toBe(engaged)
			end
		end
	end)
end)
