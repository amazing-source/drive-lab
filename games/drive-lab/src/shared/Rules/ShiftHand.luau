--!strict
--[[
	Where the gear lever and the driver's right hand are for a car with a manual gear lever
	(Config/DriverShift): the lever turned to a place in its H (a column and a row, as
	Vehicle/ShiftPlan gives it) with the knob pushed down or not; the hand gripping the knob there;
	and the hand on its way between the wheel and the knob by its share, the keyed way bent so it
	starts on the live steering grip and ends on the live knob. Plain numbers, so Lune can test it.
]]
local Config = require("../Config/DriverShift")
local StartupArms = require("./StartupArms")

export type Pose = StartupArms.Pose
type Vector = StartupArms.Vector
type Rotation = StartupArms.Rotation

local ShiftHand = {}

local function add(a: Vector, b: Vector): Vector
	return { x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }
end

local function scale(a: Vector, k: number): Vector
	return { x = a.x * k, y = a.y * k, z = a.z * k }
end

local function rotate(q: Rotation, v: Vector): Vector
	local u = { x = q.x, y = q.y, z = q.z }
	local function cross(a: Vector, b: Vector): Vector
		return { x = a.y * b.z - a.z * b.y, y = a.z * b.x - a.x * b.z, z = a.x * b.y - a.y * b.x }
	end
	local t = scale(cross(u, v), 2)
	return add(add(v, scale(t, q.w)), cross(u, t))
end

local function keyPose(key: Config.Key): Pose
	return {
		position = { x = key[2], y = key[3], z = key[4] },
		rotation = { w = key[5], x = key[6], y = key[7], z = key[8] },
	}
end

-- The lateral angle (degrees) of a place between the shifter's columns, held past the outer ones.
function ShiftHand.columnAngle(shifter: Config.Shifter, column: number): number
	local columns = shifter.columns
	if column <= columns[1].column then
		return columns[1].degrees
	end
	for index = 2, #columns do
		local low, high = columns[index - 1], columns[index]
		if column <= high.column then
			local share = (column - low.column) / (high.column - low.column)
			return low.degrees + (high.degrees - low.degrees) * share
		end
	end
	return columns[#columns].degrees
end

local function axisAngle(axis: Vector, degrees: number): Rotation
	local half = math.rad(degrees) / 2
	local s = math.sin(half)
	return { w = math.cos(half), x = axis.x * s, y = axis.y * s, z = axis.z * s }
end

-- The knob's frame with the lever at (`column`, `row`) and the knob pushed down by `knob` (0 to 1):
-- origin at the knob's centre, axes the seat's turned with the lever. As the manifest's gate motion
-- turns it: sideways about the forward axis for the column (positive to the car's right), then fore
-- and aft about the car's right for the row (positive forward), both about the pivot.
function ShiftHand.lever(shifter: Config.Shifter, column: number, row: number, knob: number): Pose
	local right, back = shifter.right, shifter.back
	local side = axisAngle(scale(back, -1), ShiftHand.columnAngle(shifter, column))
	local fore =
		axisAngle(scale(right, -1), if row >= 0 then shifter.forward * row else shifter.backward * row)
	local turn = StartupArms.multiply(fore, side)
	local offset = rotate(turn, add(shifter.knob, scale(shifter.pivot, -1)))
	local length = math.sqrt(offset.x ^ 2 + offset.y ^ 2 + offset.z ^ 2)
	local pushed = shifter.push * math.clamp(knob, 0, 1) / length
	return {
		position = add(shifter.pivot, scale(offset, 1 - pushed)),
		rotation = turn,
	}
end

-- The wrist holding the knob whose frame is `knob`.
function ShiftHand.knobWrist(knob: Pose, grip: Config.Key): Pose
	local held = keyPose(grip)
	return {
		position = add(knob.position, rotate(knob.rotation, held.position)),
		rotation = StartupArms.multiply(knob.rotation, held.rotation),
	}
end

-- The right hand `share` of the way from the wheel (0) to the knob (1), and the mesh it shows. The
-- keyed way keeps its shape; its start is carried onto `grip` (the live steering grip) and its end
-- onto `knobWrist` (the hand on the knob where the lever is now), the end's share growing along it.
function ShiftHand.pose(shift: Config.Shift, share: number, grip: Pose, knobWrist: Pose): (Pose, string)
	local keys = shift.hand.keys
	local first, last = keys[1], keys[#keys]
	local u = math.clamp(share, 0, 1)
	local t = first[1] + (last[1] - first[1]) * u
	local toEnd = u * u * (3 - 2 * u)
	local pose = StartupArms.sample(keys, t)
	pose = StartupArms.retarget(pose, keyPose(first), grip, 1 - toEnd)
	pose = StartupArms.retarget(pose, keyPose(last), knobWrist, toEnd)
	local shape = shift.hand.shapes[1].shape
	for _, change in shift.hand.shapes do
		if t >= change.at then
			shape = change.shape
		end
	end
	return pose, shape
end

return table.freeze(ShiftHand)
