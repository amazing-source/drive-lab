--!strict
--[[
	The Boss 302 Laguna Seca driven on tools/DriveSim (issue #209): its numbers against the Ford and
	magazine data in the researcher's note (drive-lab-assets/boss302/research/references_data_vfx.md
	§1.10), and its H box in the car: the automatic shifting through the plan, the automatic clutch
	that never stalls, the player's clutch that does, the TracKey hooks and the frame rate.
]]
local Assists = require("../src/shared/Config/Cars/Boss302/Assists")
local Boss302 = require("../src/shared/Config/Cars/Boss302/Physics")
local DriveSim = require("../tools/DriveSim")
local DriverAssists = require("../src/shared/Rules/DriverAssists")
local Model = require("../src/shared/Vehicle/Model")
local T = require("../../../tools/test/T")
local Types = require("../src/shared/Config/Cars/Types")

local describe, it, expect = T.describe, T.it, T.expect

local DT = 1 / 60
local KMH = 1 / 3.6
local MPH = 1.609344 / 3.6
local QUARTER_MILE = 402.336
local MANUAL = Boss302.gearbox.manual :: Types.ManualGearboxConfig

local function inputFor(mode: Types.DrivingMode, options: DriveSim.InputOptions): DriveSim.InputOptions
	local assists = DriverAssists.assists(false, mode, Assists)
	options.drivingMode = mode
	options.abs, options.tc, options.esc = assists.abs, assists.tc, assists.esc
	return options
end

-- A standing start flat out in `mode` (with TracKey's launch control armed on the brake first when
-- `launch`): the 0-60 mph time, the quarter mile's time and trap speed, and every frame's telemetry.
type Run = { time60: number, quarter: number, trap: number, frames: { Types.CarConfig | any } }

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
	local run: Run = { time60 = math.huge, quarter = math.huge, trap = 0, frames = {} }
	while sim.time - start < (seconds or 20) do
		local before = DriveSim.forwardSpeed(sim)
		local result = DriveSim.frame(sim, go, dt)
		local after = DriveSim.forwardSpeed(sim)
		table.insert(run.frames, result.telemetry)
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

	it("stays within 15 % of the slowest published 0-60 mph (4.6 s) and quarter mile (12.7 s)", function()
		-- Published 4.0-4.6 s and 12.3-12.7 s. The gap left is the human shift's torque break and the
		-- automatic clutch's start, reported on issue #209 rather than tuned away here.
		local run = standingStart("TracKey", true, DT)
		expect(run.time60 < 4.6 * 1.15).toBe(true)
		expect(run.quarter < 12.7 * 1.15).toBe(true)
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
