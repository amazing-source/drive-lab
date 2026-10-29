--!strict
local CarAudioEvents = require("../src/shared/Rules/CarAudioEvents")
local ExhaustPops = require("../src/shared/Rules/ExhaustPops")
local T = require("../../../tools/test/T")
local Types = require("../src/shared/Config/Cars/Types")

local describe, it, expect = T.describe, T.it, T.expect

local TUNING: ExhaustPops.Tuning = {
	liftChance = { Strada = 0.3, Sport = 0.8, Corsa = 1 },
	upshiftChance = { Strada = 0, Sport = 0.5, Corsa = 0.9 },
	downshiftChance = { Strada = 0.2, Sport = 0.7, Corsa = 1 },
	liftTrain = { from = 0.625, to = 1.25 },
	downshiftTrain = { from = 0.375, to = 0.75 },
	gap = { from = 0.125, to = 0.25 },
	upshiftMinRpm = 5000,
	minRpm = 3500,
	closedThrottle = 0.1,
}
-- Binary fractions throughout, so a pop on a frame boundary is not a rounding question.
local DT = 1 / 32

type Overrides = { rpm: number?, throttle: number?, gear: number? }

-- Third gear at 6,000 rpm with the throttle closed, unless overridden.
local function car(overrides: Overrides?): CarAudioEvents.Readout
	local given: Overrides = overrides or {}
	return {
		rpm = given.rpm or 6000,
		throttle = given.throttle or 0,
		gear = given.gear or 3,
		shifting = false,
		limiter = false,
		tcActive = false,
	}
end

local NOTHING: CarAudioEvents.Events = { cut = false, gear = nil, lift = false, limiter = false }
local DOWNSHIFT: CarAudioEvents.Events = { cut = false, gear = "Down", lift = false, limiter = false }
local UPSHIFT: CarAudioEvents.Events = { cut = false, gear = "Up", lift = false, limiter = false }
local CUT: CarAudioEvents.Events = { cut = true, gear = nil, lift = false, limiter = false }
local LIFT: CarAudioEvents.Events = { cut = false, gear = nil, lift = true, limiter = false }

local function always(value: number): () -> number
	return function()
		return value
	end
end

-- Pops over `seconds` of frames after `first`, every frame reading `after`.
local function count(
	state: ExhaustPops.State,
	first: CarAudioEvents.Events,
	start: CarAudioEvents.Readout,
	after: CarAudioEvents.Readout,
	mode: Types.DrivingMode,
	seconds: number,
	draw: () -> number
): number
	local pops = if ExhaustPops.step(state, first, start, mode, 0, draw) then 1 else 0
	for frame = 1, math.round(seconds / DT) do
		if ExhaustPops.step(state, NOTHING, after, mode, frame * DT, draw) then
			pops += 1
		end
	end
	return pops
end

describe("ExhaustPops", function()
	it("pops a train after a downshift with the throttle closed, above the floor", function()
		-- Draws of 0: a 0.375 s train, 0.125 s apart, so pops at 0, 0.125 and 0.25 s.
		local state = ExhaustPops.new(TUNING)
		expect(count(state, DOWNSHIFT, car(), car(), "Corsa", 0.5, always(0))).toBe(3)
	end)

	it("does not pop a downshift with the throttle open or under the floor", function()
		local cases: { Overrides } = { { throttle = 0.5 }, { rpm = 3000 } }
		for _, case in cases do
			local state = ExhaustPops.new(TUNING)
			expect(count(state, DOWNSHIFT, car(case), car(), "Corsa", 0.5, always(0))).toBe(0)
		end
	end)

	it("takes each drive mode's own chance", function()
		-- Draws of 0.6: Strada's 0.2 fails, and a 0.6 s train 0.2 s apart pops three times.
		local expected: { { mode: Types.DrivingMode, pops: number } } = {
			{ mode = "Strada", pops = 0 },
			{ mode = "Sport", pops = 3 },
			{ mode = "Corsa", pops = 3 },
		}
		for _, case in expected do
			local state = ExhaustPops.new(TUNING)
			expect(count(state, DOWNSHIFT, car(), car(), case.mode, 1, always(0.6))).toBe(case.pops)
		end
		local strada = ExhaustPops.new(TUNING)
		expect(ExhaustPops.step(strada, UPSHIFT, car({ rpm = 7000, throttle = 1 }), "Strada", 0, always(0))).toBe(false)
	end)

	it("cracks once as an upshift engages, from its rpm, and not at the shift's cut", function()
		local open = car({ rpm = 7000, throttle = 1 })
		local state = ExhaustPops.new(TUNING)
		expect(count(state, CUT, car({ rpm = 7000 }), car({ rpm = 7000 }), "Corsa", 0.5, always(0))).toBe(0)
		expect(count(state, UPSHIFT, open, open, "Corsa", 0.5, always(0))).toBe(1)
		local low = car({ rpm = 4000, throttle = 1 })
		expect(count(ExhaustPops.new(TUNING), UPSHIFT, low, low, "Corsa", 0.5, always(0))).toBe(0)
	end)

	it("stops a lift's train when the throttle opens or the overrun falls under the floor", function()
		-- Undisturbed, a 0.625 s train pops at 0, 0.125, 0.25, 0.375 and 0.5 s.
		expect(count(ExhaustPops.new(TUNING), LIFT, car(), car(), "Corsa", 1, always(0))).toBe(5)
		local endings: { Overrides } = { { throttle = 0.5 }, { rpm = 3000 } }
		for _, ending in endings do
			local state = ExhaustPops.new(TUNING)
			expect(ExhaustPops.step(state, LIFT, car(), "Corsa", 0, always(0))).toBe(true)
			expect(ExhaustPops.step(state, NOTHING, car(ending), "Corsa", 0.125, always(0))).toBe(false)
			expect(ExhaustPops.step(state, NOTHING, car(), "Corsa", 0.25, always(0))).toBe(false)
		end
	end)
end)
