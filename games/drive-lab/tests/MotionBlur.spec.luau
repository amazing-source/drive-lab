--!strict
local MotionBlur = require("../src/shared/Rules/MotionBlur")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local ROTATION: MotionBlur.Rotation =
	{ from = 120, to = 480, max = 6, exponent = 1.5, rise = 0.03, fall = 0.08, cut = 45 }
local SPEED: MotionBlur.Speed = { from = 80, to = 300, near = 0.45, exponent = 1.2 }

describe("MotionBlur", function()
	it("reads a turn as degrees a second, and a jump past the cut as no motion", function()
		expect(MotionBlur.turnRate(5, 1 / 60, 45)).toBeNear(300, 1e-9)
		expect(MotionBlur.turnRate(-5, 1 / 60, 45)).toBeNear(300, 1e-9)
		expect(MotionBlur.turnRate(90, 1 / 60, 45)).toBe(nil)
		expect(MotionBlur.turnRate(5, 0, 45)).toBe(nil)
		expect(MotionBlur.turnRate(0 / 0, 1 / 60, 45)).toBe(nil)
	end)

	it("keeps ordinary turns sharp and blurs a fast one up to its cap", function()
		expect(MotionBlur.rotationSize(60, ROTATION)).toBe(0)
		expect(MotionBlur.rotationSize(120, ROTATION)).toBe(0)
		expect(MotionBlur.rotationSize(300, ROTATION)).toBeNear(6 * 0.5 ^ 1.5, 1e-12)
		expect(MotionBlur.rotationSize(480, ROTATION)).toBe(6)
		expect(MotionBlur.rotationSize(5000, ROTATION)).toBe(6)
		expect(MotionBlur.rotationSize(0 / 0, ROTATION)).toBe(0)
	end)

	it("rises quicker than it falls, by half each half-life at any frame rate", function()
		expect(MotionBlur.follow(0, 4, 0.03, ROTATION)).toBeNear(2, 1e-12)
		expect(MotionBlur.follow(4, 0, 0.08, ROTATION)).toBeNear(2, 1e-12)
		local stepped = 0
		for _ = 1, 4 do
			stepped = MotionBlur.follow(stepped, 4, 0.0075, ROTATION)
		end
		expect(stepped).toBeNear(MotionBlur.follow(0, 4, 0.03, ROTATION), 1e-12)
		expect(MotionBlur.follow(3, 0, -1, ROTATION)).toBe(3)
	end)

	it("blurs the near road from a speed, either way, up to its cap", function()
		expect(MotionBlur.speedNear(50, SPEED)).toBe(0)
		expect(MotionBlur.speedNear(80, SPEED)).toBe(0)
		expect(MotionBlur.speedNear(190, SPEED)).toBeNear(0.45 * 0.5 ^ 1.2, 1e-12)
		expect(MotionBlur.speedNear(-190, SPEED)).toBeNear(0.45 * 0.5 ^ 1.2, 1e-12)
		expect(MotionBlur.speedNear(400, SPEED)).toBe(0.45)
		expect(MotionBlur.speedNear(0 / 0, SPEED)).toBe(0)
	end)
end)
