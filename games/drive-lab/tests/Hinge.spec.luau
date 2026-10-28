--!strict
local Hinge = require("../src/shared/Rules/Hinge")
local SVJModel = require("../src/shared/Config/Cars/SVJModel")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local function near(actual: Hinge.Vector, expected: Hinge.Vector, tolerance: number)
	expect(actual.x).toBeNear(expected.x, tolerance)
	expect(actual.y).toBeNear(expected.y, tolerance)
	expect(actual.z).toBeNear(expected.z, tolerance)
end

local function distanceFromAxis(point: Hinge.Vector, pivot: Hinge.Vector, axis: Hinge.Vector): number
	local length = math.sqrt(axis.x ^ 2 + axis.y ^ 2 + axis.z ^ 2)
	local k = { x = axis.x / length, y = axis.y / length, z = axis.z / length }
	local v = { x = point.x - pivot.x, y = point.y - pivot.y, z = point.z - pivot.z }
	local along = v.x * k.x + v.y * k.y + v.z * k.z
	return math.sqrt((v.x - k.x * along) ^ 2 + (v.y - k.y * along) ^ 2 + (v.z - k.z * along) ^ 2)
end

local ORIGIN = { x = 0, y = 0, z = 0 }

-- The SVJ door's top rear corner, shut and fully open, in the car frame (metres from the centre of
-- mass): turned by Blender's own rotation about the fitted hinge (hero_car_door_render.py,
-- door_corner.json: Blender (0.72828, 0.48757, 0.75483) to (1.1761, -0.97865, 2.27729); centre of
-- mass (0, 0.279, 0.4314); forward = -(y - 0.279), right = -x, up = z - 0.4314).
local CORNER_SHUT = { forward = -0.20857, right = -0.72828, up = 0.32343 }
local CORNER_OPEN = { forward = 1.25765, right = -1.1761, up = 1.84589 }

describe("Hinge", function()
	it("reads a car-frame point into the chassis's space: right, up, toward the back", function()
		near(Hinge.chassis({ forward = 1, right = 2, up = 3 }), { x = 2, y = 3, z = -1 }, 1e-12)
	end)

	it("turns by the right-hand rule, as CFrame.fromAxisAngle does", function()
		local quarter = math.pi / 2
		near(
			Hinge.rotate({ x = 0, y = 1, z = 0 }, ORIGIN, { x = 1, y = 0, z = 0 }, quarter),
			{ x = 0, y = 0, z = 1 },
			1e-12
		)
		near(
			Hinge.rotate({ x = 0, y = 0, z = 1 }, ORIGIN, { x = 0, y = 1, z = 0 }, quarter),
			{ x = 1, y = 0, z = 0 },
			1e-12
		)
		near(
			Hinge.rotate({ x = 1, y = 0, z = 0 }, ORIGIN, { x = 0, y = 0, z = 1 }, quarter),
			{ x = 0, y = 1, z = 0 },
			1e-12
		)
	end)

	it("turns about the pivot, keeps points on the axis still and every point's distance from it", function()
		local pivot = { x = 1.5, y = -0.4, z = 2 }
		local axis = { x = 0.98, y = -0.14, z = 0.14 }
		near(
			Hinge.rotate({ x = 1.5 + 0.98, y = -0.4 - 0.14, z = 2 + 0.14 }, pivot, axis, 1.2),
			{ x = 2.48, y = -0.54, z = 2.14 },
			1e-12
		)
		local point = { x = 0.3, y = 0.9, z = -0.7 }
		for _, angle in { 0.3, 1.1, 2.5, -0.8 } do
			local turned = Hinge.rotate(point, pivot, axis, angle)
			expect(distanceFromAxis(turned, pivot, axis)).toBeNear(
				distanceFromAxis(point, pivot, axis),
				1e-12
			)
		end
		near(Hinge.rotate(point, pivot, axis, 0), point, 1e-12)
	end)

	it("builds a right-handed frame with x along the axis and y as near up as it can be", function()
		local axis = { x = 0.97, y = -0.15, z = 0.17 }
		local x, y, z = Hinge.frame(axis)
		local length = math.sqrt(0.97 ^ 2 + 0.15 ^ 2 + 0.17 ^ 2)
		near(x, { x = 0.97 / length, y = -0.15 / length, z = 0.17 / length }, 1e-12)
		expect(x.x * y.x + x.y * y.y + x.z * y.z).toBeNear(0, 1e-12)
		expect(y.x * y.x + y.y * y.y + y.z * y.z).toBeNear(1, 1e-12)
		near(z, { x = x.y * y.z - x.z * y.y, y = x.z * y.x - x.x * y.z, z = x.x * y.y - x.y * y.x }, 1e-12)
		expect(y.y > 0.98).toBe(true)
	end)

	it("opens the SVJ's door to where Blender's own rotation put it, up and outboard", function()
		local door = SVJModel.door
		assert(door, "the SVJ binding has a door")
		local pivot, axis = Hinge.chassis(door.pivot), Hinge.chassis(door.axis)
		local open = Hinge.rotate(Hinge.chassis(CORNER_SHUT), pivot, axis, door.openAngle)
		near(open, Hinge.chassis(CORNER_OPEN), 0.002)
		local half = Hinge.rotate(Hinge.chassis(CORNER_SHUT), pivot, axis, Hinge.angle(0.5, door.openAngle))
		expect(half.y > Hinge.chassis(CORNER_SHUT).y + 0.5).toBe(true)
		-- Outboard: the driver's door is on the car's left, so further left (smaller x).
		expect(open.x < Hinge.chassis(CORNER_SHUT).x - 0.3).toBe(true)
	end)

	it("lifts the SVJ's START flap by its rear edge", function()
		local flap = SVJModel.flap
		assert(flap, "the SVJ binding has a flap")
		local rearEdge = Hinge.chassis({ forward = flap.pivot.forward - 0.03, right = 0, up = flap.pivot.up })
		local lifted =
			Hinge.rotate(rearEdge, Hinge.chassis(flap.pivot), Hinge.chassis(flap.axis), math.rad(70))
		expect(lifted.y > rearEdge.y + 0.025).toBe(true)
	end)

	it("turns by the openness's share of the open angle, never past shut or open", function()
		expect(Hinge.angle(0, 1.5)).toBe(0)
		expect(Hinge.angle(0.5, 1.5)).toBeNear(0.75, 1e-12)
		expect(Hinge.angle(1, 1.5)).toBeNear(1.5, 1e-12)
		expect(Hinge.angle(-0.2, 1.5)).toBe(0)
		expect(Hinge.angle(1.3, 1.5)).toBeNear(1.5, 1e-12)
	end)

	it("sounds the latch as the door leaves shut and the shut as it comes back, nothing between", function()
		expect(Hinge.sound(0, 0.01)).toBe("Latch")
		expect(Hinge.sound(0.02, 0)).toBe("Shut")
		expect(Hinge.sound(0.3, 0.6)).toBe(nil)
		expect(Hinge.sound(0.6, 0.3)).toBe(nil)
		expect(Hinge.sound(0, 0)).toBe(nil)
		expect(Hinge.sound(1, 1)).toBe(nil)
	end)
end)
