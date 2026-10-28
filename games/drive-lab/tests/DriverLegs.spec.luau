--!strict
local Config = require("../src/shared/Config/DriverLegs")
local Legs = require("../src/shared/Rules/DriverLegs")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

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
		local heel, ball = Legs.rightSole(0, 0, 0)
		expect(distance(heel, Config.THROTTLE.heel)).toBeNear(0, 1e-9)
		expect(distance(ball, Config.THROTTLE.ball)).toBeNear(0, 1e-9)
		heel, ball = Legs.rightSole(1, 0, 0)
		expect(distance(heel, Config.BRAKE.heel)).toBeNear(0, 1e-9)
		expect(distance(ball, Config.BRAKE.ball)).toBeNear(0, 1e-9)
		local midHeel, midBall = Legs.rightSole(0.5, 0, 0)
		local straight = (Config.THROTTLE.ball.y + Config.BRAKE.ball.y) / 2
		expect(midBall.y > straight + Config.SWITCH_LIFT / 2).toBe(true)
		expect(midHeel.y).toBeNear((Config.THROTTLE.heel.y + Config.BRAKE.heel.y) / 2, 1e-9)
	end)
end)

describe("Driver legs: pedals", function()
	it("pushes each pedal's face toward the nose, about its hinge", function()
		for _, pedal in { Config.THROTTLE, Config.BRAKE } do
			local pressed = Legs.turned(pedal, pedal.ball, pedal.travel)
			expect(pressed.z < pedal.ball.z - 0.02).toBe(true)
			expect(distance(pressed, pedal.hinge)).toBeNear(distance(pedal.ball, pedal.hinge), 1e-9)
		end
	end)

	it("moves only the pedal under the foot, by its readout", function()
		local throttle, brake = Legs.pedalAngles(0, 1, 0)
		expect(throttle).toBeNear(Config.THROTTLE.travel, 1e-9)
		expect(brake).toBe(0)
		throttle, brake = Legs.pedalAngles(1, 1, 0.5)
		expect(throttle).toBe(0)
		expect(brake).toBeNear(Config.BRAKE.travel / 2, 1e-9)
		throttle, brake = Legs.pedalAngles(0, 0, 1)
		expect(throttle).toBe(0)
		expect(brake).toBe(0)
	end)

	it("carries the foot down with the throttle", function()
		local _, rest = Legs.rightSole(0, 0, 0)
		local _, floored = Legs.rightSole(0, Config.THROTTLE.travel, 0)
		expect(floored.z < rest.z).toBe(true)
		expect(floored.y < rest.y).toBe(true)
	end)
end)

describe("Driver legs: the reach from the hip", function()
	it("keeps the thigh and shin lengths and bends each knee up, toward its point", function()
		local cases = {
			{ leg = Legs.right(RIGHT_HIP, 0, 0, 0), toward = Config.KNEE_TOWARD.right },
			{ leg = Legs.right(RIGHT_HIP, 1, 0, Config.BRAKE.travel), toward = Config.KNEE_TOWARD.right },
			{ leg = Legs.right(RIGHT_HIP, 0.5, 0, 0), toward = Config.KNEE_TOWARD.right },
			{ leg = Legs.left(LEFT_HIP), toward = Config.KNEE_TOWARD.left },
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
		local right = Legs.right(RIGHT_HIP, 0, 0, 0)
		local left = Legs.left(LEFT_HIP)
		expect(right.knee.x > left.knee.x + 0.3).toBe(true)
	end)

	it("reaches every foot position from the seated hips with the knee still bent", function()
		local cases = {
			Legs.right(RIGHT_HIP, 0, 0, 0),
			Legs.right(RIGHT_HIP, 0, Config.THROTTLE.travel, 0),
			Legs.right(RIGHT_HIP, 1, 0, Config.BRAKE.travel),
			Legs.right(RIGHT_HIP, 0.5, 0, 0),
			Legs.left(LEFT_HIP),
		}
		for _, leg in cases do
			local asked = distance(leg.hip, leg.ankle)
			expect(leg.reach).toBeNear(asked, 1e-9)
			expect(asked < (Config.THIGH + Config.SHIN) * 0.985).toBe(true)
		end
	end)

	it("stands the shoe on its sole: the ankle above the heel and up out of the instep", function()
		local leg = Legs.right(RIGHT_HIP, 0, 0, 0)
		expect(leg.up.y > 0.3).toBe(true)
		expect(leg.forward.z < 0).toBe(true)
		local heel = Legs.rightSole(0, 0, 0)
		expect(leg.ankle.y > heel.y).toBe(true)
	end)
end)
