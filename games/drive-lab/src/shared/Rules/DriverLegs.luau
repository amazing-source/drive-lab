--!strict
--[[
	Where the seated driver's legs go: the right foot on the throttle, or over on the brake while
	it is pressed (one foot, as real drivers do), the left on the footrest, each pedal turned by
	its readout, and the knee placed by a two-bone reach from the hip. Metres in the driver's seat
	frame (x right, y up, z back); plain numbers, so Lune can test it.
]]
local ArmIK = require("./ArmIK")
local Config = require("../Config/DriverLegs")

export type Vector = Config.Point
export type Leg = {
	hip: Vector,
	knee: Vector,
	ankle: Vector,
	-- The shoe's frame: along the sole from heel to toes, and up out of the instep.
	forward: Vector,
	up: Vector,
	-- How far the ankle actually is from the hip; less than asked only out of the leg's reach.
	reach: number,
}

local SIDEWAYS: Vector = table.freeze({ x = 1, y = 0, z = 0 })
-- The way the ball of the foot lifts between the pedals, the heel planted: up and back, so the
-- toes clear the pads while the knee stays down.
local LIFT_DIRECTION: Vector = table.freeze({ x = 0, y = 0.8, z = 0.6 })

local DriverLegs = {}

local function add(a: Vector, b: Vector): Vector
	return { x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }
end

local function sub(a: Vector, b: Vector): Vector
	return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }
end

local function scale(a: Vector, k: number): Vector
	return { x = a.x * k, y = a.y * k, z = a.z * k }
end

local function dot(a: Vector, b: Vector): number
	return a.x * b.x + a.y * b.y + a.z * b.z
end

local function cross(a: Vector, b: Vector): Vector
	return { x = a.y * b.z - a.z * b.y, y = a.z * b.x - a.x * b.z, z = a.x * b.y - a.y * b.x }
end

local function unit(a: Vector): Vector
	return scale(a, 1 / math.sqrt(dot(a, a)))
end

local function lerp(a: Vector, b: Vector, share: number): Vector
	return add(a, scale(sub(b, a), share))
end

local function ease(share: number): number
	return share * share * (3 - 2 * share)
end

-- 0 with the right foot on the throttle, 1 on the brake; it crosses at a steady rate.
function DriverLegs.approach(over: number, wantBrake: boolean, dt: number): number
	local step = dt / Config.SWITCH_SECONDS
	return math.clamp(if wantBrake then over + step else over - step, 0, 1)
end

function DriverLegs.wantsBrake(brake: number): boolean
	return brake > Config.BRAKE_THRESHOLD
end

-- Each pedal's angle (radians about its hinge): a pedal goes down only under the foot.
function DriverLegs.pedalAngles(
	footwell: Config.Footwell,
	over: number,
	throttle: number,
	brake: number
): (number, number)
	local onBrake = ease(over)
	return footwell.throttle.travel * math.clamp(throttle, 0, 1) * (1 - onBrake),
		footwell.brake.travel * math.clamp(brake, 0, 1) * onBrake
end

-- `point` turned with a pedal by `angle` about the hinge's x axis.
function DriverLegs.turned(pedal: Config.Pedal, point: Vector, angle: number): Vector
	local offset = sub(point, pedal.hinge)
	local cosine, sine = math.cos(angle), math.sin(angle)
	return add(pedal.hinge, {
		x = offset.x,
		y = offset.y * cosine - offset.z * sine,
		z = offset.y * sine + offset.z * cosine,
	})
end

-- The heel under a sole whose ball rides a hung pedal: where it rested on the floor, slid along
-- the car (z) until heel to ball is the sole's length at rest again.
local function heelOnFloor(pedal: Config.Pedal, ball: Vector): Vector
	local rest = sub(pedal.ball, pedal.heel)
	local across, up = ball.x - pedal.heel.x, ball.y - pedal.heel.y
	local along = math.sqrt(math.max(dot(rest, rest) - across * across - up * up, 0))
	return { x = pedal.heel.x, y = pedal.heel.y, z = ball.z + along }
end

-- Where the right sole meets its pedal: lying on the throttle's plate and turning with it, or the
-- heel on the floor and the ball on the brake's pad; in between the heel slides across the floor
-- while the ball lifts over the pads.
function DriverLegs.rightSole(
	footwell: Config.Footwell,
	over: number,
	throttleAngle: number,
	brakeAngle: number
): (Vector, Vector)
	local throttle, brake = footwell.throttle, footwell.brake
	local share = ease(over)
	local lift = scale(LIFT_DIRECTION, Config.SWITCH_LIFT * 4 * over * (1 - over))
	local throttleBall = DriverLegs.turned(throttle, throttle.ball, throttleAngle)
	local brakeBall = DriverLegs.turned(brake, brake.ball, brakeAngle)
	local throttleHeel = if throttle.hangs
		then heelOnFloor(throttle, throttleBall)
		else DriverLegs.turned(throttle, throttle.heel, throttleAngle)
	local brakeHeel = if brake.hangs then heelOnFloor(brake, brakeBall) else brake.heel
	return lerp(throttleHeel, brakeHeel, share), add(lerp(throttleBall, brakeBall, share), lift)
end

-- The shoe's frame from where its sole meets the pedal, and the ankle joint above that.
local function shoe(heel: Vector, ball: Vector): (Vector, Vector, Vector)
	local forward = unit(sub(ball, heel))
	local up = unit(cross(SIDEWAYS, forward))
	return forward, up, add(heel, add(scale(forward, Config.ANKLE_ALONG), scale(up, Config.ANKLE_UP)))
end

local function leg(hip: Vector, heel: Vector, ball: Vector, toward: Vector): Leg
	local forward, up, ankle = shoe(heel, ball)
	local toAnkle = sub(ankle, hip)
	local distance = math.sqrt(dot(toAnkle, toAnkle))
	local solved = ArmIK.solve(Config.THIGH, Config.SHIN, distance)
	local along = scale(toAnkle, 1 / distance)
	local pole = sub(toward, hip)
	local bend = unit(sub(pole, scale(along, dot(pole, along))))
	local knee = add(
		hip,
		add(
			scale(along, Config.THIGH * math.cos(solved.bend)),
			scale(bend, Config.THIGH * math.sin(solved.bend))
		)
	)
	return {
		hip = hip,
		knee = knee,
		ankle = add(hip, scale(along, solved.reach)),
		forward = forward,
		up = up,
		reach = solved.reach,
	}
end

function DriverLegs.right(
	footwell: Config.Footwell,
	hip: Vector,
	over: number,
	throttleAngle: number,
	brakeAngle: number
): Leg
	local heel, ball = DriverLegs.rightSole(footwell, over, throttleAngle, brakeAngle)
	return leg(hip, heel, ball, footwell.kneeToward.right)
end

-- The clutch's angle (radians about its hinge): it goes down only under the foot. `onClutch` is how
-- far the left foot has come from the footrest onto the clutch, 0 to 1; `clutch` the pedal's
-- press, 0 up to 1 down. 0 in a car without a clutch.
function DriverLegs.clutchAngle(footwell: Config.Footwell, onClutch: number, clutch: number): number
	local pedal = footwell.clutch
	if pedal == nil then
		return 0
	end
	return pedal.travel * math.clamp(clutch, 0, 1) * ease(math.clamp(onClutch, 0, 1))
end

-- Where the left sole is: on the footrest, or the heel on the floor and the ball on the clutch's
-- pad turning with it; in between the heel slides across the floor while the ball lifts over the
-- pads, as the right foot crosses between its pedals.
function DriverLegs.leftSole(
	footwell: Config.Footwell,
	onClutch: number,
	clutchAngle: number
): (Vector, Vector)
	local rest, pedal = footwell.footrest, footwell.clutch
	if pedal == nil then
		return rest.heel, rest.ball
	end
	local over = math.clamp(onClutch, 0, 1)
	local share = ease(over)
	local lift = scale(LIFT_DIRECTION, Config.SWITCH_LIFT * 4 * over * (1 - over))
	local ball = DriverLegs.turned(pedal, pedal.ball, clutchAngle)
	local heel = if pedal.hangs then heelOnFloor(pedal, ball) else pedal.heel
	return lerp(rest.heel, heel, share), add(lerp(rest.ball, ball, share), lift)
end

-- `onClutch` and `clutchAngle` default to the foot on its footrest.
function DriverLegs.left(footwell: Config.Footwell, hip: Vector, onClutch: number?, clutchAngle: number?): Leg
	local heel, ball = DriverLegs.leftSole(footwell, onClutch or 0, clutchAngle or 0)
	return leg(hip, heel, ball, footwell.kneeToward.left)
end

-- The ankle a sole asks for, before the leg's reach is applied.
function DriverLegs.ankleFor(heel: Vector, ball: Vector): Vector
	local _, _, ankle = shoe(heel, ball)
	return ankle
end

return table.freeze(DriverLegs)
