--!strict
--[[
	The DR458's sourced values, pinned to docs/research/12_dr458_challenge_evo.md or to the value
	derived from it exactly, so a change to one shows up here. EST values stay free.
]]
local DR458 = require("../src/shared/Config/Cars/DR458/Physics")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

-- 1 CV (metric horsepower) in watts.
local CV = 735.49875

local function torqueAt(rpm: number): number
	for _, point in DR458.engine.torqueCurve do
		if point.rpm == rpm then
			return point.torque
		end
	end
	error(`the torque curve has no point at {rpm} rpm`)
end

local function watts(rpm: number, torque: number): number
	return torque * rpm * 2 * math.pi / 60
end

describe("DR458 data", function()
	it("weighs 1,383 kg with the driver, without fuel (documented, 12 §1.3)", function()
		expect(DR458.mass).toBe(1383)
	end)

	it("carries 42 % of it on the front axle (likely, 12 §1.3)", function()
		expect(DR458.frontWeightShare).toBe(0.42)
	end)

	it("makes 570 CV at 9,000 rpm, its peak (documented, 12 §1.1)", function()
		expect(watts(9000, torqueAt(9000)) / CV).toBeNear(570, 0.5)
		for _, point in DR458.engine.torqueCurve do
			expect(watts(point.rpm, point.torque) / CV <= 570.5).toBe(true)
		end
	end)

	it("makes 540 Nm at 6,000 rpm, its peak (documented, 12 §1.1)", function()
		expect(torqueAt(6000)).toBe(540)
		for _, point in DR458.engine.torqueCurve do
			expect(point.torque <= 540).toBe(true)
		end
	end)

	it("has at least 432 Nm from 3,250 rpm to 9,000 (likely, 12 §1.1: over 80 % of 540)", function()
		expect(torqueAt(3250) >= 432).toBe(true)
		for _, point in DR458.engine.torqueCurve do
			if point.rpm >= 3250 and point.rpm <= 9000 then
				expect(point.torque >= 432).toBe(true)
			end
		end
	end)

	it(
		"rolls on 255/650 R19 and 305/690 R19 tyres: half their overall diameters (likely, 12 §1.5)",
		function()
			expect(DR458.front.tyre.radius).toBe(0.650 / 2)
			expect(DR458.rear.tyre.radius).toBe(0.690 / 2)
		end
	)

	it("has the road 458's ratios and 5.14 final drive (likely for the road car, 12 §1.2)", function()
		local ratios = { 3.08, 2.18, 1.63, 1.29, 1.03, 0.84, 0.69 }
		expect(#DR458.gearbox.ratios).toBe(#ratios)
		for gear, ratio in ratios do
			expect(DR458.gearbox.ratios[gear]).toBe(ratio)
		end
		expect(DR458.driveline.rearReduction).toBe(5.14)
	end)

	it("steers at 11.5:1 over 2 turns, so a full turn either way gives 31.3° (likely, 12 §1.7)", function()
		local steering = DR458.steering
		expect(steering.lowSpeedRatio).toBe(11.5)
		expect(steering.highSpeedRatio).toBe(11.5)
		expect(steering.lockToLockTurns).toBe(2)
		expect(math.deg(steering.maxRoadWheelAngle)).toBeNear(360 / 11.5, 1e-9)
	end)

	it("matches the 3D model's wheel centres (3D lead, 2026-10-30)", function()
		expect(DR458.wheelbase).toBe(2.650)
		expect(DR458.front.track).toBe(2 * 0.8325)
		expect(DR458.rear.track).toBe(2 * 0.7984)
	end)
end)
