--!strict
local T = require("../../../tools/test/T")
local DriveSim = require("../tools/DriveSim")
local Model = require("../src/shared/Vehicle/Model")
local SVJ = require("../src/shared/Config/Cars/SVJ/Physics")

local describe, it, expect = T.describe, T.it, T.expect

local DT = 1 / 60

local function finite(value: number): boolean
	return value == value and math.abs(value) < math.huge
end

describe("Model step", function()
	it("returns four wheels and the telemetry the glue reads, all finite", function()
		local sim = DriveSim.new(SVJ)
		local result = DriveSim.frame(sim, DriveSim.input({ throttle = 0.5, steer = 0.2 }), DT)
		expect(#result.wheels).toBe(4)
		for _, wheel in result.wheels do
			for _, key in
				{
					"suspensionForce",
					"forwardForce",
					"rightForce",
					"steerAngle",
					"spin",
					"slipRatio",
					"slipAngle",
					"load",
					"combinedSlip",
				}
			do
				expect(finite((wheel :: any)[key])).toBeTruthy()
			end
		end
		for _, key in
			{
				"rpm",
				"gear",
				"speedKmh",
				"throttle",
				"brake",
				"frontTorqueShare",
				"clutch",
				"alaOpen",
				"steer",
				"rearSteerAngle",
			}
		do
			expect(finite((result.telemetry :: any)[key])).toBeTruthy()
		end
		expect(finite(result.aeroDrag) and finite(result.downforceFront) and finite(result.downforceRear)).toBeTruthy()
	end)

	it("idles parked with the clutch open, pushing nothing sideways or along", function()
		local sim = DriveSim.new(SVJ)
		local result
		for _ = 1, 120 do
			result = DriveSim.frame(sim, DriveSim.input({}), DT)
		end
		expect(result.telemetry.rpm).toBeNear(SVJ.engine.idleRpm, 25)
		expect(result.telemetry.clutch).toBe(0)
		for _, wheel in result.wheels do
			expect(math.abs(wheel.forwardForce) < 1e-6 and math.abs(wheel.rightForce) < 1e-6).toBeTruthy()
		end
	end)

	it("revs freely to the limiter in neutral and no further", function()
		local sim = DriveSim.new(SVJ)
		DriveSim.frame(sim, DriveSim.input({ shiftDown = true }), DT)
		local highest = 0
		for _ = 1, 120 do
			local result = DriveSim.frame(sim, DriveSim.input({ throttle = 1 }), DT)
			highest = math.max(highest, result.telemetry.rpm)
		end
		expect(sim.model.gearbox.gear).toBe(0)
		expect(highest).toBeNear(SVJ.engine.limiterRpm, 60)
		expect(DriveSim.forwardSpeed(sim)).toBeNear(0, 1e-9)
	end)

	it("holds the engine at the launch speed on the brake, then pulls away", function()
		local sim = DriveSim.new(SVJ)
		local result
		for _ = 1, 90 do
			result = DriveSim.frame(sim, DriveSim.input({ throttle = 1, brake = 1 }), DT)
		end
		expect(result.telemetry.rpm).toBeNear(SVJ.engine.launchRpm, 100)
		expect(math.abs(DriveSim.forwardSpeed(sim)) < 0.01).toBeTruthy()
		for _ = 1, 30 do
			DriveSim.frame(sim, DriveSim.input({ throttle = 1 }), DT)
		end
		expect(DriveSim.forwardSpeed(sim) > 3).toBeTruthy()
	end)

	it("drives backwards in reverse", function()
		local sim = DriveSim.new(SVJ)
		DriveSim.frame(sim, DriveSim.input({ shiftDown = true }), DT)
		DriveSim.frame(sim, DriveSim.input({}), DT)
		DriveSim.frame(sim, DriveSim.input({ shiftDown = true }), DT)
		for _ = 1, 120 do
			DriveSim.frame(sim, DriveSim.input({ throttle = 0.5 }), DT)
		end
		expect(sim.model.gearbox.gear).toBe(-1)
		expect(DriveSim.forwardSpeed(sim) < -2).toBeTruthy()
	end)

	it("keeps the front's share of drive under the mode's cap (Strada 40 %)", function()
		local sim = DriveSim.new(SVJ)
		local highest = 0
		for _ = 1, 120 do
			local result = DriveSim.frame(sim, DriveSim.input({ throttle = 1, drivingMode = "Strada" }), DT)
			highest = math.max(highest, result.telemetry.frontTorqueShare)
		end
		expect(highest <= SVJ.modes.Strada.frontShareDrive + 0.01).toBeTruthy()
		expect(highest > 0.2).toBeTruthy()
	end)

	it("takes no force through a wheel in the air", function()
		local sim = DriveSim.new(SVJ)
		DriveSim.setSpeed(sim, 20, 2)
		local contacts = sim.contacts
		for wheel, contact in contacts do
			contact.grounded = wheel ~= 2
			contact.compression = if wheel == 2 then 0 else SVJ.suspension.staticCompression
			contact.forwardSpeed = 20
		end
		sim.chassis.forwardSpeed = 20
		local result =
			Model.step(sim.model, DriveSim.input({ throttle = 1, steer = 0.3 }), contacts, sim.chassis, DT)
		local airborne = result.wheels[2]
		expect(airborne.load).toBe(0)
		expect(airborne.suspensionForce).toBe(0)
		expect(airborne.forwardForce == 0 and airborne.rightForce == 0).toBeTruthy()
	end)

	it("brakes harder on dry asphalt than on a wet surface", function()
		local function decelerationOn(grip: number): number
			local sim = DriveSim.new(SVJ)
			sim.grip = grip
			DriveSim.setSpeed(sim, 25, 3)
			for _ = 1, 30 do
				DriveSim.frame(sim, DriveSim.input({ brake = 1 }), DT)
			end
			return 25 - DriveSim.forwardSpeed(sim)
		end
		expect(decelerationOn(0.6) < 0.75 * decelerationOn(1)).toBeTruthy()
	end)

	it("survives a hitch and a zero-length frame without producing NaN", function()
		local sim = DriveSim.new(SVJ)
		DriveSim.setSpeed(sim, 30, 3)
		local hitch = Model.step(sim.model, DriveSim.input({ throttle = 1 }), sim.contacts, sim.chassis, 2)
		local zero = Model.step(sim.model, DriveSim.input({ throttle = 1 }), sim.contacts, sim.chassis, 0)
		expect(finite(hitch.wheels[3].forwardForce) and finite(zero.wheels[3].forwardForce)).toBeTruthy()
	end)
end)
