--!strict
local T = require("../../../tools/test/T")
local Geometry = require("../src/shared/Vehicle/Geometry")
local InputFilter = require("../src/shared/Vehicle/InputFilter")
local InputHelp = require("../src/shared/Config/InputHelp")
local SVJ = require("../src/shared/Config/Cars/SVJ")
local Steering = require("../src/shared/Vehicle/Steering")

local describe, it, expect = T.describe, T.it, T.expect

local keyboard = InputHelp.keyboard

local function raw(steer: number, throttle: number?, brake: number?): InputFilter.RawControls
	return { steer = steer, throttle = throttle or 0, brake = brake or 0, handbrake = 0 }
end

-- Seconds of steady `steer` input until the filtered value reaches `target`.
local function timeTo(state: InputFilter.Controls, steer: number, target: number, speed: number): number
	local elapsed = 0
	while math.abs(state.steer - target) > 1e-9 and elapsed < 10 do
		InputFilter.update(keyboard, SVJ, state, raw(steer), speed, 0, 0, 0.001)
		elapsed += 0.001
	end
	return elapsed
end

describe("Input filter steering", function()
	it("returns to centre faster than it turns in", function()
		local state = InputFilter.newState()
		local turnIn = timeTo(state, 1, 1, 0)
		local back = timeTo(state, 0, 0, 0)
		expect(turnIn).toBeNear(1 / keyboard.steerRate, 0.002)
		expect(back).toBeNear(turnIn / keyboard.returnRateFactor, 0.002)
	end)

	it("slows as speed rises, halving at the configured speed", function()
		local still = timeTo(InputFilter.newState(), 0.04, 0.04, 0)
		local fast = timeTo(InputFilter.newState(), 0.04, 0.04, keyboard.rateHalvingSpeed)
		expect(fast / still).toBeNear(2, 0.05)
	end)

	it("limits steering to the angle that puts the front axle at its target slip", function()
		local state = InputFilter.newState()
		local speed = 30
		for _ = 1, 3000 do
			InputFilter.update(keyboard, SVJ, state, raw(1), speed, 0, 0, 0.001)
		end
		local angle = Steering.frontAngle(SVJ.steering, state.steer, speed)
		expect(angle).toBeNear(keyboard.targetSlip * SVJ.front.tyre.slipAngleAtPeak, 1e-6)
	end)

	it("opens the limit as the front axle swings out in a slide", function()
		local yawRate = 0.4
		local low, high = InputFilter.steerBounds(keyboard, SVJ, 30, -2, yawRate)
		local front = Geometry.frontAxleDistance(SVJ)
		local heading = math.atan((-2 + front * yawRate) / 30)
		local perRadian = Steering.ratio(SVJ.steering, 30) / Steering.maxWheelAngle(SVJ.steering)
		expect((low + high) / 2).toBeNear(heading * perRadian, 1e-9)
	end)

	it("never steers against the player's direction", function()
		local state = InputFilter.newState()
		for _ = 1, 2000 do
			InputFilter.update(keyboard, SVJ, state, raw(1), 30, 0, -1.5, 0.001)
		end
		expect(state.steer >= 0).toBeTruthy()
	end)

	it("shapes a stick with the exponent outside the deadzone", function()
		local pad = InputHelp.gamepad
		expect(InputFilter.shape(pad, pad.deadzone * 0.9)).toBe(0)
		expect(InputFilter.shape(pad, -1)).toBe(-1)
		local half = pad.deadzone + (1 - pad.deadzone) / 2
		expect(InputFilter.shape(pad, half)).toBeNear(0.5 ^ pad.stickExponent, 1e-12)
	end)

	it("passes a wheel or robot driver straight through with the direct preset", function()
		local state = InputFilter.newState()
		InputFilter.update(InputHelp.direct, SVJ, state, raw(-0.7, 0.4, 0.2), 50, 0, 0, 1 / 60)
		expect(state.steer).toBe(-0.7)
		expect(state.throttle).toBe(0.4)
		expect(state.brake).toBe(0.2)
	end)
end)

describe("Input filter pedals", function()
	it("ramps the throttle over its rise time, the same at any frame rate", function()
		local coarse, fine = InputFilter.newState(), InputFilter.newState()
		for _ = 1, 3 do
			InputFilter.update(keyboard, SVJ, coarse, raw(0, 1), 0, 0, 0, 1 / 30)
		end
		for _ = 1, 24 do
			InputFilter.update(keyboard, SVJ, fine, raw(0, 1), 0, 0, 0, 1 / 240)
		end
		expect(coarse.throttle).toBeNear(0.1 / keyboard.throttleRiseTime, 1e-9)
		expect(fine.throttle).toBeNear(coarse.throttle, 1e-9)
	end)

	it("releases faster than it presses", function()
		local state = InputFilter.newState()
		state.brake = 1
		InputFilter.update(keyboard, SVJ, state, raw(0, 0, 0), 0, 0, 0, keyboard.brakeFallTime / 2)
		expect(state.brake).toBeNear(0.5, 1e-9)
		expect(keyboard.brakeFallTime < keyboard.brakeRiseTime).toBeTruthy()
	end)
end)
