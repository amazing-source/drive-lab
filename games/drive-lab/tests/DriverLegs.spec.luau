--!strict
local Config = require("../src/shared/Config/DriverLegs")
local Legs = require("../src/shared/Rules/DriverLegs")
local SVJ = require("../src/shared/Config/Cars/SVJ")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local FOOTWELL = SVJ.driver.footwell

type Vector = Legs.Vector

local function distance(a: Vector, b: Vector): number
	return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
end

local function minus(a: Vector, b: Vector): Vector
	return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }
end

local function dot(a: Vector, b: Vector): number
	return a.x * b.x + a.y * b.y + a.z * b.z
end

-- The seated driver's hips in the seat frame, metres: Roblox's sit pose at Driving.DRIVER_SCALE,
-- the torso's centre measured at (0, 1.557, 0) studs (drive-lab-assets/driver/SEAT_WELD.json)
-- plus Config.HIP at that scale.
local RIGHT_HIP: Vector = { x = 0.08, y = 0.1227, z = 0.008 }
local LEFT_HIP: Vector = { x = -0.08, y = 0.1226, z = 0.008 }

describe("Driver legs: the right foot between the pedals", function()
	it("crosses from the throttle to the brake in the configured time, and back", function()
		local over = 0
		for _ = 1, 10 do
			over = Legs.approach(over, true, Config.SWITCH_SECONDS / 10)
		end
		expect(over).toBeNear(1, 1e-9)
		expect(Legs.approach(1, true, 1)).toBe(1)
		expect(Legs.approach(1, false, Config.SWITCH_SECONDS / 2)).toBeNear(0.5, 1e-9)
		expect(Legs.approach(0, false, 1)).toBe(0)
	end)

	it("goes for the brake only once the brake readout is above its threshold", function()
		expect(Legs.wantsBrake(0)).toBe(false)
		expect(Legs.wantsBrake(Config.BRAKE_THRESHOLD)).toBe(false)
		expect(Legs.wantsBrake(0.5)).toBe(true)
	end)

	it("lies on the throttle, then on the brake, rocking on its heel between them", function()
		local heel, ball = Legs.rightSole(FOOTWELL, 0, 0, 0)
		expect(distance(heel, FOOTWELL.throttle.heel)).toBeNear(0, 1e-9)
		expect(distance(ball, FOOTWELL.throttle.ball)).toBeNear(0, 1e-9)
		heel, ball = Legs.rightSole(FOOTWELL, 1, 0, 0)
		expect(distance(heel, FOOTWELL.brake.heel)).toBeNear(0, 1e-9)
		expect(distance(ball, FOOTWELL.brake.ball)).toBeNear(0, 1e-9)
		local midHeel, midBall = Legs.rightSole(FOOTWELL, 0.5, 0, 0)
		local straight = (FOOTWELL.throttle.ball.y + FOOTWELL.brake.ball.y) / 2
		expect(midBall.y > straight + Config.SWITCH_LIFT / 2).toBe(true)
		expect(midHeel.y).toBeNear((FOOTWELL.throttle.heel.y + FOOTWELL.brake.heel.y) / 2, 1e-9)
	end)
end)

describe("Driver legs: pedals", function()
	it("pushes each pedal's face toward the nose, about its hinge", function()
		for _, pedal in { FOOTWELL.throttle, FOOTWELL.brake } do
			local pressed = Legs.turned(pedal, pedal.ball, pedal.travel)
			expect(pressed.z < pedal.ball.z - 0.02).toBe(true)
			expect(distance(pressed, pedal.hinge)).toBeNear(distance(pedal.ball, pedal.hinge), 1e-9)
		end
	end)

	it("moves only the pedal under the foot, by its readout", function()
		local throttle, brake = Legs.pedalAngles(FOOTWELL, 0, 1, 0)
		expect(throttle).toBeNear(FOOTWELL.throttle.travel, 1e-9)
		expect(brake).toBe(0)
		throttle, brake = Legs.pedalAngles(FOOTWELL, 1, 1, 0.5)
		expect(throttle).toBe(0)
		expect(brake).toBeNear(FOOTWELL.brake.travel / 2, 1e-9)
		throttle, brake = Legs.pedalAngles(FOOTWELL, 0, 0, 1)
		expect(throttle).toBe(0)
		expect(brake).toBe(0)
	end)

	it("carries the foot down with the throttle", function()
		local _, rest = Legs.rightSole(FOOTWELL, 0, 0, 0)
		local _, floored = Legs.rightSole(FOOTWELL, 0, FOOTWELL.throttle.travel, 0)
		expect(floored.z < rest.z).toBe(true)
		expect(floored.y < rest.y).toBe(true)
	end)
end)

describe("Driver legs: the reach from the hip", function()
	it("keeps the thigh and shin lengths and bends each knee up, toward its point", function()
		local cases = {
			{ leg = Legs.right(FOOTWELL, RIGHT_HIP, 0, 0, 0), toward = FOOTWELL.kneeToward.right },
			{
				leg = Legs.right(FOOTWELL, RIGHT_HIP, 1, 0, FOOTWELL.brake.travel),
				toward = FOOTWELL.kneeToward.right,
			},
			{ leg = Legs.right(FOOTWELL, RIGHT_HIP, 0.5, 0, 0), toward = FOOTWELL.kneeToward.right },
			{ leg = Legs.left(FOOTWELL, LEFT_HIP), toward = FOOTWELL.kneeToward.left },
		}
		for _, case in cases do
			local leg = case.leg
			expect(distance(leg.knee, leg.hip)).toBeNear(Config.THIGH, 1e-9)
			expect(distance(leg.ankle, leg.knee)).toBeNear(Config.SHIN, 1e-6)
			-- The knee's and the point's offsets from the hip-to-ankle line, both across it.
			local along = minus(leg.ankle, leg.hip)
			local function across(point: Vector): Vector
				local offset = minus(point, leg.hip)
				local share = dot(offset, along) / dot(along, along)
				return minus(offset, { x = along.x * share, y = along.y * share, z = along.z * share })
			end
			local knee, toward = across(leg.knee), across(case.toward)
			local cosine = dot(knee, toward) / math.sqrt(dot(knee, knee) * dot(toward, toward))
			expect(cosine).toBeNear(1, 1e-9)
			expect(knee.y > 0).toBe(true)
		end
		local right = Legs.right(FOOTWELL, RIGHT_HIP, 0, 0, 0)
		local left = Legs.left(FOOTWELL, LEFT_HIP)
		expect(right.knee.x > left.knee.x + 0.3).toBe(true)
	end)

	it("reaches every foot position from the seated hips with the knee still bent", function()
		local cases = {
			Legs.right(FOOTWELL, RIGHT_HIP, 0, 0, 0),
			Legs.right(FOOTWELL, RIGHT_HIP, 0, FOOTWELL.throttle.travel, 0),
			Legs.right(FOOTWELL, RIGHT_HIP, 1, 0, FOOTWELL.brake.travel),
			Legs.right(FOOTWELL, RIGHT_HIP, 0.5, 0, 0),
			Legs.left(FOOTWELL, LEFT_HIP),
		}
		for _, leg in cases do
			local asked = distance(leg.hip, leg.ankle)
			expect(leg.reach).toBeNear(asked, 1e-9)
			expect(asked < (Config.THIGH + Config.SHIN) * 0.985).toBe(true)
		end
	end)

	it("stands the shoe on its sole: the ankle above the heel and up out of the instep", function()
		local leg = Legs.right(FOOTWELL, RIGHT_HIP, 0, 0, 0)
		expect(leg.up.y > 0.3).toBe(true)
		expect(leg.forward.z < 0).toBe(true)
		local heel = Legs.rightSole(FOOTWELL, 0, 0, 0)
		expect(leg.ankle.y > heel.y).toBe(true)
	end)
end)

local function copy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for key, child in value do
		out[key] = copy(child)
	end
	return out
end

describe("Driver legs, per car", function()
	it("presses the car's own pedals by their own travel", function()
		-- A throttle with twice the travel, set 2 cm further right.
		local other = copy(FOOTWELL)
		other.throttle.travel *= 2
		for _, point in { other.throttle.hinge, other.throttle.heel, other.throttle.ball } do
			point.x += 0.02
		end
		local throttle = Legs.pedalAngles(other, 0, 1, 0)
		expect(throttle).toBeNear(FOOTWELL.throttle.travel * 2, 1e-9)
		local heel, ball = Legs.rightSole(other, 0, 0, 0)
		expect(distance(heel, other.throttle.heel)).toBeNear(0, 1e-9)
		expect(distance(ball, other.throttle.ball)).toBeNear(0, 1e-9)
	end)

	it("rests the left foot on the car's own footrest", function()
		local other = copy(FOOTWELL)
		for _, point in { other.footrest.heel, other.footrest.ball } do
			point.x -= 0.03
		end
		local ankle = Legs.left(other, LEFT_HIP).ankle
		expect(distance(ankle, Legs.ankleFor(other.footrest.heel, other.footrest.ball))).toBeNear(0, 1e-6)
		expect(ankle.x).toBeNear(Legs.left(FOOTWELL, LEFT_HIP).ankle.x - 0.03, 1e-6)
	end)

	it("bends each knee toward the car's own point", function()
		local other = copy(FOOTWELL)
		other.kneeToward.right.y += 0.2
		other.kneeToward.left.y += 0.2
		local pairs = {
			{ Legs.right(FOOTWELL, RIGHT_HIP, 0, 0, 0), Legs.right(other, RIGHT_HIP, 0, 0, 0) },
			{ Legs.left(FOOTWELL, LEFT_HIP), Legs.left(other, LEFT_HIP) },
		}
		for _, pair in pairs do
			local mine, theirs = pair[1], pair[2]
			expect(distance(mine.ankle, theirs.ankle)).toBeNear(0, 1e-9)
			expect(distance(mine.knee, theirs.knee) > 0.005).toBe(true)
		end
	end)
end)

-- A clutch for the specs: the SVJ's brake moved 13 cm toward the door and 6 cm toward the driver
-- (the SVJ has no clutch; a car's real one comes from tools/blender/footwell.py).
local function withClutch(): any
	local footwell = copy(FOOTWELL)
	local clutch = copy(FOOTWELL.brake)
	clutch.part = "Pedal_Clutch"
	for _, point in { clutch.hinge, clutch.heel, clutch.ball } do
		point.x -= 0.13
		point.z += 0.06
	end
	footwell.clutch = clutch
	return footwell
end

describe("Driver legs: the left foot on a clutch", function()
	it("keeps the left foot on its footrest in a car without a clutch, whatever the inputs", function()
		local rest = Legs.left(FOOTWELL, LEFT_HIP)
		local asked = Legs.left(FOOTWELL, LEFT_HIP, 1, 0.3)
		expect(distance(asked.ankle, rest.ankle)).toBe(0)
		expect(distance(asked.knee, rest.knee)).toBe(0)
		expect(Legs.clutchAngle(FOOTWELL, 1, 1)).toBe(0)
	end)

	it("moves the sole from the footrest onto the clutch, rocking on its heel", function()
		local footwell = withClutch()
		local heel, ball = Legs.leftSole(footwell, 0, 0)
		expect(distance(heel, footwell.footrest.heel)).toBeNear(0, 1e-9)
		expect(distance(ball, footwell.footrest.ball)).toBeNear(0, 1e-9)
		heel, ball = Legs.leftSole(footwell, 1, 0)
		expect(distance(heel, footwell.clutch.heel)).toBeNear(0, 1e-9)
		expect(distance(ball, footwell.clutch.ball)).toBeNear(0, 1e-9)
		local midHeel, midBall = Legs.leftSole(footwell, 0.5, 0)
		local straight = (footwell.footrest.ball.y + footwell.clutch.ball.y) / 2
		expect(midBall.y > straight + Config.SWITCH_LIFT / 2).toBe(true)
		expect(midHeel.y).toBeNear((footwell.footrest.heel.y + footwell.clutch.heel.y) / 2, 1e-9)
	end)

	it("presses the clutch only under the foot, by its value", function()
		local footwell = withClutch()
		local travel = footwell.clutch.travel
		expect(Legs.clutchAngle(footwell, 0, 1)).toBe(0)
		expect(Legs.clutchAngle(footwell, 1, 1)).toBeNear(travel, 1e-12)
		expect(Legs.clutchAngle(footwell, 1, 0.5)).toBeNear(travel / 2, 1e-12)
		expect(Legs.clutchAngle(footwell, 1, 0)).toBe(0)
		local halfWay = Legs.clutchAngle(footwell, 0.5, 1)
		expect(math.abs(halfWay) > 0 and math.abs(halfWay) < math.abs(travel)).toBe(true)
		expect(Legs.clutchAngle(footwell, 2, 3)).toBeNear(travel, 1e-12)
	end)

	it("carries the ball down with the clutch, about the clutch's hinge", function()
		local footwell = withClutch()
		local pedal = footwell.clutch
		local _, rest = Legs.leftSole(footwell, 1, 0)
		local _, pressed = Legs.leftSole(footwell, 1, pedal.travel)
		expect(pressed.z < rest.z - 0.02).toBe(true)
		expect(distance(pressed, pedal.hinge)).toBeNear(distance(rest, pedal.hinge), 1e-9)
	end)

	it("reaches the pressed clutch from the seated hips with the knee bent toward its point", function()
		local footwell = withClutch()
		local leg = Legs.left(footwell, LEFT_HIP, 1, footwell.clutch.travel)
		local asked = distance(leg.hip, leg.ankle)
		expect(leg.reach).toBeNear(asked, 1e-9)
		expect(asked < (Config.THIGH + Config.SHIN) * 0.985).toBe(true)
		expect(distance(leg.knee, leg.hip)).toBeNear(Config.THIGH, 1e-9)
		expect(leg.knee.y > leg.hip.y - Config.THIGH).toBe(true)
	end)
end)

-- Every pedal of the footwell marked as hung from above (the Boss 302's are).
local function hung(footwell: any): any
	for _, name in { "throttle", "brake", "clutch" } do
		if footwell[name] then
			footwell[name].hangs = true
		end
	end
	return footwell
end

-- A throttle hung from above for the specs: the SVJ's brake moved 15 cm toward the console.
local function withHungThrottle(): any
	local footwell = copy(FOOTWELL)
	local throttle = copy(FOOTWELL.brake)
	throttle.part = "Pedal_Throttle"
	for _, point in { throttle.hinge, throttle.heel, throttle.ball } do
		point.x += 0.15
	end
	footwell.throttle = throttle
	return footwell
end

describe("Driver legs: pedals hung from above", function()
	it("keeps the organ throttle's heel turning with its plate and the brake's heel put", function()
		local throttle, brake = FOOTWELL.throttle, FOOTWELL.brake
		local heel = Legs.rightSole(FOOTWELL, 0, throttle.travel, 0)
		expect(distance(heel, Legs.turned(throttle, throttle.heel, throttle.travel))).toBeNear(0, 1e-12)
		heel = Legs.rightSole(FOOTWELL, 1, 0, brake.travel)
		expect(distance(heel, brake.heel)).toBeNear(0, 1e-12)
	end)

	it("keeps the sole's length on a hung clutch, the heel sliding along the floor", function()
		local footwell = hung(withClutch())
		local pedal = footwell.clutch
		local length = distance(pedal.heel, pedal.ball)
		local heel = Legs.leftSole(footwell, 1, 0)
		expect(distance(heel, pedal.heel)).toBeNear(0, 1e-9)
		local ball
		heel, ball = Legs.leftSole(footwell, 1, pedal.travel)
		expect(distance(heel, ball)).toBeNear(length, 1e-9)
		expect(heel.y).toBeNear(pedal.heel.y, 1e-12)
		expect(heel.x).toBeNear(pedal.heel.x, 1e-12)
		-- which way it slides depends on how far the ball drops against how far it goes forward
		expect(math.abs(heel.z - pedal.heel.z) > 0.002).toBe(true)
	end)

	it("keeps the right heel on the floor under hung pedals, the sole's length kept", function()
		local footwell = hung(withHungThrottle())
		for _, case in { { 0, "throttle" }, { 1, "brake" } } do
			local pedal = footwell[case[2]]
			local length = distance(pedal.heel, pedal.ball)
			local throttleAngle = if case[1] == 0 then pedal.travel else 0
			local brakeAngle = if case[1] == 1 then pedal.travel else 0
			local heel, ball = Legs.rightSole(footwell, case[1], throttleAngle, brakeAngle)
			expect(distance(heel, ball)).toBeNear(length, 1e-9)
			expect(heel.y).toBeNear(pedal.heel.y, 1e-12)
			expect(math.abs(heel.z - pedal.heel.z) > 0.002).toBe(true)
		end
		-- the same hung throttle read as an organ pedal swings its heel round the top hinge
		local organ = withHungThrottle()
		local swung = Legs.rightSole(organ, 0, organ.throttle.travel, 0)
		expect(math.abs(swung.y - organ.throttle.heel.y) > 0.01).toBe(true)
	end)

	it("reaches the hung clutch's full press from the seated hips with the knee bent", function()
		local footwell = hung(withClutch())
		local leg = Legs.left(footwell, LEFT_HIP, 1, footwell.clutch.travel)
		expect(leg.reach).toBeNear(distance(leg.hip, leg.ankle), 1e-9)
		expect(distance(leg.hip, leg.ankle) < (Config.THIGH + Config.SHIN) * 0.985).toBe(true)
	end)
end)
