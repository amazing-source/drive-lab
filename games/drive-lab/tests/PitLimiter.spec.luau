--!strict
local DR458 = require("../src/shared/Config/Cars/DR458/Physics")
local DR458Switches = require("../src/shared/Config/Cars/DR458/Switches")
local DriveSim = require("../tools/DriveSim")
local PitLimiter = require("../src/shared/Rules/PitLimiter")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local TUNING: PitLimiter.Tuning = { limitKmh = 60, armGear = 2, armBelowKmh = 60, band = 3 }

describe("PitLimiter", function()
	it("arms only in the arming gear below the arming speed", function()
		for _, case in { { 1, 40 }, { 3, 40 }, { 2, 60 }, { 2, 75 }, { -1, 10 } } do
			local state = PitLimiter.newState()
			expect(PitLimiter.press(state, TUNING, case[1], case[2])).toBe(false)
		end
		local state = PitLimiter.newState()
		expect(PitLimiter.press(state, TUNING, 2, 59)).toBe(true)
	end)

	it("releases on a second press, or once the car is in a gear below the arming gear", function()
		local state = PitLimiter.newState()
		PitLimiter.press(state, TUNING, 2, 40)
		expect(PitLimiter.press(state, TUNING, 3, 70)).toBe(false)
		PitLimiter.press(state, TUNING, 2, 40)
		PitLimiter.update(state, TUNING, 3)
		expect(state.armed).toBe(true)
		PitLimiter.update(state, TUNING, 1)
		expect(state.armed).toBe(false)
	end)

	it("leaves the pedal alone unless armed, and armed takes the throttle away over the band", function()
		local state = PitLimiter.newState()
		expect(PitLimiter.throttle(state, TUNING, 0.8, 100)).toBe(0.8)
		PitLimiter.press(state, TUNING, 2, 30)
		expect(PitLimiter.throttle(state, TUNING, 1, 50)).toBe(1)
		expect(PitLimiter.throttle(state, TUNING, 1, 58.5)).toBeNear(0.5, 1e-9)
		expect(PitLimiter.throttle(state, TUNING, 0.2, 58.5)).toBe(0.2)
		expect(PitLimiter.throttle(state, TUNING, 1, 60)).toBe(0)
		expect(PitLimiter.throttle(state, TUNING, 1, 64)).toBe(0)
	end)

	it("holds the DR458 at its 60 km/h limit on full throttle in 2nd (DriveSim, 60 FPS)", function()
		local tuning = DR458Switches.pitLimiter
		assert(tuning, "the DR458 has a pit limiter")
		local sim = DriveSim.new(DR458)
		DriveSim.setSpeed(sim, 40 / 3.6, 2)
		local state = PitLimiter.newState()
		expect(PitLimiter.press(state, tuning, 2, 40)).toBe(true)
		local low, high = math.huge, 0
		while sim.time < 15 do
			local kmh = DriveSim.forwardSpeed(sim) * 3.6
			local throttle = PitLimiter.throttle(state, tuning, 1, kmh)
			local input = DriveSim.input({
				throttle = throttle,
				gearboxMode = "manual",
				drivingMode = "1",
				esc = false,
			})
			DriveSim.frame(sim, input, 1 / 60)
			if sim.time > 8 then
				low, high = math.min(low, kmh), math.max(high, kmh)
			end
		end
		expect(low > tuning.limitKmh - 1.5).toBe(true)
		expect(high <= tuning.limitKmh + 0.5).toBe(true)
	end)
end)
