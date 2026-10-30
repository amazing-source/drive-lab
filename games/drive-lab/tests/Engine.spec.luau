--!strict
local T = require("../../../tools/test/T")
local Engine = require("../src/shared/Vehicle/Engine")
local SVJ = require("../src/shared/Config/Cars/SVJ/Physics")

local describe, it, expect = T.describe, T.it, T.expect

local engine = Engine.prepare(SVJ.engine)
local RPM = Engine.RAD_PER_RPM

describe("Engine torque curve", function()
	it("passes through the two OEM anchors (02 E6, E7)", function()
		expect(Engine.fullTorque(engine, 6750 * RPM)).toBeNear(720, 1e-9)
		expect(Engine.fullTorque(engine, 8500 * RPM)).toBeNear(636, 1e-9)
	end)

	it("makes 566 kW (770 CV) at its power peak, at 8,500 rpm", function()
		local best, bestRpm = 0, 0
		for rpm = 1000, 8700, 10 do
			local power = Engine.fullTorque(engine, rpm * RPM) * rpm * RPM
			if power > best then
				best, bestRpm = power, rpm
			end
		end
		expect(best).toBeNear(566e3, 500)
		expect(bestRpm).toBe(8500)
	end)

	it("interpolates between table points and fades to nothing at rest", function()
		expect(Engine.fullTorque(engine, 6250 * RPM)).toBeNear((708 + 717) / 2, 1e-9)
		expect(Engine.fullTorque(engine, 0)).toBe(0)
		expect(Engine.fullTorque(engine, 500 * RPM)).toBeNear(200, 1e-9)
	end)
end)

describe("Engine drag", function()
	it("runs from 2 bar near idle to 4 bar at 8,500 rpm (02 §2.4)", function()
		expect(Engine.dragTorque(engine, 950 * RPM)).toBeNear(103, 1e-9)
		expect(Engine.dragTorque(engine, 8500 * RPM)).toBeNear(207, 1e-9)
		expect(Engine.dragTorque(engine, 0)).toBe(0)
	end)

	it("blends drive and drag by throttle", function()
		local speed = 5000 * RPM
		local drive, drag = Engine.output(engine, speed, 0.25)
		expect(drive).toBeNear(0.25 * Engine.fullTorque(engine, speed), 1e-9)
		expect(drag).toBeNear(0.75 * Engine.dragTorque(engine, speed), 1e-9)
	end)
end)

describe("Engine limiter and idle", function()
	it("cuts at the limit and resumes only after falling by the hysteresis", function()
		local state = Engine.newState(engine)
		state.speed = 8700 * RPM
		expect(Engine.updateLimiter(engine, state, engine.limiterSpeed)).toBe(true)
		state.speed = 8600 * RPM
		expect(Engine.updateLimiter(engine, state, engine.limiterSpeed)).toBe(true)
		state.speed = 8540 * RPM
		expect(Engine.updateLimiter(engine, state, engine.limiterSpeed)).toBe(false)
	end)

	it("opens the throttle only below idle", function()
		expect(Engine.idleThrottle(engine, 1100 * RPM)).toBe(0)
		expect(Engine.idleThrottle(engine, 850 * RPM) > 0).toBeTruthy()
		expect(Engine.idleThrottle(engine, 0)).toBe(1)
	end)
end)
