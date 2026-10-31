--!strict
--[[
	The maths of a part that turns on a hinge, a car's door or its START flap: the frame a hinge
	weld is built on, where a point goes as the part turns, how far it turns for an openness, and
	when a door's latch and shut sound. Vectors are in the chassis's own space, Roblox's: x right,
	y up, z toward the back, so a turn follows the right-hand rule like CFrame.fromAxisAngle.
]]
export type Vector = { x: number, y: number, z: number }

-- A point or a direction in the car frame, metres, as the model bindings write them.
export type CarPoint = { forward: number, right: number, up: number }

export type DoorSound = "Latch" | "Shut"

local Hinge = {}

function Hinge.chassis(point: CarPoint): Vector
	return { x = point.right, y = point.up, z = -point.forward }
end

local function dot(a: Vector, b: Vector): number
	return a.x * b.x + a.y * b.y + a.z * b.z
end

local function cross(a: Vector, b: Vector): Vector
	return { x = a.y * b.z - a.z * b.y, y = a.z * b.x - a.x * b.z, z = a.x * b.y - a.y * b.x }
end

local function scaled(a: Vector, k: number): Vector
	return { x = a.x * k, y = a.y * k, z = a.z * k }
end

local function unit(a: Vector): Vector
	local length = math.sqrt(dot(a, a))
	assert(length > 1e-9, "a hinge axis needs a length")
	return scaled(a, 1 / length)
end

-- A right-handed frame whose x is the axis and whose y is as near the chassis's up as the axis
-- allows: the weld's C0, so turning it about its own x turns the part about the hinge.
function Hinge.frame(axis: Vector): (Vector, Vector, Vector)
	local x = unit(axis)
	local up = if math.abs(x.y) < 0.99 then { x = 0, y = 1, z = 0 } else { x = 0, y = 0, z = -1 }
	local along = dot(up, x)
	local y = unit({ x = up.x - x.x * along, y = up.y - x.y * along, z = up.z - x.z * along })
	return x, y, cross(x, y)
end

-- A steering column's frame: z along the axis (toward the driver), y as near the chassis's up as
-- the axis allows, x to the right. A hub built on it turns the wheel about its own z, as a
-- steering wheel's pivot does (Car/VehicleRunner).
function Hinge.column(axis: Vector): (Vector, Vector, Vector)
	local z = unit(axis)
	local up = if math.abs(z.y) < 0.99 then { x = 0, y = 1, z = 0 } else { x = 0, y = 0, z = -1 }
	local along = dot(up, z)
	local y = unit({ x = up.x - z.x * along, y = up.y - z.y * along, z = up.z - z.z * along })
	return cross(y, z), y, z
end

-- `point` turned by `angle` radians about the line through `pivot` along `axis` (Rodrigues).
function Hinge.rotate(point: Vector, pivot: Vector, axis: Vector, angle: number): Vector
	local k = unit(axis)
	local v = { x = point.x - pivot.x, y = point.y - pivot.y, z = point.z - pivot.z }
	local cos, sin = math.cos(angle), math.sin(angle)
	local across = cross(k, v)
	local along = dot(k, v) * (1 - cos)
	return {
		x = pivot.x + v.x * cos + across.x * sin + k.x * along,
		y = pivot.y + v.y * cos + across.y * sin + k.y * along,
		z = pivot.z + v.z * cos + across.z * sin + k.z * along,
	}
end

-- The turn, in radians, for an openness from 0 (shut) to 1 (fully open).
function Hinge.angle(openness: number, openAngle: number): number
	return math.clamp(openness, 0, 1) * openAngle
end

-- The sound a door makes between two readings of its openness: the latch as it leaves shut, the
-- shut as it comes back to it.
function Hinge.sound(before: number, after: number): DoorSound?
	if before <= 0 and after > 0 then
		return "Latch"
	elseif before > 0 and after <= 0 then
		return "Shut"
	end
	return nil
end

return table.freeze(Hinge)
