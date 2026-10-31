--!strict
local DR458 = require("../src/shared/Config/Cars/DR458/Physics")
local DR458Switches = require("../src/shared/Config/Cars/DR458/Switches")
local DriveSim = require("../tools/DriveSim")
local PitLimiter = require("../src/shared/Rules/PitLimiter")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

-- The real car's rule (one source): 2nd gear, below the limit.
local STRICT: PitLimiter.Tuning =
	{ limitKmh = 60, armFromGear = 2, armToGear = 2, armBelowKmh = 60, band = 3, hazards = false }
-- Any forward gear, any speed.
local OPEN: PitLimiter.Tuning = { limitKmh = 60, armFromGear = 1, band = 3, hazards = false }

local function dr458Tuning(): PitLimiter.Tuning
	local tuning = DR458Switches.pitLimiter
	assert(tuning, "the DR458 has a pit limiter")
	return tuning
end

-- Runs the DR458 for `seconds` with the pedal flat and the limiter in `state`, the limiter
-- reading the gear and speed of the frame before as Controllers/Driving does. Returns the
-- lowest and highest speed (km/h) after `settle` seconds, and the gears seen then.
local function flatOut(
	sim: DriveSim.Sim,
	state: PitLimiter.State,
	tuning: PitLimiter.Tuning,
	gearboxMode: "auto" | "manual",
	seconds: number,
	settle: number
): (number, number, { [number]: true })
	local low, high, gears = math.huge, 0, {}
	while sim.time < seconds do
		local kmh = DriveSim.forwardSpeed(sim) * 3.6
		PitLimiter.update(state, tuning, sim.model.gearbox.gear)
		local input = DriveSim.input({
			throttle = PitLimiter.throttle(state, tuning, 1, kmh),
			gearboxMode = gearboxMode,
			drivingMode = "1",
			esc = false,
		})
		DriveSim.frame(sim, input, 1 / 60)
		if sim.time > settle then
			low, high = math.min(low, kmh), math.max(high, kmh)
			gears[sim.model.gearbox.gear] = true
		end
	end
	return low, high, gears
end

describe("PitLimiter", function()
	it("with the strict rule, arms only in 2nd below the limit", function()
		for _, case in { { 1, 40 }, { 3, 40 }, { 2, 60 }, { 2, 75 }, { -1, 10 }, { 0, 0 } } do
			local state = PitLimiter.newState()
			expect(PitLimiter.press(state, STRICT, case[1], case[2])).toBe(false)
		end
		local state = PitLimiter.newState()
		expect(PitLimiter.press(state, STRICT, 2, 59)).toBe(true)
	end)

	it("with the open rule, arms in any forward gear at any speed, never in neutral or reverse", function()
		for _, case in { { 1, 0 }, { 1, 30 }, { 2, 59 }, { 3, 75 }, { 6, 220 } } do
			local state = PitLimiter.newState()
			expect(PitLimiter.press(state, OPEN, case[1], case[2])).toBe(true)
		end
		for _, case in { { 0, 0 }, { -1, 5 } } do
			local state = PitLimiter.newState()
			expect(PitLimiter.press(state, OPEN, case[1], case[2])).toBe(false)
		end
	end)

	it("releases on a second press, or once the car is below its lowest arming gear", function()
		for _, case in { { STRICT, 2, 3, 1 }, { OPEN, 1, 6, 0 }, { OPEN, 3, 1, -1 } } do
			local tuning, armIn, keepIn, releaseIn = case[1], case[2], case[3], case[4]
			local state = PitLimiter.newState()
			PitLimiter.press(state, tuning, armIn, 40)
			expect(PitLimiter.press(state, tuning, keepIn, 40)).toBe(false)
			PitLimiter.press(state, tuning, armIn, 40)
			PitLimiter.update(state, tuning, keepIn)
			expect(state.armed).toBe(true)
			PitLimiter.update(state, tuning, releaseIn)
			expect(state.armed).toBe(false)
		end
	end)

	it("leaves the pedal alone unless armed; armed, it takes the throttle away over the band", function()
		local state = PitLimiter.newState()
		expect(PitLimiter.throttle(state, OPEN, 0.8, 100)).toBe(0.8)
		PitLimiter.press(state, OPEN, 2, 30)
		expect(PitLimiter.throttle(state, OPEN, 1, 50)).toBe(1)
		expect(PitLimiter.throttle(state, OPEN, 1, 58.5)).toBeNear(0.5, 1e-9)
		expect(PitLimiter.throttle(state, OPEN, 0.2, 58.5)).toBe(0.2)
		expect(PitLimiter.throttle(state, OPEN, 1, 60)).toBe(0)
		expect(PitLimiter.throttle(state, OPEN, 1, 140)).toBe(0)
	end)

	it("arms on the DR458 parked in 1st, as the car sits after its start", function()
		local tuning = dr458Tuning()
		local state = PitLimiter.newState()
		expect(PitLimiter.press(state, tuning, 1, 0)).toBe(true)
		expect(tuning.hazards).toBe(false)
	end)

	it("holds the DR458 at 60 km/h flat out from a standstill in auto (DriveSim, 60 FPS)", function()
		local tuning = dr458Tuning()
		local sim = DriveSim.new(DR458)
		local state = PitLimiter.newState()
		expect(PitLimiter.press(state, tuning, sim.model.gearbox.gear, 0)).toBe(true)
		local low, high = flatOut(sim, state, tuning, "auto", 20, 10)
		expect(state.armed).toBe(true)
		expect(low > tuning.limitKmh - 1.5).toBe(true)
		expect(high <= tuning.limitKmh + 0.5).toBe(true)
	end)

	it("holds the DR458 at 60 km/h flat out in 2nd, manual (DriveSim, 60 FPS)", function()
		local tuning = dr458Tuning()
		local sim = DriveSim.new(DR458)
		DriveSim.setSpeed(sim, 40 / 3.6, 2)
		local state = PitLimiter.newState()
		expect(PitLimiter.press(state, tuning, 2, 40)).toBe(true)
		local low, high = flatOut(sim, state, tuning, "manual", 15, 8)
		expect(low > tuning.limitKmh - 1.5).toBe(true)
		expect(high <= tuning.limitKmh + 0.5).toBe(true)
	end)

	it("armed at 140 km/h, gives no throttle until the DR458 is down to 60, then holds it", function()
		local tuning = dr458Tuning()
		local sim = DriveSim.new(DR458)
		DriveSim.setSpeed(sim, 140 / 3.6, 4)
		local state = PitLimiter.newState()
		expect(PitLimiter.press(state, tuning, 4, 140)).toBe(true)
		local before = DriveSim.forwardSpeed(sim)
		local slowing = true
		while sim.time < 3 do
			local kmh = DriveSim.forwardSpeed(sim) * 3.6
			expect(PitLimiter.throttle(state, tuning, 1, kmh)).toBe(0)
			flatOut(sim, state, tuning, "auto", sim.time + 1 / 60, math.huge)
			slowing = slowing and DriveSim.forwardSpeed(sim) < before
			before = DriveSim.forwardSpeed(sim)
		end
		expect(slowing).toBe(true)
		local low, high = flatOut(sim, state, tuning, "auto", 90, 70)
		expect(state.armed).toBe(true)
		expect(low > tuning.limitKmh - 1.5).toBe(true)
		expect(high <= tuning.limitKmh + 0.5).toBe(true)
	end)
end)
