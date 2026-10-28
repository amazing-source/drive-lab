--!strict
local DriverLegs = require("../src/shared/Config/DriverLegs")
local Hinge = require("../src/shared/Rules/Hinge")
local Legs = require("../src/shared/Rules/DriverLegs")
local SVJModel = require("../src/shared/Config/Cars/SVJModel")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

type Binding = { part: string, pivot: Hinge.CarPoint, axis: Hinge.CarPoint }

local function near(actual: Hinge.Vector, expected: Hinge.Vector, tolerance: number)
	expect(actual.x).toBeNear(expected.x, tolerance)
	expect(actual.y).toBeNear(expected.y, tolerance)
	expect(actual.z).toBeNear(expected.z, tolerance)
end

-- A point of Config/DriverLegs (the DriverSeat's frame, whose origin is SVJModel.seat and whose
-- axes are the chassis's) in the chassis's space; the body raise lifts both alike.
local function fromSeat(point: Legs.Vector): Hinge.Vector
	local seat = Hinge.chassis(SVJModel.seat)
	return { x = seat.x + point.x, y = seat.y + point.y, z = seat.z + point.z }
end

local function binding(name: string): Binding
	local pedals = SVJModel.pedals
	assert(pedals, "the SVJ binding has pedals")
	for _, pedal in pedals do
		if pedal.part == name then
			return pedal
		end
	end
	error(`the SVJ binding names no {name}`)
end

describe("SVJ pedals: the rig's hinges against the legs' footwell", function()
	it("hangs each pedal on the hinge Config/DriverLegs measured", function()
		for _, pedal in { DriverLegs.THROTTLE, DriverLegs.BRAKE } do
			local rigged = binding(pedal.part)
			near(Hinge.chassis(rigged.pivot), fromSeat(pedal.hinge), 2e-4)
		end
	end)

	it("turns the rigged pedal's face to where the rule puts the ball of the foot", function()
		for _, pedal in { DriverLegs.THROTTLE, DriverLegs.BRAKE } do
			local rigged = binding(pedal.part)
			for _, press in { 0.25, 0.5, 1 } do
				local angle = pedal.travel * press
				local turned = Hinge.rotate(
					fromSeat(pedal.ball),
					Hinge.chassis(rigged.pivot),
					Hinge.chassis(rigged.axis),
					angle
				)
				near(turned, fromSeat(Legs.turned(pedal, pedal.ball, angle)), 2e-4)
			end
		end
	end)
end)
