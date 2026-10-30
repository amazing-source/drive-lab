--!strict
local CarShake = require("../src/shared/Rules/CarShake")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local VIEW = { road = 1, engine = 1, launch = 1, shift = 1, lift = 0 }
local KICK = { road = 0, engine = 0, launch = 0, shift = 1, lift = 0 }
local TUNING: CarShake.Tuning = {
	road = { base = 0.03, gain = 0.12, exponent = 1.5, topKmh = 350, hz = { 12, 22 } },
	engine = { degrees = { 0.015, 0.04 }, hz = 25, fadeKmh = { 40, 100 } },
	launch = { degrees = 0.6, fromG = 0.4, toG = 1.0, fadeKmh = 80, hz = 9 },
	shift = {
		down = 0.4,
		up = 0.3,
		dip = 0.06,
		rise = 0.15,
		settle = 0.15,
	},
	-- The cockpit takes only the kick, so the kick can be read exactly; the others take all.
	views = { Chase = VIEW, Cockpit = KICK, Hood = VIEW },
	scale = 1,
}

local function input(gear: number, shiftScale: number?): CarShake.Input
	return {
		view = "Cockpit",
		speedKmh = 0,
		throttle = 0,
		longitudinalG = 0,
		gear = gear,
		shiftScale = shiftScale or 1,
	}
end

describe("CarShake", function()
	it("leaves a car at rest still, and vibrates more with speed up to its top", function()
		expect(CarShake.roadDegrees(0, TUNING)).toBe(0)
		expect(CarShake.roadDegrees(20, TUNING) > 0.03).toBe(true)
		expect(CarShake.roadDegrees(175, TUNING)).toBeNear(0.03 + 0.12 * 0.5 ^ 1.5, 1e-12)
		expect(CarShake.roadDegrees(350, TUNING)).toBeNear(0.15, 1e-12)
		expect(CarShake.roadDegrees(900, TUNING)).toBeNear(0.15, 1e-12)
		expect(CarShake.roadDegrees(-175, TUNING)).toBeNear(CarShake.roadDegrees(175, TUNING), 1e-12)
		expect(CarShake.roadDegrees(0 / 0, TUNING)).toBe(0)
	end)

	it("rocks with the throttle at low speed, the road taking over by 100 km/h", function()
		expect(CarShake.engineDegrees(0, 0, TUNING)).toBeNear(0.015, 1e-12)
		expect(CarShake.engineDegrees(1, 0, TUNING)).toBeNear(0.04, 1e-12)
		expect(CarShake.engineDegrees(1, 70, TUNING)).toBeNear(0.02, 1e-12)
		expect(CarShake.engineDegrees(1, 100, TUNING)).toBe(0)
	end)

	it("rumbles on a hard launch only, fading with speed", function()
		expect(CarShake.launchDegrees(0.3, 0, TUNING)).toBe(0)
		expect(CarShake.launchDegrees(1, 0, TUNING)).toBeNear(0.6, 1e-12)
		expect(CarShake.launchDegrees(1, 40, TUNING)).toBeNear(0.3, 1e-12)
		expect(CarShake.launchDegrees(1, 80, TUNING)).toBe(0)
		expect(CarShake.launchDegrees(-1, 0, TUNING)).toBe(0)
	end)

	it("dips then lifts the view on an upshift, and settles level", function()
		expect(CarShake.shiftPitch(0, TUNING)).toBeNear(0, 1e-12)
		expect(CarShake.shiftPitch(0.06, TUNING)).toBeNear(-0.4, 1e-12)
		expect(CarShake.shiftPitch(0.21, TUNING)).toBeNear(0.3, 1e-12)
		expect(CarShake.shiftPitch(0.36, TUNING)).toBeNear(0, 1e-12)
		expect(CarShake.shiftPitch(5, TUNING)).toBe(0)
		local previous = CarShake.shiftPitch(0, TUNING)
		for step = 1, 40 do
			local pitch = CarShake.shiftPitch(step * 0.01, TUNING)
			expect(math.abs(pitch - previous) < 0.15).toBe(true)
			previous = pitch
		end
	end)

	it("kicks on an upshift, not a downshift or the first gear seen, scaled by the gearbox", function()
		local state = CarShake.new()
		CarShake.step(state, input(3), 1 / 60, TUNING)
		expect(state.shiftAge > 1).toBe(true)
		CarShake.step(state, input(2), 1 / 60, TUNING)
		expect(state.shiftAge > 1).toBe(true)
		CarShake.step(state, input(3, 0.35), 1 / 60, TUNING)
		expect(state.shiftAge).toBe(0)
		expect(state.shiftScale).toBe(0.35)
		local strada = CarShake.step(state, input(3, 0.35), 0.06, TUNING).pitch
		local corsa = CarShake.new()
		CarShake.step(corsa, input(2), 1 / 60, TUNING)
		CarShake.step(corsa, input(3), 1 / 60, TUNING)
		local hard = CarShake.step(corsa, input(3), 0.06, TUNING).pitch
		expect(hard).toBeNear(math.rad(-0.4), 1e-9)
		expect(strada).toBeNear(math.rad(-0.4 * 0.35), 1e-9)
		local neutral = CarShake.new()
		CarShake.step(neutral, input(0), 1 / 60, TUNING)
		CarShake.step(neutral, input(1), 1 / 60, TUNING)
		expect(neutral.shiftAge > 1).toBe(true)
	end)

	it("stays within the sum of its parts at every frame", function()
		local state = CarShake.new()
		local fast: CarShake.Input =
			{ view = "Chase", speedKmh = 300, throttle = 1, longitudinalG = 1, gear = 6, shiftScale = 1 }
		local bound = math.rad(
			CarShake.roadDegrees(300, TUNING)
				+ CarShake.engineDegrees(1, 300, TUNING)
				+ CarShake.launchDegrees(1, 300, TUNING)
		)
		local moved = false
		for _ = 1, 600 do
			local offset = CarShake.step(state, fast, 1 / 60, TUNING)
			expect(math.abs(offset.pitch) <= bound + 1e-12).toBe(true)
			expect(math.abs(offset.roll) <= bound + 1e-12).toBe(true)
			moved = moved or math.abs(offset.pitch) > bound * 0.2
		end
		expect(moved).toBe(true)
	end)
end)
