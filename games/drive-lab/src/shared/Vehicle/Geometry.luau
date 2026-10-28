--!strict
--[[
	Where the wheels sit and what each one carries at rest. Every module and the Roblox glue
	index wheels the same way: 1 = front left, 2 = front right, 3 = rear left, 4 = rear right.
	Positions are relative to the centre of mass in the car frame: forward and right, in m.
]]
local Types = require("../Config/Cars/Types")

export type WheelPosition = { forward: number, right: number }

local Geometry = {
	WHEELS = 4,
	FRONT_LEFT = 1,
	FRONT_RIGHT = 2,
	REAR_LEFT = 3,
	REAR_RIGHT = 4,
}

function Geometry.isFront(wheel: number): boolean
	return wheel <= 2
end

function Geometry.isLeft(wheel: number): boolean
	return wheel % 2 == 1
end

-- The other wheel on the same axle.
function Geometry.partner(wheel: number): number
	return if Geometry.isLeft(wheel) then wheel + 1 else wheel - 1
end

function Geometry.axle(car: Types.CarConfig, wheel: number): Types.AxleConfig
	return if Geometry.isFront(wheel) then car.front else car.rear
end

-- Distance from the front axle back to the centre of mass: the rear weight share of the
-- wheelbase, since the static loads balance about it.
function Geometry.frontAxleDistance(car: Types.CarConfig): number
	return (1 - car.frontWeightShare) * car.wheelbase
end

function Geometry.wheelPositions(car: Types.CarConfig): { WheelPosition }
	local front = Geometry.frontAxleDistance(car)
	local rear = front - car.wheelbase
	return {
		{ forward = front, right = -car.front.track / 2 },
		{ forward = front, right = car.front.track / 2 },
		{ forward = rear, right = -car.rear.track / 2 },
		{ forward = rear, right = car.rear.track / 2 },
	}
end

-- Whole-car mass resting on one corner, unsprung mass included.
function Geometry.cornerMass(car: Types.CarConfig, wheel: number): number
	local share = if Geometry.isFront(wheel) then car.frontWeightShare else 1 - car.frontWeightShare
	return car.mass * share / 2
end

function Geometry.sprungCornerMass(car: Types.CarConfig, wheel: number): number
	return Geometry.cornerMass(car, wheel) - Geometry.axle(car, wheel).unsprungMass
end

return table.freeze(Geometry)
