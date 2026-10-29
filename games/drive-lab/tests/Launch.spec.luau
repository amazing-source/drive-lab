--!strict
local DriveSim = require("../tools/DriveSim")
local Launch = require("../src/shared/Vehicle/Launch")
local SVJ = require("../src/shared/Config/Cars/SVJ")
local T = require("../../../tools/test/T")
local TyreSmoke = require("../src/shared/Rules/TyreSmoke")
local TyreSmokeConfig = require("../src/shared/Config/TyreSmoke")
local Types = require("../src/shared/Config/Cars/Types")

local describe, it, expect = T.describe, T.it, T.expect

local config = SVJ.launch
local STANDSTILL = SVJ.gearbox.selectorMaxSpeed

local function copy<V>(value: V): V
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, item in value :: any do
		result[key] = copy(item)
	end
	return result :: any
end

local function escOff(options: DriveSim.InputOptions): DriveSim.InputOptions
	options.tc, options.esc = false, false
	return options
end

-- Runs one frame of the rule on the given pedals, the car ready to arm (Corsa, ESC off, stopped
-- in first) unless told otherwise.
local function step(
	state: Launch.LaunchState,
	throttle: number,
	brake: number,
	speed: number?,
	selected: boolean?
)
	local chosen = if selected == nil then true else selected
	local ground = speed or 0
	Launch.update(config, state, chosen, chosen and ground < STANDSTILL, throttle, brake, 1, ground)
end

describe("Launch control: when it can arm", function()
	it("only in Corsa with ESC off, stopped in first and not mid-shift", function()
		local function can(
			mode: Types.DrivingMode,
			esc: boolean,
			gear: number,
			shifting: boolean,
			speed: number
		): boolean
			local input = DriveSim.input({ drivingMode = mode, tc = esc, esc = esc })
			return Launch.available(config, input, gear, shifting, speed, STANDSTILL)
		end
		expect(can("Corsa", false, 1, false, 0)).toBe(true)
		expect(can("Sport", false, 1, false, 0)).toBe(false)
		expect(can("Strada", false, 1, false, 0)).toBe(false)
		expect(can("Corsa", true, 1, false, 0)).toBe(false)
		expect(can("Corsa", false, 2, false, 0)).toBe(false)
		expect(can("Corsa", false, -1, false, 0)).toBe(false)
		expect(can("Corsa", false, 1, true, 0)).toBe(false)
		expect(can("Corsa", false, 1, false, STANDSTILL)).toBe(false)
	end)
end)

describe("Launch control: its phases", function()
	it("arms on the brake held and the accelerator floored, not on either alone", function()
		local state = Launch.newState()
		step(state, 1, 0)
		expect(state.phase).toBe("Off")
		step(state, 0, 1)
		expect(state.phase).toBe("Off")
		step(state, 0.9, 1)
		expect(state.phase).toBe("Off")
		step(state, 1, 1)
		expect(state.phase).toBe("Armed")
		local unavailable = Launch.newState()
		step(unavailable, 1, 1, nil, false)
		expect(unavailable.phase).toBe("Off")
	end)

	it("cancels when the accelerator lifts before the brake is released", function()
		local state = Launch.newState()
		step(state, 1, 1)
		step(state, 0.5, 1)
		expect(state.phase).toBe("Off")
		step(state, 0.5, 0)
		expect(state.phase).toBe("Off")
	end)

	it("launches when the brake is released with the accelerator still floored", function()
		local state = Launch.newState()
		step(state, 1, 1)
		step(state, 1, 0.3)
		expect(state.phase).toBe("Armed")
		step(state, 1, 0)
		expect(state.phase).toBe("Launching")
	end)

	it(
		"ends on a lift, the brake, out of Corsa or ESC on, out of first gear's range, or at the end speed",
		function()
			local function launched(): Launch.LaunchState
				local state = Launch.newState()
				step(state, 1, 1)
				step(state, 1, 0)
				return state
			end
			local running = launched()
			Launch.update(config, running, true, false, 1, 0, 2, config.endSpeed - 0.1)
			expect(running.phase).toBe("Launching")
			local cases = {
				{ throttle = 0.5, brake = 0, gear = 1, speed = 10, selected = true },
				{ throttle = 1, brake = 0.5, gear = 1, speed = 10, selected = true },
				{ throttle = 1, brake = 0, gear = 1, speed = 10, selected = false },
				{ throttle = 1, brake = 0, gear = 0, speed = 10, selected = true },
				{ throttle = 1, brake = 0, gear = 2, speed = config.endSpeed, selected = true },
			}
			for _, case in cases do
				local state = launched()
				Launch.update(
					config,
					state,
					case.selected,
					false,
					case.throttle,
					case.brake,
					case.gear,
					case.speed
				)
				expect(state.phase).toBe("Off")
			end
		end
	)
end)

type Run = {
	armedRpm: { min: number, max: number },
	smoke: number,
	meanSlip: number,
	tcActed: boolean,
	time100: number,
	endedAt: number?,
}

-- A start in Corsa with ESC off, held on the brake for 1.5 s when `held`, then full throttle.
local function corsaStart(car: Types.CarConfig, held: boolean, dt: number): (Run, DriveSim.Sim)
	local sim = DriveSim.new(car)
	local run: Run = {
		armedRpm = { min = math.huge, max = 0 },
		smoke = 0,
		meanSlip = 0,
		tcActed = false,
		time100 = math.huge,
		endedAt = nil,
	}
	if held then
		local hold = DriveSim.input(escOff({ throttle = 1, brake = 1, drivingMode = "Corsa" }))
		while sim.time < 1.5 do
			local result = DriveSim.frame(sim, hold, dt)
			if sim.time > 1 then
				run.armedRpm.min = math.min(run.armedRpm.min, result.telemetry.rpm)
				run.armedRpm.max = math.max(run.armedRpm.max, result.telemetry.rpm)
			end
		end
	end
	local go = DriveSim.input(escOff({ throttle = 1, drivingMode = "Corsa" }))
	local readings: { TyreSmoke.Wheel } = {}
	local slip, samples = 0, 0
	local start = sim.time
	while sim.time - start < 6 do
		local result = DriveSim.frame(sim, go, dt)
		TyreSmoke.measure(sim.model, result.wheels, readings)
		if sim.time - start <= 3 then
			for wheel = 3, 4 do
				run.smoke = math.max(run.smoke, TyreSmoke.share(readings[wheel], TyreSmokeConfig.THRESHOLDS))
			end
		end
		if result.telemetry.launch == "Launching" then
			for wheel = 1, 4 do
				slip += result.wheels[wheel].slipRatio
				samples += 1
			end
			run.tcActed = run.tcActed or result.telemetry.tcActive
		elseif held and run.endedAt == nil then
			run.endedAt = DriveSim.forwardSpeed(sim)
		end
		if run.time100 == math.huge and DriveSim.forwardSpeed(sim) >= config.endSpeed then
			run.time100 = sim.time - start
		end
	end
	run.meanSlip = if samples > 0 then slip / samples else math.huge
	return run, sim
end

describe("Launch control in the car", function()
	for _, fps in { 30, 60 } do
		it(
			`holds the launch rpm, then launches with no smoke and no slower than a plain start, at {fps} FPS`,
			function()
				local dt = 1 / fps
				local launch = corsaStart(SVJ, true, dt)
				local plain = corsaStart(SVJ, false, dt)
				expect(launch.armedRpm.min).toBeNear(SVJ.engine.launchRpm, 200)
				expect(launch.armedRpm.max).toBeNear(SVJ.engine.launchRpm, 200)
				expect(launch.smoke < 0.1).toBe(true)
				expect(plain.smoke > 0.9).toBe(true)
				expect(launch.meanSlip <= config.slipRatio).toBe(true)
				expect(launch.tcActed).toBe(true)
				expect(launch.time100 <= plain.time100).toBe(true)
				local ended = launch.endedAt
				assert(ended, "the launch ended")
				expect(ended).toBeNear(config.endSpeed, 1)
			end
		)
	end

	it("works the tyres at the launch's own slip, not the drive mode's", function()
		local tight = copy(SVJ) :: any
		tight.launch.slipRatio = 0.02
		local run = corsaStart(Types.define(tight), true, 1 / 60)
		expect(SVJ.modes.Corsa.tcSlipRatio > 0.1).toBe(true)
		expect(run.meanSlip <= 0.025).toBe(true)
	end)

	it("lets the automatic shift up during a launch only when the flag allows it", function()
		local _, shifting = corsaStart(SVJ, true, 1 / 60)
		expect(SVJ.launch.autoUpshift).toBe(true)
		expect(shifting.model.gearbox.gear >= 2).toBe(true)
		local held = copy(SVJ) :: any
		held.launch.autoUpshift = false
		local _, holding = corsaStart(Types.define(held), true, 1 / 60)
		expect(holding.model.gearbox.gear).toBe(1)
		expect(holding.model.launch.phase).toBe("Launching")
	end)
end)
