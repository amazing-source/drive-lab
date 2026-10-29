--!strict
local DriveSim = require("../tools/DriveSim")
local Gearbox = require("../src/shared/Vehicle/Gearbox")
local InputHelp = require("../src/shared/Config/InputHelp")
local Interface = require("../src/shared/Vehicle/Interface")
local Selector = require("../src/shared/Vehicle/Selector")
local SVJ = require("../src/shared/Config/Cars/SVJ")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local config = SVJ.gearbox
local keyboard = InputHelp.keyboard
local HOLD = InputHelp.REVERSE_HOLD_SECONDS
local DT = 1 / 60

local function engaged(gear: number): Gearbox.GearboxState
	local state = Gearbox.newState()
	state.gear, state.target, state.autoClutch, state.launching = gear, gear, 1, false
	return state
end

-- Feeds `seconds` of one input to the selector at `speed`, frame by frame.
local function hold(
	gearbox: Gearbox.GearboxState,
	selector: Selector.SelectorState,
	input: Interface.DriverInput,
	speed: number,
	seconds: number,
	help: InputHelp.InputHelp?
)
	for _ = 1, math.round(seconds / DT) do
		Selector.update(help or keyboard, config, gearbox, selector, input, speed, false, DT)
	end
end

describe("Selector: the automatic's reverse on the pedals", function()
	it("selects reverse once the brake has been held on its own for the hold at a standstill", function()
		local gearbox, selector = engaged(1), Selector.newState()
		local brake = DriveSim.input({ brake = 1 })
		hold(gearbox, selector, brake, 0, HOLD - 2 * DT)
		expect(gearbox.gear).toBe(1)
		hold(gearbox, selector, brake, 0, 3 * DT)
		expect(gearbox.gear).toBe(-1)
		expect(gearbox.target).toBe(-1)
	end)

	it("never selects reverse while rolling, and counts the hold only from the standstill", function()
		local gearbox, selector = engaged(1), Selector.newState()
		local brake = DriveSim.input({ brake = 1 })
		hold(gearbox, selector, brake, 5, 3)
		hold(gearbox, selector, brake, config.selectorMaxSpeed, 3)
		expect(gearbox.gear).toBe(1)
		hold(gearbox, selector, brake, 0, HOLD - 2 * DT)
		expect(gearbox.gear).toBe(1)
	end)

	it("restarts the hold whenever the brake is let go", function()
		local gearbox, selector = engaged(1), Selector.newState()
		for _ = 1, 10 do
			hold(gearbox, selector, DriveSim.input({ brake = 1 }), 0, HOLD - 2 * DT)
			hold(gearbox, selector, DriveSim.input({}), 0, DT)
		end
		expect(gearbox.gear).toBe(1)
	end)

	it("selects no reverse on the brake while launch control can arm", function()
		local gearbox, selector = engaged(1), Selector.newState()
		local brake = DriveSim.input({ brake = 1 })
		for _ = 1, math.round(3 / DT) do
			Selector.update(keyboard, config, gearbox, selector, brake, 0, true, DT)
		end
		expect(gearbox.gear).toBe(1)
		Selector.update(keyboard, config, gearbox, selector, brake, 0, false, DT)
		expect(gearbox.gear).toBe(1)
		hold(gearbox, selector, brake, 0, HOLD + DT)
		expect(gearbox.gear).toBe(-1)
	end)

	it("selects nothing while both pedals are down", function()
		local forward, selector = engaged(1), Selector.newState()
		local both = DriveSim.input({ brake = 1, throttle = 1 })
		hold(forward, selector, both, 0, 3)
		expect(forward.gear).toBe(1)
		local reverse = engaged(-1)
		hold(reverse, selector, both, 0, 3)
		expect(reverse.gear).toBe(-1)
	end)

	it("selects first again from reverse on the accelerator held on its own at a standstill", function()
		local gearbox, selector = engaged(-1), Selector.newState()
		local throttle = DriveSim.input({ throttle = 1 })
		hold(gearbox, selector, throttle, 3, 3)
		expect(gearbox.gear).toBe(-1)
		hold(gearbox, selector, throttle, 0, HOLD + DT)
		expect(gearbox.gear).toBe(1)
	end)

	it("leaves manual and neutral to the paddles", function()
		local manual, selector = engaged(1), Selector.newState()
		hold(manual, selector, DriveSim.input({ brake = 1, gearboxMode = "manual" }), 0, 3)
		expect(manual.gear).toBe(1)
		local manualReverse = engaged(-1)
		hold(manualReverse, selector, DriveSim.input({ throttle = 1, gearboxMode = "manual" }), 0, 3)
		expect(manualReverse.gear).toBe(-1)
		local neutral = engaged(0)
		hold(neutral, selector, DriveSim.input({ brake = 1 }), 0, 3)
		hold(neutral, selector, DriveSim.input({ throttle = 1 }), 0, 3)
		expect(neutral.gear).toBe(0)
	end)

	it("waits for a shift to end before it selects", function()
		local gearbox, selector = engaged(2), Selector.newState()
		gearbox.phase, gearbox.target = "neutral", 1
		hold(gearbox, selector, DriveSim.input({ brake = 1 }), 0, 1)
		expect(gearbox.gear).toBe(2)
		gearbox.phase, gearbox.gear = "engaged", 1
		hold(gearbox, selector, DriveSim.input({ brake = 1 }), 0, DT)
		expect(gearbox.gear).toBe(-1)
	end)

	it("swaps the pedals in automatic reverse only", function()
		local out = { steer = 0, throttle = 0, brake = 0, handbrake = 0 }
		local input = DriveSim.input({ throttle = 0.25, brake = 0.75, steer = 0.5, handbrake = 1 })
		local swapped = Selector.pedals(keyboard, engaged(-1), input, out)
		expect(swapped.throttle).toBe(0.75)
		expect(swapped.brake).toBe(0.25)
		expect(swapped.steer).toBe(0.5)
		expect(swapped.handbrake).toBe(1)
		local forward = Selector.pedals(keyboard, engaged(1), input, out)
		expect(forward.throttle).toBe(0.25)
		expect(forward.brake).toBe(0.75)
		local manual = DriveSim.input({ throttle = 0.25, brake = 0.75, gearboxMode = "manual" })
		expect(Selector.pedals(keyboard, engaged(-1), manual, out).throttle).toBe(0.25)
		expect(Selector.pedals(InputHelp.gamepad, engaged(-1), input, out).throttle).toBe(0.75)
	end)

	it("selects nothing and swaps nothing for a preset without the hold", function()
		local gearbox, selector = engaged(1), Selector.newState()
		hold(gearbox, selector, DriveSim.input({ brake = 1 }), 0, 3, InputHelp.direct)
		expect(gearbox.gear).toBe(1)
		local out = { steer = 0, throttle = 0, brake = 0, handbrake = 0 }
		local input = DriveSim.input({ throttle = 0.25, brake = 0.75 })
		expect(Selector.pedals(InputHelp.direct, engaged(-1), input, out).throttle).toBe(0.25)
	end)
end)

-- The whole car on the keyboard preset, as Controllers/Driving drives it.
describe("Selector in the car", function()
	it("brakes to a stop on the brake key, then backs up on it after the hold", function()
		local sim = DriveSim.new(SVJ, keyboard)
		DriveSim.setSpeed(sim, 40 / 3.6, 2)
		local stoppedAt, selectedAt, fastest = nil :: number?, nil :: number?, 0
		for _ = 1, math.round(6 / DT) do
			DriveSim.frame(sim, DriveSim.input({ brake = 1 }), DT)
			local speed = DriveSim.forwardSpeed(sim)
			if stoppedAt == nil and math.abs(speed) < config.selectorMaxSpeed then
				stoppedAt = sim.time
			end
			if selectedAt == nil and sim.model.gearbox.gear < 0 then
				selectedAt = sim.time
				fastest = speed
			end
		end
		assert(stoppedAt and selectedAt, "the car stopped and reverse was selected")
		expect(selectedAt - stoppedAt >= HOLD - 1e-9).toBe(true)
		expect(math.abs(fastest) < config.selectorMaxSpeed).toBe(true)
		expect(DriveSim.forwardSpeed(sim) < -3).toBe(true)
	end)

	it(
		"in reverse brakes on the accelerator key, then selects drive at a standstill and drives forward",
		function()
			local sim = DriveSim.new(SVJ, keyboard)
			for _ = 1, math.round(2.5 / DT) do
				DriveSim.frame(sim, DriveSim.input({ brake = 1 }), DT)
			end
			expect(DriveSim.forwardSpeed(sim) < -3).toBe(true)
			for _ = 1, math.round(0.3 / DT) do
				DriveSim.frame(sim, DriveSim.input({ throttle = 1 }), DT)
			end
			expect(sim.model.gearbox.gear).toBe(-1)
			expect(sim.model.controls.brake).toBe(1)
			expect(sim.model.controls.throttle).toBe(0)
			local selectedAt: number? = nil
			for _ = 1, math.round(5 / DT) do
				DriveSim.frame(sim, DriveSim.input({ throttle = 1 }), DT)
				if selectedAt == nil and sim.model.gearbox.gear > 0 then
					selectedAt = DriveSim.forwardSpeed(sim)
				end
			end
			assert(selectedAt, "drive was selected")
			expect(math.abs(selectedAt) < config.selectorMaxSpeed).toBe(true)
			expect(DriveSim.forwardSpeed(sim) > 3).toBe(true)
		end
	)

	it(
		"tops out in reverse under the top speed, on the brake key in automatic and the accelerator in manual",
		function()
			local max, band = config.reverseMaxSpeed, config.reverseCutBand
			for _, dt in { 1 / 30, 1 / 60 } do
				for _, manual in { false, true } do
					local sim = DriveSim.new(SVJ, keyboard)
					local mode: "auto" | "manual" = if manual then "manual" else "auto"
					if manual then
						DriveSim.frame(sim, DriveSim.input({ shiftDown = true, gearboxMode = mode }), dt)
						DriveSim.frame(sim, DriveSim.input({ gearboxMode = mode }), dt)
						DriveSim.frame(sim, DriveSim.input({ shiftDown = true, gearboxMode = mode }), dt)
					end
					local input = if manual
						then DriveSim.input({ throttle = 1, gearboxMode = mode })
						else DriveSim.input({ brake = 1 })
					local fastest = 0
					for _ = 1, math.round(10 / dt) do
						DriveSim.frame(sim, input, dt)
						fastest = math.min(fastest, DriveSim.forwardSpeed(sim))
					end
					expect(sim.model.gearbox.gear).toBe(-1)
					expect(-fastest <= max).toBe(true)
					expect(-DriveSim.forwardSpeed(sim) >= max - band).toBe(true)
				end
			end
		end
	)

	it(
		"in Corsa with ESC off the brake arms nothing and selects no reverse; in Sport it selects reverse",
		function()
			local function held(mode: "Corsa" | "Sport"): DriveSim.Sim
				local sim = DriveSim.new(SVJ, keyboard)
				for _ = 1, math.round(3 / DT) do
					DriveSim.frame(
						sim,
						DriveSim.input({ brake = 1, drivingMode = mode, tc = false, esc = false }),
						DT
					)
				end
				return sim
			end
			local corsa = held("Corsa")
			expect(corsa.model.gearbox.gear).toBe(1)
			expect(corsa.model.launch.phase).toBe("Off")
			expect(math.abs(DriveSim.forwardSpeed(corsa)) < 0.05).toBe(true)
			expect(held("Sport").model.gearbox.gear).toBe(-1)
		end
	)

	it("in manual only brakes at a standstill, and the downshift paddle still steps to reverse", function()
		local sim = DriveSim.new(SVJ, keyboard)
		for _ = 1, math.round(2 / DT) do
			DriveSim.frame(sim, DriveSim.input({ brake = 1, gearboxMode = "manual" }), DT)
		end
		expect(sim.model.gearbox.gear).toBe(1)
		expect(math.abs(DriveSim.forwardSpeed(sim)) < 0.05).toBe(true)
		DriveSim.frame(sim, DriveSim.input({ shiftDown = true, gearboxMode = "manual" }), DT)
		DriveSim.frame(sim, DriveSim.input({ gearboxMode = "manual" }), DT)
		DriveSim.frame(sim, DriveSim.input({ shiftDown = true, gearboxMode = "manual" }), DT)
		expect(sim.model.gearbox.gear).toBe(-1)
		for _ = 1, math.round(2 / DT) do
			DriveSim.frame(sim, DriveSim.input({ throttle = 0.5, gearboxMode = "manual" }), DT)
		end
		expect(DriveSim.forwardSpeed(sim) < -2).toBe(true)
	end)
end)
