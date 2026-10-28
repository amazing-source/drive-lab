--!strict
local CarLights = require("../src/shared/Rules/CarLights")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local TUNING: CarLights.Tuning = { rainOn = 0.3, brakeOn = 0.05, blinkHz = 1.5 }

local function state(overrides: { [string]: any }): CarLights.State
	local base: { [string]: any } = { mode = "Auto", night = false, rain = 0, brake = 0, gear = 1, time = 0 }
	for key, value in overrides do
		base[key] = value
	end
	return base :: any
end

describe("CarLights", function()
	it("switches the headlights on automatically at night and in heavy rain only", function()
		expect(CarLights.decide(state({}), TUNING).headlights).toBe(false)
		expect(CarLights.decide(state({ night = true }), TUNING).headlights).toBe(true)
		expect(CarLights.decide(state({ rain = 0.6 }), TUNING).headlights).toBe(true)
		expect(CarLights.decide(state({ rain = 0.1 }), TUNING).headlights).toBe(false)
	end)

	it("obeys a forced mode over the automatic", function()
		expect(CarLights.decide(state({ mode = "On" }), TUNING).headlights).toBe(true)
		expect(CarLights.decide(state({ mode = "Off", night = true }), TUNING).headlights).toBe(false)
	end)

	it("cycles the modes Auto, On, Off and back", function()
		expect(CarLights.nextMode("Auto")).toBe("On")
		expect(CarLights.nextMode("On")).toBe("Off")
		expect(CarLights.nextMode("Off")).toBe("Auto")
	end)

	it("lights the brakes on the pedal and the reversing light in reverse", function()
		expect(CarLights.decide(state({ brake = 0.02 }), TUNING).brake).toBe(false)
		expect(CarLights.decide(state({ brake = 0.4 }), TUNING).brake).toBe(true)
		expect(CarLights.decide(state({ gear = -1 }), TUNING).reverse).toBe(true)
		expect(CarLights.decide(state({ gear = 0 }), TUNING).reverse).toBe(false)
	end)

	it("blinks one indicator at its rate, the other side dark", function()
		local onAt = CarLights.decide(state({ indicator = "Left", time = 0.1 }), TUNING)
		local offAt = CarLights.decide(state({ indicator = "Left", time = 0.1 + 0.5 / 1.5 }), TUNING)
		expect(onAt.left).toBe(true)
		expect(offAt.left).toBe(false)
		expect(onAt.right).toBe(false)
	end)
end)
