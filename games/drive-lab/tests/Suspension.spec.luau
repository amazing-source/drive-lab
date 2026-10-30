--!strict
local T = require("../../../tools/test/T")
local Geometry = require("../src/shared/Vehicle/Geometry")
local SVJ = require("../src/shared/Config/Cars/SVJ/Physics")
local Suspension = require("../src/shared/Vehicle/Suspension")
local World = require("../src/shared/Config/World")

local describe, it, expect = T.describe, T.it, T.expect

local suspension = Suspension.prepare(SVJ)
local config = SVJ.suspension

describe("Suspension rates", function()
	it("sizes the wheel rate from the ride frequency (02 §2.8: 349 kg at 1.7 Hz is 39.8 kN/m)", function()
		expect(Suspension.wheelRate(349, 1.7)).toBeNear(39.8e3, 100)
		expect(Suspension.wheelRate(471, 1.9)).toBeNear(67.1e3, 100)
	end)

	it("carries each corner's whole weight at the static compression", function()
		for wheel = 1, Geometry.WHEELS do
			local corner = suspension.corners[wheel]
			local weight = Geometry.cornerMass(SVJ, wheel) * World.GRAVITY_MPS2
			expect(Suspension.springForce(corner, config.staticCompression)).toBeNear(weight, 1e-6)
		end
	end)

	it("sizes the anti-roll bars to the configured roll gradient and front share", function()
		local front, rear = suspension.corners[1], suspension.corners[3]
		local function axleStiffness(corner: Suspension.Corner, track: number): number
			return 0.5 * track * track * corner.wheelRate + corner.antiRollRate * track * track
		end
		local stiffnessFront = axleStiffness(front, SVJ.front.track)
		local stiffnessRear = axleStiffness(rear, SVJ.rear.track)
		local total = stiffnessFront + stiffnessRear
		local gradient = SVJ.mass * World.GRAVITY_MPS2 * SVJ.cgHeight / total
		expect(gradient).toBeNear(config.rollGradient, 1e-9)
		expect(stiffnessFront / total).toBeNear(config.frontRollShare, 1e-9)
	end)
end)

describe("Suspension damper", function()
	local corner = suspension.corners[1]

	it("is stiffer in rebound than in bump by the configured ratio", function()
		local bump = Suspension.damperForce(corner, config, 0.5, 0.05)
		local rebound = Suspension.damperForce(corner, config, 0.5, -0.05)
		expect(-rebound / bump).toBeNear(config.damperReboundRatio, 1e-9)
	end)

	it("averages the mode's share of critical damping below the knee", function()
		local bump = Suspension.damperForce(corner, config, 0.5, 0.05)
		local rebound = -Suspension.damperForce(corner, config, 0.5, -0.05)
		expect((bump + rebound) / 2 / 0.05).toBeNear(0.5 * corner.criticalDamping, 1e-6)
	end)

	it("switches to the shallower fast slope past the knee", function()
		local knee = config.damperKneeSpeed
		local atKnee = Suspension.damperForce(corner, config, 0.5, knee)
		local beyond = Suspension.damperForce(corner, config, 0.5, knee + 0.1)
		local slow = atKnee / knee
		expect((beyond - atKnee) / 0.1).toBeNear(slow * config.damperFastRatio, 1e-6)
	end)
end)

describe("Suspension bump stop", function()
	it("does nothing before it is reached", function()
		expect(Suspension.bumpStopForce(config, config.bumpStopStart)).toBe(0)
	end)

	it("stiffens with depth, then holds the capped rate", function()
		local h = 1e-6
		local function rate(depth: number): number
			local compression = config.bumpStopStart + depth
			return (
				Suspension.bumpStopForce(config, compression + h)
				- Suspension.bumpStopForce(config, compression - h)
			) / (2 * h)
		end
		expect(rate(0.001)).toBeNear(config.bumpStopRate + 2 * config.bumpStopProgression * 0.001, 1)
		expect(rate(0.004) > rate(0.001)).toBeTruthy()
		expect(rate(0.019)).toBeNear(config.bumpStopMaxRate, 1)
	end)
end)

describe("Suspension corner forces", function()
	it("pushes the compressed side up and the other side down through the anti-roll bar", function()
		local compressions = { 0.06, 0.04, 0.05, 0.05 }
		local speeds = { 0, 0, 0, 0 }
		local grounded = { true, true, true, true }
		local forces = table.create(4, 0)
		Suspension.forces(suspension, 0.5, compressions, speeds, grounded, forces)
		local corner = suspension.corners[1]
		local bar = corner.antiRollRate * 0.02
		expect(forces[1] - Suspension.springForce(corner, 0.06)).toBeNear(bar, 1e-6)
		expect(forces[2] - Suspension.springForce(corner, 0.04)).toBeNear(-bar, 1e-6)
	end)

	it("carries nothing on an airborne wheel and never pulls a wheel down", function()
		local forces = table.create(4, 0)
		Suspension.forces(
			suspension,
			0.65,
			{ 0.05, 0.0, 0.05, 0.001 },
			{ 0, 0, 0, -3 },
			{ true, false, true, true },
			forces
		)
		expect(forces[2]).toBe(0)
		expect(forces[4]).toBe(0)
		expect(forces[1] > 0).toBeTruthy()
	end)
end)
