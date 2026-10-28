--!strict
local HeadLook = require("../src/shared/Rules/HeadLook")
local Look = require("../src/shared/Config/Look")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

describe("HeadLook", function()
	it("reads straight ahead as no turn", function()
		local angles = HeadLook.fromDirection(0, 0, -1)
		expect(angles.yaw).toBeNear(0, 1e-9)
		expect(angles.pitch).toBeNear(0, 1e-9)
	end)

	it("turns left for a look toward -X and up for a look toward +Y", function()
		local left = HeadLook.fromDirection(-1, 0, -1)
		expect(left.yaw).toBeNear(math.rad(45), 1e-9)
		local up = HeadLook.fromDirection(0, 1, -2)
		expect(up.pitch).toBeNear(math.atan2(1, 2), 1e-9)
	end)

	it("never turns the head past the neck's range", function()
		local side = HeadLook.fromDirection(-1, 0, 0)
		expect(side.yaw).toBeNear(Look.MAX_YAW, 1e-9)
		local down = HeadLook.fromDirection(0, -1, 0)
		expect(down.pitch).toBeNear(-Look.MAX_PITCH_DOWN, 1e-9)
	end)

	it("looks back at a camera that faces the character", function()
		local facing = HeadLook.fromDirection(0, -0.2, 1)
		expect(facing.yaw).toBeNear(0, 1e-9)
	end)

	it("never jumps as the camera circles the character", function()
		local previous = HeadLook.fromDirection(0, 0, -1).yaw
		for degrees = 2, 360, 2 do
			local heading = math.rad(degrees)
			local yaw = HeadLook.fromDirection(-math.sin(heading), 0, -math.cos(heading)).yaw
			expect(math.abs(yaw - previous) < math.rad(5)).toBe(true)
			previous = yaw
		end
	end)

	it("rejects payloads a client could forge", function()
		expect(HeadLook.parse(nil)).toBe(nil)
		expect(HeadLook.parse({ yaw = "1", pitch = 0 })).toBe(nil)
		expect(HeadLook.parse({ yaw = 0 / 0, pitch = 0 })).toBe(nil)
		expect(HeadLook.parse({ yaw = math.huge, pitch = 0 })).toBe(nil)
		local clamped = HeadLook.parse({ yaw = 10, pitch = -10 }) :: HeadLook.Angles
		expect(clamped.yaw).toBeNear(Look.MAX_YAW, 1e-9)
		expect(clamped.pitch).toBeNear(-Look.MAX_PITCH_DOWN, 1e-9)
	end)

	it("eases the same distance whatever the frame rate", function()
		local target = { yaw = 1, pitch = 0 }
		local coarse = HeadLook.approach({ yaw = 0, pitch = 0 }, target, 0.1)
		local fine = { yaw = 0, pitch = 0 }
		for _ = 1, 10 do
			fine = HeadLook.approach(fine, target, 0.01)
		end
		expect(fine.yaw).toBeNear(coarse.yaw, 1e-9)
		expect(HeadLook.approach({ yaw = 0, pitch = 0 }, target, Look.SMOOTHING_HALF_LIFE).yaw).toBeNear(
			0.5,
			1e-9
		)
	end)
end)
