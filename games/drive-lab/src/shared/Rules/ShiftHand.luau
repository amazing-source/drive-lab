--!strict
--[[
	Where the gear lever and the driver's right hand are for a car with a manual gear lever: the
	lever (the car's model binding, Binding.Shifter, turned into the seat's frame) at a place in its H
	(a column and a row, as Vehicle/ShiftPlan gives it) with the knob pushed down or not; the hand
	gripping the knob there (Config/DriverShift); and the hand on its way between the wheel and the
	knob by its share, the keyed way bent so it starts on the live steering grip and ends on the live
	knob. Plain numbers, so Lune can test it.
]]
local Binding = require("../Config/Cars/Binding")
local Config = require("../Config/DriverShift")
local Hinge = require("./Hinge")
local StartupArms = require("./StartupArms")
local Types = require("../Config/Cars/Types")

export type Pose = StartupArms.Pose
type Vector = StartupArms.Vector
type Rotation = StartupArms.Rotation

-- A lateral angle per gate column, degrees, positive toward the car's right.
export type Column = { column: number, degrees: number }

-- The lever in the driver's seat frame (metres; x right, y up, z back): its pivot and its knob's
-- centre in neutral; the car's right and back, the axes it turns about (first sideways about the
-- forward axis for its column, then fore and aft about the right axis for its row); each column's
-- lateral angle in order; the fore-and-aft angles (degrees, row +1 forward, row -1 back, both
-- positive); and how far the knob goes down the lever into reverse's lockout.
export type Lever = {
	pivot: Vector,
	knob: Vector,
	right: Vector,
	back: Vector,
	columns: { Column },
	forward: number,
	backward: number,
	push: number,
}

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

local function seatPoint(point: Binding.CarPoint, seat: Binding.CarPoint): Vector
	local a, b = Hinge.chassis(point), Hinge.chassis(seat)
	return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }
end

local function negative(a: Vector): Vector
	return { x = -a.x, y = -a.y, z = -a.z }
end

-- The lever in the seat's frame, from the car's model binding (`shifter`, with the seat's hip point
-- `seat` the DriverSeat sits at, Car/CarRig) and its gearbox's gates (each gear's column and row):
-- each column's angle is its gears' side angle, the rows' angles their gears' fore angles. Errors
-- if two gears of one column, or of one row, disagree.
function ShiftHand.leverFromBinding(
	shifter: Binding.Shifter,
	gates: { [number]: Types.Gate },
	seat: Binding.CarPoint
): Lever
	local byColumn: { [number]: number } = {}
	local forward: number?, backward: number? = nil, nil
	for gear, gate in gates do
		local angles = shifter.gates[if gear < 0 then "R" elseif gear == 0 then "N" else tostring(gear)]
		assert(angles, `the lever's binding has no gate for gear {gear}`)
		local side = math.deg(angles.side)
		local known = byColumn[gate.column]
		assert(
			known == nil or math.abs(known - side) < 1e-3,
			`column {gate.column}'s gears disagree on its angle`
		)
		byColumn[gate.column] = side
		local fore = math.deg(angles.fore) * gate.row
		if gate.row > 0 then
			assert(
				forward == nil or math.abs(forward - fore) < 1e-3,
				"the forward gears disagree on their angle"
			)
			forward = fore
		elseif gate.row < 0 then
			assert(
				backward == nil or math.abs(backward - fore) < 1e-3,
				"the back gears disagree on their angle"
			)
			backward = fore
		end
	end
	local columns: { Column } = {}
	for column, degrees in byColumn do
		table.insert(columns, { column = column, degrees = degrees })
	end
	table.sort(columns, function(a: Column, b: Column): boolean
		return a.column < b.column
	end)
	return {
		pivot = seatPoint(shifter.pivot, seat),
		knob = seatPoint(shifter.knob, seat),
		-- The binding turns the knob forward about axisFore and right about axisSide; this lever turns
		-- about -right and -back for the same moves.
		right = negative(Hinge.chassis(shifter.axisFore)),
		back = negative(Hinge.chassis(shifter.axisSide)),
		columns = columns,
		forward = assert(forward, "no forward gear"),
		backward = assert(backward, "no back gear"),
		push = shifter.push,
	}
end

-- The lateral angle (degrees) of a place between the lever's columns, held past the outer ones.
function ShiftHand.columnAngle(shifter: Lever, column: number): number
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
function ShiftHand.lever(shifter: Lever, column: number, row: number, knob: number): Pose
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

-- The lever's joint at (`column`, `row`) with the knob pushed down by `knob`: its turn about the
-- pivot and the slide after it (metres), so a point p modelled on the lever in neutral goes to
-- pivot + slide + turn (p - pivot).
function ShiftHand.joint(shifter: Lever, column: number, row: number, knob: number): (Rotation, Vector)
	local pose = ShiftHand.lever(shifter, column, row, knob)
	local reach = rotate(pose.rotation, add(shifter.knob, scale(shifter.pivot, -1)))
	return pose.rotation, add(pose.position, scale(add(shifter.pivot, reach), -1))
end

-- The wrist holding the knob whose frame is `knob`.
function ShiftHand.knobWrist(knob: Pose, grip: Config.Key): Pose
	local held = keyPose(grip)
	return {
		position = add(knob.position, rotate(knob.rotation, held.position)),
		rotation = StartupArms.multiply(knob.rotation, held.rotation),
	}
end

-- The right hand with the lever at (`column`, `row`, `knob`) and the hand `share` of the way from
-- the live steering grip `grip` (0) to the knob (1), and the mesh it shows.
function ShiftHand.wrist(
	shift: Config.Shift,
	lever: Lever,
	share: number,
	column: number,
	row: number,
	knob: number,
	grip: Pose
): (Pose, string)
	local knobWrist = ShiftHand.knobWrist(ShiftHand.lever(lever, column, row, knob), shift.grip)
	return ShiftHand.pose(shift, share, grip, knobWrist)
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
