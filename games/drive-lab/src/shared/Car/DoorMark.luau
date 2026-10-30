--!strict
--[[
	Where a character stands to use a car's driver's door: beside the seat, facing it. The
	entry and exit clips are authored from here, so the server checks the character against
	it; getting out ends a little further out (the door's exitEnd), facing the same way. Both
	are the car's own (Config/CarEntry Door).
]]
local Config = require("../Config/CarEntry")
local Units = require("../Units")

local DoorMark = {}

-- A point beside the seat at its height, `right` and `forward` metres in the seat's frame.
local function beside(seat: BasePart, right: number, forward: number): Vector3
	return seat.CFrame:PointToWorldSpace(
		Vector3.new(Units.metresToStuds(right), 0, -Units.metresToStuds(forward))
	)
end

-- At the seat's height, turned to face the seat about the vertical.
function DoorMark.frame(door: Config.Door, seat: BasePart): CFrame
	local position = beside(seat, door.mark.right, door.mark.forward)
	local toward = seat.Position - position
	return CFrame.lookAt(position, position + Vector3.new(toward.X, 0, toward.Z))
end

-- Where getting out ends, at the seat's height, facing as at the mark.
function DoorMark.exitFrame(door: Config.Door, seat: BasePart): CFrame
	return DoorMark.frame(door, seat).Rotation + beside(seat, door.exitEnd.right, door.exitEnd.forward)
end

-- Distance across the ground from the mark, ignoring height.
function DoorMark.distance(door: Config.Door, seat: BasePart, point: Vector3): number
	local delta = point - DoorMark.frame(door, seat).Position
	return Vector3.new(delta.X, 0, delta.Z).Magnitude
end

return table.freeze(DoorMark)
