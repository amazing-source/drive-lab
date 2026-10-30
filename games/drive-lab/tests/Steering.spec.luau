--!strict
local T = require("../../../tools/test/T")
local Geometry = require("../src/shared/Vehicle/Geometry")
local SVJ = require("../src/shared/Config/Cars/SVJ/Physics")
local Steering = require("../src/shared/Vehicle/Steering")

local describe, it, expect = T.describe, T.it, T.expect

local config = SVJ.steering

describe("Steering ratio and lock", function()
	it("is quickest at low speed and slowest at speed (02 S6: 10:1 to 18:1)", function()
		expect(Steering.ratio(config, 0)).toBe(10)
		expect(Steering.ratio(config, 300 / 3.6)).toBe(18)
		local middle = Steering.ratio(config, (config.lowRatioSpeed + config.highRatioSpeed) / 2)
		expect(middle).toBeNear(14, 1e-9)
	end)

	it("maps a full input to 2.3 turns of steering wheel over the ratio, up to the rack lock", function()
		local small = Steering.frontAngle(config, 0.1, 0)
		expect(small).toBeNear(0.1 * 2.3 * math.pi / 10, 1e-12)
		expect(Steering.frontAngle(config, 1, 0)).toBe(config.maxRoadWheelAngle)
		expect(Steering.frontAngle(config, -1, 0)).toBe(-config.maxRoadWheelAngle)
	end)
end)

describe("Steering Ackermann", function()
	it("turns the inner wheel more than the outer, either way", function()
		local left, right = Steering.ackermann(SVJ, 0.3)
		expect(right > 0.3 and left < 0.3).toBeTruthy()
		local leftTurn, rightTurn = Steering.ackermann(SVJ, -0.3)
		expect(leftTurn).toBeNear(-right, 1e-12)
		expect(rightTurn).toBeNear(-left, 1e-12)
	end)

	it("puts both wheels' axes through one point at full Ackermann", function()
		local car = table.clone(SVJ) :: any
		car.steering = table.clone(SVJ.steering)
		car.steering.ackermann = 1
		local left, right = Steering.ackermann(car, 0.3)
		local halfTrack = SVJ.front.track / 2
		local fromLeft = SVJ.wheelbase / math.tan(left) - halfTrack
		local fromRight = SVJ.wheelbase / math.tan(right) + halfTrack
		expect(fromLeft).toBeNear(fromRight, 1e-9)
	end)
end)

describe("Rear-wheel steering", function()
	local function settled(steer: number, speed: number): number
		local state = Steering.newState()
		Steering.update(SVJ, state, steer, speed, 1)
		return state.angles[Geometry.REAR_LEFT]
	end

	it("steers against the fronts at low speed, up to 3° (02 S11)", function()
		local rear = settled(1, 5)
		expect(rear).toBeNear(-config.rearMaxOpposite, 1e-9)
		expect(settled(-1, 5)).toBeNear(config.rearMaxOpposite, 1e-9)
	end)

	it("steers with the fronts at speed, up to 1.5° (02 S11)", function()
		expect(settled(0.05, 200 / 3.6) > 0).toBeTruthy()
		expect(settled(1, 250 / 3.6)).toBeNear(config.rearMaxSame, 1e-9)
	end)

	it("crosses over near 130 km/h (02 S12)", function()
		expect(math.abs(settled(0.1, 130 / 3.6))).toBeNear(0, 1e-9)
	end)

	it("follows its target through the actuator lag, exactly at any frame rate", function()
		local coarse, fine = Steering.newState(), Steering.newState()
		Steering.update(SVJ, coarse, 0.5, 5, config.rearActuatorTime)
		for _ = 1, 8 do
			Steering.update(SVJ, fine, 0.5, 5, config.rearActuatorTime / 8)
		end
		local target = -0.10 * Steering.frontAngle(config, 0.5, 5)
		expect(coarse.rearAngle / target).toBeNear(1 - math.exp(-1), 1e-9)
		expect(coarse.rearAngle).toBeNear(fine.rearAngle, 1e-12)
	end)
end)
