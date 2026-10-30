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
	it("reaches full lock at a standstill in its lock time", function()
		expect(timeTo(InputFilter.newState(), 1, 1, 0)).toBeNear(keyboard.lockTime, 0.005)
	end)

	it("eases in, as a hand speeds the wheel up, and never passes its target", function()
		local state = InputFilter.newState()
		local topRate = 1 / (keyboard.lockTime - keyboard.easeTime)
		local early = keyboard.easeTime / 2
		local elapsed, highest = 0, 0
		while elapsed < early - 1e-9 do
			InputFilter.update(keyboard, SVJ, state, raw(1), 0, 0, 0, 0.001)
			elapsed += 0.001
		end
		expect(state.steer < topRate * early / 2).toBe(true)
		for _ = 1, 2000 do
			InputFilter.update(keyboard, SVJ, state, raw(1), 0, 0, 0, 0.001)
			highest = math.max(highest, state.steer)
		end
		expect(highest).toBe(1)
	end)

	it("moves the wheel only a little on a short tap", function()
		local state = InputFilter.newState()
		local peak = 0
		for step = 1, 600 do
			InputFilter.update(keyboard, SVJ, state, raw(if step <= 100 then 1 else 0), 0, 0, 0, 0.001)
			peak = math.max(peak, state.steer)
		end
		-- The constant 2.5 of lock a second this replaced reached 0.25 on the same 0.1 s tap.
		expect(peak < 0.1).toBe(true)
		expect(state.steer >= 0).toBe(true)
	end)

	it("returns slowly at rest and quickly on the move", function()
		local function back(speed: number): number
			local state = InputFilter.newState()
			state.steer = 1
			return timeTo(state, 0, 0, speed)
		end
		expect(back(0)).toBeNear(keyboard.returnTimeStill, 0.005)
		expect(back(keyboard.returnBlend.to)).toBeNear(keyboard.returnTimeMoving, 0.005)
		expect(keyboard.returnTimeStill >= keyboard.lockTime).toBe(true)
	end)

	it("turns toward the other side faster than it turns in", function()
		local opposite = InputFilter.moveTime(keyboard, -1, 1, 0)
		expect(opposite).toBeNear(keyboard.lockTime / keyboard.oppositeFactor, 1e-12)
		expect(opposite < InputFilter.moveTime(keyboard, 0, 1, 0)).toBe(true)
		-- The same share at any speed: on the move it never takes the quick return's pace, which
		-- made a swing from one side to the other 4 to 5 times faster than turning in.
		for _, speed in { 8, 14, 30 } do
			local turnIn = InputFilter.moveTime(keyboard, 0, 1, speed)
			expect(InputFilter.moveTime(keyboard, -1, 1, speed)).toBeNear(
				turnIn / keyboard.oppositeFactor,
				1e-12
			)
		end
	end)

	it("keeps its timing within a frame at 30, 60 and 240 FPS", function()
		local function lockAt(dt: number): number
			local state, elapsed = InputFilter.newState(), 0
			while state.steer < 1 and elapsed < 5 do
				InputFilter.update(keyboard, SVJ, state, raw(1), 0, 0, 0, dt)
				elapsed += dt
			end
			return elapsed
		end
		local reference = lockAt(1 / 240)
		for _, fps in { 30, 60, 240 } do
			local dt = 1 / fps
			expect(math.abs(lockAt(dt) - reference) <= dt).toBe(true)
		end
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
