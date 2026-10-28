--!strict
local CarAudioEvents = require("../src/shared/Rules/CarAudioEvents")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local TUNING: CarAudioEvents.Tuning = { liftFrom = 0.6, liftTo = 0.1, liftMinRpm = 5000, limiterHold = 0.15 }
local DT = 1 / 60

type Overrides = {
	rpm: number?,
	throttle: number?,
	gear: number?,
	shifting: boolean?,
	limiter: boolean?,
	tcActive: boolean?,
}

-- Fourth gear at 7,000 rpm, full throttle, nothing else going on, unless overridden.
local function car(overrides: Overrides?): CarAudioEvents.Readout
	local given: Overrides = overrides or {}
	return {
		rpm = given.rpm or 7000,
		throttle = given.throttle or 1,
		gear = given.gear or 4,
		shifting = given.shifting == true,
		limiter = given.limiter == true,
		tcActive = given.tcActive == true,
	}
end

describe("CarAudioEvents", function()
	it("reports a shift's cut on its first frame only", function()
		local state = CarAudioEvents.new(TUNING)
		expect(CarAudioEvents.step(state, car(), DT).cut).toBe(false)
		expect(CarAudioEvents.step(state, car({ shifting = true }), DT).cut).toBe(true)
		expect(CarAudioEvents.step(state, car({ shifting = true }), DT).cut).toBe(false)
	end)

	it("reports the gear that engaged and which way", function()
		local state = CarAudioEvents.new(TUNING)
		CarAudioEvents.step(state, car({ gear = 3 }), DT)
		expect(CarAudioEvents.step(state, car({ gear = 4 }), DT).gear).toBe("Up")
		expect(CarAudioEvents.step(state, car({ gear = 4 }), DT).gear).toBe(nil)
		expect(CarAudioEvents.step(state, car({ gear = 3 }), DT).gear).toBe("Down")
	end)

	it("fires once when an open throttle closes at high rpm", function()
		local state = CarAudioEvents.new(TUNING)
		CarAudioEvents.step(state, car(), DT)
		expect(CarAudioEvents.step(state, car({ throttle = 0.4 }), DT).lift).toBe(false)
		expect(CarAudioEvents.step(state, car({ throttle = 0 }), DT).lift).toBe(true)
		expect(CarAudioEvents.step(state, car({ throttle = 0 }), DT).lift).toBe(false)
	end)

	it("does not take a shift cut, traction control or a low-rpm lift for a lift", function()
		local closings: { Overrides } = {
			{ throttle = 0, shifting = true },
			{ throttle = 0, tcActive = true },
			{ throttle = 0, rpm = 4000 },
		}
		for _, closing in closings do
			local state = CarAudioEvents.new(TUNING)
			CarAudioEvents.step(state, car(), DT)
			expect(CarAudioEvents.step(state, car(closing), DT).lift).toBe(false)
		end
	end)

	it("holds the limiter across the bounce and releases it after the hold", function()
		local state = CarAudioEvents.new(TUNING)
		expect(CarAudioEvents.step(state, car({ limiter = true }), DT).limiter).toBe(true)
		local held = true
		for _ = 1, 6 do
			held = CarAudioEvents.step(state, car(), DT).limiter
		end
		expect(held).toBe(true)
		for _ = 1, 6 do
			held = CarAudioEvents.step(state, car(), DT).limiter
		end
		expect(held).toBe(false)
	end)

	it("pops only when the driver lifts off the limiter, not at its cuts", function()
		local state = CarAudioEvents.new(TUNING)
		CarAudioEvents.step(state, car({ rpm = 8000 }), DT)
		for frame = 1, 30 do
			local cut = frame % 2 == 0
			local events = CarAudioEvents.step(
				state,
				car({ rpm = 8700, limiter = cut, throttle = if cut then 0 else 1 }),
				DT
			)
			expect(events.lift).toBe(false)
		end
		local lifted = false
		for _ = 1, 20 do
			lifted = lifted or CarAudioEvents.step(state, car({ rpm = 8500, throttle = 0 }), DT).lift
		end
		expect(lifted).toBe(true)
	end)
end)
