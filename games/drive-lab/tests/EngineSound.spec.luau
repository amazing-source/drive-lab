--!strict
local EngineSound = require("../src/shared/Rules/EngineSound")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local FLAT: EngineSound.Tuning = {
	crossfadeOctaves = 0.5,
	minSpeed = 0.05,
	maxSpeed = 4,
	quietRpm = 1000,
	quietDb = 0,
	loudRpm = 8000,
	loudDb = 0,
	liftHalfLife = 0.02,
	pressHalfLife = 0.08,
	volumeHalfLife = 0.03,
	speedHalfLife = 0.01,
}

local LAYERS: { EngineSound.Layer } = {
	{ rpm = 1000, load = "Both", volume = 1, crossoverRpm = 1300 },
	{ rpm = 4000, load = "On", volume = 1 },
	{ rpm = 7500, load = "On", volume = 1 },
	{ rpm = 7000, load = "Off", volume = 1 },
}

local function power(volumes: { number }): number
	local sum = 0
	for _, volume in volumes do
		sum += volume * volume
	end
	return sum
end

describe("EngineSound", function()
	it("plays each loop at rpm over the rpm it was recorded at, within the speed bounds", function()
		local speeds = EngineSound.target(LAYERS, FLAT, 3750, 1).speeds
		expect(speeds[1]).toBeNear(3.75, 1e-9)
		expect(speeds[2]).toBeNear(0.9375, 1e-9)
		expect(speeds[3]).toBeNear(0.5, 1e-9)
		expect(EngineSound.target(LAYERS, FLAT, 100, 1).speeds[3]).toBe(FLAT.minSpeed)
		expect(EngineSound.target(LAYERS, FLAT, 9000, 1).speeds[1]).toBe(FLAT.maxSpeed)
	end)

	it("keeps the power of one load constant through every hand-over", function()
		for rpm = 600, 9000, 25 do
			expect(power(EngineSound.target(LAYERS, FLAT, rpm, 1).volumes)).toBeNear(1, 1e-9)
			expect(power(EngineSound.target(LAYERS, FLAT, rpm, 0).volumes)).toBeNear(1, 1e-9)
		end
	end)

	it("hands over inside the band around the crossover: lower alone below, upper alone above", function()
		-- Idle to 4,000 at the idle's crossover, 1,300 rpm: the band is 1,093 to 1,546 rpm.
		local below = EngineSound.target(LAYERS, FLAT, 1080, 1).volumes
		expect(below[1]).toBeNear(1, 1e-9)
		expect(below[2]).toBeNear(0, 1e-9)
		local above = EngineSound.target(LAYERS, FLAT, 1560, 1).volumes
		expect(above[1]).toBeNear(0, 1e-9)
		expect(above[2]).toBeNear(1, 1e-9)
		local centre = EngineSound.target(LAYERS, FLAT, 1300, 1).volumes
		expect(centre[1] ^ 2).toBeNear(0.5, 1e-9)
		expect(centre[2] ^ 2).toBeNear(0.5, 1e-9)
		-- 4,000 to 7,500 has no crossover set: the centre is their geometric mean.
		local middle = EngineSound.target(LAYERS, FLAT, math.sqrt(4000 * 7500), 1).volumes
		expect(middle[2] ^ 2).toBeNear(0.5, 1e-9)
		expect(middle[3] ^ 2).toBeNear(0.5, 1e-9)
	end)

	it("blends on and off by throttle at equal power, and the shared idle keeps its level", function()
		local half = EngineSound.target(LAYERS, FLAT, 7000, 0.5).volumes
		expect(half[3]).toBeNear(math.sqrt(0.5), 1e-9)
		expect(half[4]).toBeNear(math.sqrt(0.5), 1e-9)
		for _, share in { 0, 0.3, 1 } do
			expect(EngineSound.target(LAYERS, FLAT, 900, share).volumes[1]).toBeNear(1, 1e-9)
		end
	end)

	it("grows louder with rpm between its quiet and loud ends", function()
		local tuning = table.clone(FLAT)
		tuning.quietDb = -12
		expect(EngineSound.loudness(tuning, 500)).toBeNear(10 ^ (-12 / 20), 1e-9)
		expect(EngineSound.loudness(tuning, 1000)).toBeNear(10 ^ (-12 / 20), 1e-9)
		expect(EngineSound.loudness(tuning, math.sqrt(1000 * 8000))).toBeNear(10 ^ (-6 / 20), 1e-9)
		expect(EngineSound.loudness(tuning, 8000)).toBeNear(1, 1e-9)
		expect(EngineSound.loudness(tuning, 9000)).toBeNear(1, 1e-9)
	end)

	it("fades in from silence without a step, with the speeds on target from the first frame", function()
		local state = EngineSound.new(LAYERS, FLAT)
		state.throttle = 1
		local dt = 1 / 60
		local mix = EngineSound.step(state, 7500, 1, dt)
		local share = EngineSound.blend(dt, FLAT.volumeHalfLife)
		expect(mix.volumes[3]).toBeNear(share, 1e-9)
		expect(mix.speeds[3]).toBe(1)
		for _ = 1, 120 do
			local before = mix.volumes[3]
			EngineSound.step(state, 7500, 1, dt)
			expect(mix.volumes[3] - before <= share + 1e-12).toBeTruthy()
		end
		expect(mix.volumes[3]).toBeNear(1, 1e-6)
	end)

	it("follows a lift faster than a press", function()
		local press = EngineSound.new(LAYERS, FLAT)
		local lift = EngineSound.new(LAYERS, FLAT)
		lift.throttle = 1
		for _ = 1, 3 do
			EngineSound.step(press, 7000, 1, 1 / 60)
			EngineSound.step(lift, 7000, 0, 1 / 60)
		end
		expect(1 - lift.throttle).toBeNear(1 - 0.5 ^ (0.05 / FLAT.liftHalfLife), 1e-9)
		expect(press.throttle).toBeNear(1 - 0.5 ^ (0.05 / FLAT.pressHalfLife), 1e-9)
		expect(1 - lift.throttle > press.throttle).toBeTruthy()
	end)

	it("moves the same way at any frame rate", function()
		local coarse = EngineSound.new(LAYERS, FLAT)
		local fine = EngineSound.new(LAYERS, FLAT)
		coarse.throttle, fine.throttle = 1, 1
		EngineSound.step(coarse, 6000, 1, 0.1)
		for _ = 1, 10 do
			EngineSound.step(fine, 6000, 1, 0.01)
		end
		for index in LAYERS do
			expect(fine.mix.volumes[index]).toBeNear(coarse.mix.volumes[index], 1e-9)
		end
		local throttleCoarse = EngineSound.new(LAYERS, FLAT)
		local throttleFine = EngineSound.new(LAYERS, FLAT)
		EngineSound.step(throttleCoarse, 6000, 1, 0.1)
		for _ = 1, 10 do
			EngineSound.step(throttleFine, 6000, 1, 0.01)
		end
		expect(throttleFine.throttle).toBeNear(throttleCoarse.throttle, 1e-9)
	end)
end)
