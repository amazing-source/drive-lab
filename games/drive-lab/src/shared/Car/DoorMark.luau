--!strict
--[[
	Where a character stands to use a car's driver's door: beside the seat, facing it. The
	entry and exit clips are authored from here, so the server checks the character against
	it and puts it back here on the way out.
]]
local Config = require("../Config/CarEntry")
local Units = require("../Units")

local DoorMark = {}

-- At the seat's height, turned to face the seat about the vertical.
function DoorMark.frame(seat: BasePart): CFrame
	local offset =
		Vector3.new(Units.metresToStuds(Config.MARK.right), 0, -Units.metresToStuds(Config.MARK.forward))
	local position = seat.CFrame:PointToWorldSpace(offset)
	local toward = seat.Position - position
	return CFrame.lookAt(position, position + Vector3.new(toward.X, 0, toward.Z))
end

-- Distance across the ground from the mark, ignoring height.
function DoorMark.distance(seat: BasePart, point: Vector3): number
	local delta = point - DoorMark.frame(seat).Position
	return Vector3.new(delta.X, 0, delta.Z).Magnitude
end

return table.freeze(DoorMark)
