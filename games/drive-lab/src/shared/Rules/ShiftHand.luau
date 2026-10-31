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

-- The rotation whose matrix has columns `x`, `y`, `z` (orthonormal).
local function fromAxes(x: Vector, y: Vector, z: Vector): Rotation
	local trace = x.x + y.y + z.z
	local w, qx, qy, qz
	if trace > 0 then
		local s = math.sqrt(trace + 1) * 2
		w, qx, qy, qz = s / 4, (y.z - z.y) / s, (z.x - x.z) / s, (x.y - y.x) / s
	elseif x.x > y.y and x.x > z.z then
		local s = math.sqrt(1 + x.x - y.y - z.z) * 2
		w, qx, qy, qz = (y.z - z.y) / s, s / 4, (y.x + x.y) / s, (z.x + x.z) / s
	elseif y.y > z.z then
		local s = math.sqrt(1 + y.y - x.x - z.z) * 2
		w, qx, qy, qz = (z.x - x.z) / s, (y.x + x.y) / s, s / 4, (z.y + y.z) / s
	else
		local s = math.sqrt(1 + z.z - x.x - y.y) * 2
		w, qx, qy, qz = (x.y - y.x) / s, (z.x + x.z) / s, (z.y + y.z) / s, s / 4
	end
	return { w = w, x = qx, y = qy, z = qz }
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

-- The knob's frame with the lever at (`column`, `row`) and the knob pushed down by `knob` (0 to 1):
-- origin at the knob's centre, axes the lever's (across, up it, toward the driver). The lever leans
-- sideways for the column, then fore and aft for the row, about its pivot.
function ShiftHand.lever(shifter: Config.Shifter, column: number, row: number, knob: number): Pose
	local side = math.rad(ShiftHand.columnAngle(shifter, column))
	local tilt = math.rad(if row >= 0 then shifter.forward * row else shifter.backward * row)
	local right0, up0, back = shifter.right, shifter.up, shifter.back
	local up1 = add(scale(up0, math.cos(side)), scale(right0, math.sin(side)))
	local right = add(scale(right0, math.cos(side)), scale(up0, -math.sin(side)))
	local up = add(scale(up1, math.cos(tilt)), scale(back, -math.sin(tilt)))
	local towardDriver = add(scale(back, math.cos(tilt)), scale(up1, math.sin(tilt)))
	local reach = shifter.length - shifter.push * math.clamp(knob, 0, 1)
	return {
		position = add(shifter.pivot, scale(up, reach)),
		rotation = fromAxes(right, up, towardDriver),
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
