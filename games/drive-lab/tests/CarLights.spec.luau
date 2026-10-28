--!strict
local CarLights = require("../src/shared/Rules/CarLights")
local Config = require("../src/shared/Config/CarLights")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local TUNING: CarLights.Tuning = {
	rainOn = 0.3,
	brakeOn = 0.05,
	blinkHz = 1.5,
	blinkOnShare = 0.5,
	drlWithHeadlights = 0.15,
	drlWhileIndicating = 0,
}

local function state(overrides: { [string]: any }): CarLights.State
	local base: { [string]: any } = {
		running = true,
		mode = "Auto",
		night = false,
		rain = 0,
		brake = 0,
		gear = 1,
		indicating = 0,
		cabin = false,
	}
	for key, value in overrides do
		base[key] = value
	end
	return base :: any
end

local function decide(overrides: { [string]: any }): CarLights.Lit
	return CarLights.decide(state(overrides), TUNING)
end

describe("CarLights", function()
	it("switches the headlights on automatically at night and in heavy rain only", function()
		expect(decide({}).headlights).toBe(false)
		expect(decide({ night = true }).headlights).toBe(true)
		expect(decide({ rain = 0.6 }).headlights).toBe(true)
		expect(decide({ rain = 0.1 }).headlights).toBe(false)
	end)

	it("obeys a forced mode over the automatic", function()
		expect(decide({ mode = "On" }).headlights).toBe(true)
		expect(decide({ mode = "Off", night = true }).headlights).toBe(false)
	end)

	it("cycles the modes Auto, On, Off and back", function()
		expect(CarLights.nextMode("Auto")).toBe("On")
		expect(CarLights.nextMode("On")).toBe("Off")
		expect(CarLights.nextMode("Off")).toBe("Auto")
	end)

	it("lights the brakes on the pedal and the reversing light in reverse", function()
		expect(decide({ brake = 0.02 }).brake).toBe(false)
		expect(decide({ brake = 0.4 }).brake).toBe(true)
		expect(decide({ gear = -1 }).reverse).toBe(true)
		expect(decide({ gear = 0 }).reverse).toBe(false)
	end)

	it(
		"keeps every outside lamp dark until the ignition is on, and the cabin light works without it",
		function()
			local off = decide({
				running = false,
				mode = "On",
				night = true,
				brake = 1,
				gear = -1,
				indicator = "Left",
				cabin = true,
			})
			expect(off.headlights).toBe(false)
			expect(off.drlLeft).toBe(0)
			expect(off.drlRight).toBe(0)
			expect(off.tail).toBe(false)
			expect(off.brake).toBe(false)
			expect(off.reverse).toBe(false)
			expect(off.left).toBe(false)
			expect(off.cabin).toBe(true)
		end
	)

	it("lights the indicator from the moment it is switched on, at its rate, the other side dark", function()
		local period = 1 / TUNING.blinkHz
		expect(decide({ indicator = "Left", indicating = 0 }).left).toBe(true)
		expect(decide({ indicator = "Left", indicating = 0.49 * period }).left).toBe(true)
		expect(decide({ indicator = "Left", indicating = 0.51 * period }).left).toBe(false)
		expect(decide({ indicator = "Left", indicating = 1.01 * period }).left).toBe(true)
		expect(decide({ indicator = "Left", indicating = 0 }).right).toBe(false)
	end)

	it("runs the daytime lights full, dimmed to a position lamp with the headlights", function()
		expect(decide({}).drlLeft).toBe(1)
		expect(decide({ night = true }).drlLeft).toBe(TUNING.drlWithHeadlights)
		expect(decide({ night = true }).drlRight).toBe(TUNING.drlWithHeadlights)
	end)

	it("puts out the running light on the indicator's side for the whole flash cycle", function()
		local period = 1 / TUNING.blinkHz
		for _, elapsed in { 0, 0.75 * period } do
			local lit = decide({ indicator = "Right", indicating = elapsed })
			expect(lit.drlRight).toBe(TUNING.drlWhileIndicating)
			expect(lit.drlLeft).toBe(1)
		end
	end)

	it("lights the tail lamps with the headlights, not with the running lights alone", function()
		expect(decide({}).tail).toBe(false)
		expect(decide({ night = true }).tail).toBe(true)
	end)

	it("burns the Y lamps as tail lamps at a fifth of their brake output or less", function()
		local tail = CarLights.levels(decide({ night = true }), Config.TAIL_SHARE)
		local braking = CarLights.levels(decide({ night = true, brake = 1 }), Config.TAIL_SHARE)
		expect(braking.tail).toBe(1)
		expect(tail.tail > 0).toBe(true)
		expect(braking.tail / tail.tail >= 5).toBe(true)
		expect(braking.stop).toBe(1)
		expect(tail.stop).toBe(0)
		expect(tail.position).toBe(1)
	end)

	it("draws lamps brighter by day than at night, in proportion to their level", function()
		expect(CarLights.daylight(0.6, 0.6, 1.6)).toBe(0)
		expect(CarLights.daylight(2.4, 0.6, 1.6)).toBe(1)
		expect(CarLights.daylight(1.1, 0.6, 1.6)).toBeNear(0.5, 1e-9)
		expect(CarLights.strength(1, 2, 8, 0)).toBe(2)
		expect(CarLights.strength(1, 2, 8, 1)).toBe(8)
		expect(CarLights.strength(0.5, 2, 8, 0.5)).toBeNear(2.5, 1e-9)
	end)

	it("tells a tap from a hold on the pad's lights button", function()
		local hold = 0.5
		local press: CarLights.Press = { since = nil, spent = false }
		expect(CarLights.press(press, true, 0, hold)).toBe(nil)
		expect(CarLights.press(press, true, 0.3, hold)).toBe(nil)
		expect(CarLights.press(press, false, 0.35, hold)).toBe("Tap")
		expect(CarLights.press(press, false, 0.4, hold)).toBe(nil)

		expect(CarLights.press(press, true, 1, hold)).toBe(nil)
		expect(CarLights.press(press, true, 1.49, hold)).toBe(nil)
		expect(CarLights.press(press, true, 1.5, hold)).toBe("Hold")
		expect(CarLights.press(press, true, 2.5, hold)).toBe(nil)
		expect(CarLights.press(press, false, 2.6, hold)).toBe(nil)
	end)

	it("keeps the configured indicator rhythm and stop-to-tail ratio inside the regulations", function()
		local perMinute = Config.TUNING.blinkHz * 60
		expect(perMinute >= 60 and perMinute <= 120).toBe(true)
		expect(Config.TUNING.blinkOnShare >= 0.3 and Config.TUNING.blinkOnShare <= 0.75).toBe(true)
		expect(1 / Config.TAIL_SHARE >= 5).toBe(true)
	end)
end)
