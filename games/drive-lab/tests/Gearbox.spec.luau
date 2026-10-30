--!strict
local T = require("../../../tools/test/T")
local Engine = require("../src/shared/Vehicle/Engine")
local Gearbox = require("../src/shared/Vehicle/Gearbox")
local SVJ = require("../src/shared/Config/Cars/SVJ/Physics")

local describe, it, expect = T.describe, T.it, T.expect

local config, engine = SVJ.gearbox, SVJ.engine
local RPM = Engine.RAD_PER_RPM
local STEP = 0.001

local function context(overrides: { [string]: any }?): Gearbox.Context
	local base: Gearbox.Context = {
		engineSpeed = 3000 * RPM,
		outputSpeed = 3000 * RPM / config.ratios[2],
		engineTorque = 300,
		groundSpeed = 15,
		throttle = 0.3,
		brake = 0,
		mode = SVJ.modes.Corsa,
		gearboxMode = "manual",
		holdGear = false,
	}
	if overrides then
		for key, value in overrides do
			(base :: any)[key] = value
		end
	end
	return base
end

local function engaged(gear: number): Gearbox.GearboxState
	local state = Gearbox.newState()
	state.gear, state.target, state.autoClutch, state.launching = gear, gear, 1, false
	return state
end

-- Runs substeps until the shift ends; returns its time and whether torque was cut throughout
-- the opening and neutral phases.
local function runShift(state: Gearbox.GearboxState, ctx: Gearbox.Context): (number, boolean)
	local elapsed, cutWhileOpen = 0, true
	while Gearbox.isShifting(state) and elapsed < 1 do
		local cut = Gearbox.update(config, engine, state, ctx, STEP)
		if state.phase == "opening" or state.phase == "neutral" then
			cutWhileOpen = cutWhileOpen and cut
		end
		elapsed += STEP
	end
	return elapsed, cutWhileOpen
end

describe("Gearbox shifts", function()
	it("upshifts in the mode's time, cutting torque until the clutch closes again", function()
		local state = engaged(2)
		Gearbox.request(config, engine, state, true, false, context())
		local elapsed, cut = runShift(state, context())
		expect(elapsed).toBeNear(SVJ.modes.Corsa.upshiftTime, 2 * STEP)
		expect(cut).toBe(true)
		expect(state.gear).toBe(3)
	end)

	it("takes Strada's slower time for the same shift", function()
		local state = engaged(2)
		local strada = context({ mode = SVJ.modes.Strada })
		Gearbox.request(config, engine, state, true, false, strada)
		expect((runShift(state, strada))).toBeNear(SVJ.modes.Strada.upshiftTime, 2 * STEP)
	end)

	it("keeps the old ratio and opens the clutch before switching in neutral", function()
		local state = engaged(2)
		Gearbox.request(config, engine, state, true, false, context())
		local ctx = context()
		while state.phase ~= "neutral" do
			Gearbox.update(config, engine, state, ctx, STEP)
		end
		expect(state.gear).toBe(2)
		expect(Gearbox.clutchCapacity(config, state)).toBe(0)
		while state.phase == "neutral" do
			Gearbox.update(config, engine, state, ctx, STEP)
		end
		expect(state.gear).toBe(3)
	end)

	it("blips toward the lower gear's speed during a downshift", function()
		local state = engaged(3)
		local ctx = context({ outputSpeed = 3000 * RPM / config.ratios[3], throttle = 0 })
		Gearbox.request(config, engine, state, false, true, ctx)
		local blipped = 0
		while Gearbox.isShifting(state) do
			local _, blip = Gearbox.update(config, engine, state, ctx, STEP)
			blipped = math.max(blipped, blip)
		end
		expect(blipped).toBe(1)
		expect(state.gear).toBe(2)
	end)

	it("refuses a downshift that would over-rev", function()
		local state = engaged(3)
		local fast = context({ outputSpeed = 8000 * RPM / config.ratios[3] })
		Gearbox.request(config, engine, state, false, true, fast)
		expect(Gearbox.isShifting(state)).toBe(false)
		expect(state.gear).toBe(3)
	end)
end)

describe("Gearbox automatic", function()
	it("upshifts near the mode's full-throttle point and does not hunt back", function()
		local state = engaged(1)
		local full = SVJ.modes.Corsa.upshiftRpm.full
		local below = context({
			gearboxMode = "auto",
			throttle = 1,
			outputSpeed = (full - 50) * RPM / config.ratios[1],
		})
		Gearbox.update(config, engine, state, below, STEP)
		expect(Gearbox.isShifting(state)).toBe(false)
		local above = context({
			gearboxMode = "auto",
			throttle = 1,
			outputSpeed = (full + 50) * RPM / config.ratios[1],
		})
		Gearbox.update(config, engine, state, above, STEP)
		expect(Gearbox.isShifting(state)).toBe(true)
		runShift(state, above)
		expect(state.gear).toBe(2)
		Gearbox.update(config, engine, state, above, STEP)
		expect(Gearbox.isShifting(state)).toBe(false)
	end)

	it("drops a gear on a closed throttle once below the light downshift point", function()
		local state = engaged(4)
		local slow = (SVJ.modes.Corsa.downshiftRpm.light - 100) * RPM / config.ratios[4]
		Gearbox.update(
			config,
			engine,
			state,
			context({ gearboxMode = "auto", throttle = 0, outputSpeed = slow }),
			STEP
		)
		expect(state.target).toBe(3)
	end)

	it("holds off a downshift for the hold after an upshift, but never one under braking", function()
		local mode = SVJ.modes.Sport
		local under = (mode.downshiftRpm.full - 200) * RPM / config.ratios[2]
		local floored = context({ gearboxMode = "auto", throttle = 1, mode = mode, outputSpeed = under })
		local state = engaged(2)
		state.sinceUpshift = 0
		local held = 0
		while held < config.upshiftHoldTime - 2 * STEP do
			Gearbox.update(config, engine, state, floored, STEP)
			held += STEP
		end
		expect(state.target).toBe(2)
		Gearbox.update(config, engine, state, floored, 3 * STEP)
		expect(state.target).toBe(1)

		local braking = engaged(2)
		braking.sinceUpshift = 0
		local slow = context({
			gearboxMode = "auto",
			throttle = 0,
			brake = 1,
			mode = mode,
			outputSpeed = (mode.brakeDownshiftRpm - 200) * RPM / config.ratios[2],
		})
		Gearbox.update(config, engine, braking, slow, STEP)
		expect(braking.target).toBe(1)
	end)

	it("starts the hold with every upshift", function()
		local state = engaged(2)
		expect(state.sinceUpshift >= config.upshiftHoldTime).toBe(true)
		Gearbox.request(config, engine, state, true, false, context())
		expect(state.sinceUpshift).toBe(0)
		local down = engaged(3)
		down.sinceUpshift = 5
		Gearbox.request(
			config,
			engine,
			down,
			false,
			true,
			context({ outputSpeed = 3000 * RPM / config.ratios[3] })
		)
		expect(down.sinceUpshift).toBe(5)
	end)

	it("in manual, drops a gear only to avoid falling under idle", function()
		local state = engaged(3)
		local low = context({ outputSpeed = (engine.idleRpm + 100) * RPM / config.ratios[3] })
		Gearbox.update(config, engine, state, low, STEP)
		expect(Gearbox.isShifting(state)).toBe(false)
		local under = context({ outputSpeed = (engine.idleRpm - 100) * RPM / config.ratios[3] })
		Gearbox.update(config, engine, state, under, STEP)
		expect(state.target).toBe(2)
	end)
end)

describe("Gearbox selector", function()
	it("goes 1, N, R on downshifts only at a standstill, and back on upshifts", function()
		local state = engaged(1)
		local stopped = context({ groundSpeed = 0, outputSpeed = 0 })
		Gearbox.request(config, engine, state, false, true, stopped)
		expect(state.gear).toBe(0)
		Gearbox.request(config, engine, state, false, true, stopped)
		expect(state.gear).toBe(-1)
		expect(Gearbox.ratio(config, state.gear) < 0).toBeTruthy()
		Gearbox.request(config, engine, state, true, false, stopped)
		Gearbox.request(config, engine, state, true, false, stopped)
		expect(state.gear).toBe(1)
		Gearbox.request(config, engine, state, false, true, context({ groundSpeed = 5 }))
		expect(state.gear).toBe(1)
	end)

	it("selects reverse or first straight away near a standstill, never rolling or mid-shift", function()
		local state = engaged(1)
		expect(Gearbox.select(config, state, -1, config.selectorMaxSpeed)).toBe(false)
		expect(state.gear).toBe(1)
		expect(Gearbox.select(config, state, -1, 0)).toBe(true)
		expect(state.gear).toBe(-1)
		expect(state.target).toBe(-1)
		expect(Gearbox.isShifting(state)).toBe(false)
		expect(Gearbox.select(config, state, 1, 0)).toBe(true)
		expect(state.gear).toBe(1)
		local shifting = engaged(2)
		Gearbox.request(config, engine, shifting, false, true, context({ groundSpeed = 0, outputSpeed = 0 }))
		expect(Gearbox.select(config, shifting, -1, 0)).toBe(false)
		expect(shifting.target).toBe(1)
	end)
end)

describe("Gearbox reverse top speed", function()
	it("lets the whole throttle through until the last band before the top speed, none from it", function()
		local max, band = config.reverseMaxSpeed, config.reverseCutBand
		expect(max).toBeNear(40 / 3.6, 1e-9)
		expect(Gearbox.reverseCut(config, -1, 0)).toBe(1)
		expect(Gearbox.reverseCut(config, -1, 2)).toBe(1)
		expect(Gearbox.reverseCut(config, -1, -(max - band))).toBeNear(1, 1e-9)
		expect(Gearbox.reverseCut(config, -1, -(max - band / 2))).toBeNear(0.5, 1e-9)
		expect(Gearbox.reverseCut(config, -1, -max)).toBe(0)
		expect(Gearbox.reverseCut(config, -1, -max - 5)).toBe(0)
	end)

	it("leaves the forward gears and neutral alone", function()
		expect(Gearbox.reverseCut(config, 1, 80)).toBe(1)
		expect(Gearbox.reverseCut(config, 1, -config.reverseMaxSpeed - 5)).toBe(1)
		expect(Gearbox.reverseCut(config, 0, -config.reverseMaxSpeed - 5)).toBe(1)
	end)
end)

describe("Gearbox clutch", function()
	it("stays open while the brake holds a stopped car", function()
		local state = Gearbox.newState()
		local held =
			context({ groundSpeed = 0, outputSpeed = 0, brake = 1, throttle = 1, engineSpeed = 5000 * RPM })
		for _ = 1, 500 do
			Gearbox.update(config, engine, state, held, STEP)
		end
		expect(state.holding).toBe(true)
		expect(state.engagement).toBe(0)
	end)

	it("slips to carry the engine's torque at the launch speed at full throttle", function()
		local state = Gearbox.newState()
		local launch = context({
			groundSpeed = 2,
			outputSpeed = 10,
			throttle = 1,
			engineSpeed = engine.launchRpm * RPM,
			engineTorque = 675,
		})
		for _ = 1, 500 do
			Gearbox.update(config, engine, state, launch, STEP)
		end
		expect(Gearbox.clutchCapacity(config, state)).toBeNear(675, 1)
	end)

	it("closes fully once the gearbox input reaches the launch speed, and stays closed", function()
		local state = Gearbox.newState()
		local caught = context({
			throttle = 1,
			engineSpeed = engine.launchRpm * RPM,
			outputSpeed = engine.launchRpm * RPM / config.ratios[1],
		})
		for _ = 1, 500 do
			Gearbox.update(config, engine, state, caught, STEP)
		end
		expect(state.engagement).toBe(1)
		local cruise =
			context({ throttle = 0.2, engineSpeed = 2500 * RPM, outputSpeed = 2500 * RPM / config.ratios[1] })
		Gearbox.update(config, engine, state, cruise, STEP)
		expect(state.engagement).toBe(1)
	end)
end)
