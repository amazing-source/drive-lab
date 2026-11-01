--!strict
local Boss302Gauges = require("../src/shared/Config/Cars/Boss302/Gauges")
local Gauges = require("../src/shared/Config/Gauges")
local Rules = require("../src/shared/Rules/Gauges")
local Startup = require("../src/shared/Config/Cars/Boss302/Startup")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local function dial(unit: Gauges.Unit, reading: Gauges.Reading, scale: { { number } }): Gauges.Dial
	return {
		needle = "Needle",
		reading = reading,
		unit = unit,
		scale = scale,
		response = 0.2,
		maxRate = 3,
		catchUp = 0.2,
	}
end

-- The needle's share after `seconds` toward `target` from rest, stepped at `fps`, and the most it
-- moved in one step (shares a second), the furthest past the target it went, and its share at
-- every step.
local function run(target: number, seconds: number, fps: number, response: number, maxRate: number)
	local needle = Rules.newNeedle()
	local dt = 1 / fps
	local fastest, past = 0, 0
	for _ = 1, math.round(seconds * fps) do
		local before = needle.share
		Rules.step(needle, target, dt, response, maxRate)
		fastest = math.max(fastest, math.abs(needle.share - before) / dt)
		past = math.max(past, (needle.share - target) * (if target >= 0 then 1 else -1))
	end
	return needle.share, fastest, past
end

describe("Gauge needles", function()
	it("reads a linear dial in its printed unit, held at the dial's ends", function()
		local speedo = dial("mph", "speed", { { 0, 0 }, { 180, 1 } })
		expect(Rules.share(speedo, 90 * 1.609344)).toBeNear(0.5, 1e-9)
		expect(Rules.share(speedo, 0)).toBe(0)
		expect(Rules.share(speedo, 400)).toBe(1)
		expect(Rules.share(speedo, -20)).toBe(0)
		local water = dial("degF", "coolant", { { 100, 0 }, { 260, 1 } })
		expect(Rules.share(water, 100)).toBeNear((212 - 100) / 160, 1e-9)
		local oil = dial("psi", "oilPressure", { { 0, 0 }, { 100, 1 } })
		expect(Rules.share(oil, 6.894757 * 50)).toBeNear(0.5, 1e-6)
	end)

	it("holds a buffered gauge mid across its flat stretch", function()
		local temp = dial("degF", "coolant", { { 100, 0 }, { 165, 0.5 }, { 235, 0.5 }, { 260, 1 } })
		for _, fahrenheit in { 165, 180, 200, 235 } do
			expect(Rules.share(temp, (fahrenheit - 32) * 5 / 9)).toBeNear(0.5, 1e-9)
		end
		expect(Rules.share(temp, (132.5 - 32) * 5 / 9)).toBeNear(0.25, 1e-9)
		expect(Rules.share(temp, (247.5 - 32) * 5 / 9)).toBeNear(0.75, 1e-9)
	end)

	it("takes each reading only in a unit it can be printed in", function()
		expect(Rules.unitFits("speed", "mph")).toBe(true)
		expect(Rules.unitFits("speed", "psi")).toBe(false)
		expect(Rules.unitFits("coolant", "degF")).toBe(true)
		expect(Rules.unitFits("fuel", "degC")).toBe(false)
		expect(Rules.unitFits("rpm", "rpm")).toBe(true)
	end)

	it("follows a step without ever passing it, within the motor's top speed", function()
		for _, case in { { 1, 0.06, 3.3 }, { 0.4, 0.2, 3 }, { 0.7, 2, 0.3 }, { 0.05, 0.15, 2 } } do
			local target, response, maxRate = case[1], case[2], case[3]
			local share, fastest, past = run(target, 30, 60, response, maxRate)
			expect(past <= 1e-12 and "never past").toBe("never past")
			expect(fastest <= maxRate + 1e-9 and "within its top speed").toBe("within its top speed")
			expect(share).toBeNear(target, 1e-3)
		end
		-- Rising fast toward the top of the dial when the reading drops just in front of it.
		local needle = { share = 0.48, velocity = 3, met = true }
		for _ = 1, 120 do
			Rules.step(needle, 0.5, 1 / 60, 0.06, 3.3)
			expect(needle.share <= 0.5 and "never past" or needle.share).toBe("never past")
		end
	end)

	it("settles like a critically damped needle when its top speed does not bind", function()
		-- A critically damped spring is 95 % of the way after about 4.74 time constants.
		local share = run(0.2, 0.2 * 4.74, 240, 0.2, 100)
		expect(share).toBeNear(0.19, 0.002)
		local early = run(0.2, 0.2, 240, 0.2, 100)
		expect(early).toBeNear(0.2 * (1 - 2 * math.exp(-1)), 0.002)
	end)

	it("slows into its reading at the end of a sweep instead of stopping dead", function()
		local needle = Rules.newNeedle()
		local dt, response, maxRate = 1 / 240, 0.06, 3.3
		local arriving = 0
		for _ = 1, 240 do
			local before = needle.share
			Rules.step(needle, 1, dt, response, maxRate)
			if needle.share > 1 - 0.02 then
				arriving = math.max(arriving, (needle.share - before) / dt)
			end
		end
		-- Over its last 2 % it moves at most what it can stop from within that distance.
		expect(arriving <= 0.02 / response + 1e-9 and "slowing in").toBe("slowing in")
		expect(arriving > 0 and "arrived").toBe("arrived")
	end)

	it("ramps at its top speed through a long sweep", function()
		local share = run(1, 0.1, 240, 0.01, 2)
		expect(share).toBeNear(0.2, 0.01)
	end)

	it("moves the same at 30, 60 and 240 frames a second", function()
		-- Whole frames at every rate.
		for _, seconds in { 1 / 15, 0.1, 0.2, 0.5, 1 } do
			local reference = run(0.8, seconds, 240, 0.12, 3)
			for _, fps in { 30, 60 } do
				expect(run(0.8, seconds, fps, 0.12, 3)).toBeNear(reference, 0.012)
			end
		end
	end)

	it("catches up fast at the ignition, then damps", function()
		local fuel = Boss302Gauges.dials[3]
		expect(fuel.needle).toBe("Needle_Fuel")
		local needle = Rules.newNeedle()
		local target = Rules.share(fuel, 0.8)
		local elapsed = 0
		while not needle.met and elapsed < 30 do
			Rules.follow(needle, fuel, target, 1 / 60)
			elapsed += 1 / 60
		end
		expect(elapsed < 3 and "met within a second or two").toBe("met within a second or two")
		local before = needle.share
		Rules.follow(needle, fuel, 0.2, 1)
		-- Met, it follows a sudden drop at its slow time constant only.
		expect(before - needle.share < 0.05 and "damped").toBe("damped")
	end)

	it("lights with the key reaching ON, dark before and with the engine off", function()
		local keyOn = assert(Rules.lightAt(Startup, "Key_Ignition"), "the key moves in the start-up")
		expect(keyOn).toBe(Startup.moves[1].at)
		local state = { engine = "On", engineAt = 100 } :: any
		expect(Rules.sinceLit(Startup, "Key_Ignition", state, 100 + keyOn - 0.01)).toBe(nil)
		expect(Rules.sinceLit(Startup, "Key_Ignition", state, 100 + keyOn + 0.5)).toBeNear(0.5, 1e-9)
		expect(Rules.sinceLit(Startup, "Key_Ignition", { engine = "Off", engineAt = 100 } :: any, 200)).toBe(
			nil
		)
		-- A control the start-up never moves lights the cluster at the press.
		expect(Rules.sinceLit(Startup, "Nothing", state, 100 + Startup.pressAt + 0.25)).toBeNear(0.25, 1e-9)
	end)

	it("sweeps up and back only when the car has a sweep", function()
		expect(Rules.sweepShare(nil, 0.3)).toBe(nil)
		expect(Rules.sweepShare(1.2, 0.6)).toBeNear(1, 1e-9)
		expect(Rules.sweepShare(1.2, 0.3)).toBeNear(math.sin(math.pi / 4), 1e-9)
		expect(Rules.sweepShare(1.2, 1.2)).toBe(nil)
		expect(Boss302Gauges.sweep).toBe(nil)
	end)
end)
