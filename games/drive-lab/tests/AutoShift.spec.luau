--!strict
local DriveSim = require("../tools/DriveSim")
local ClusterRules = require("../src/shared/Rules/Cluster")
local SVJ = require("../src/shared/Config/Cars/SVJ/Physics")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local FACE = require("../src/shared/Config/Cars/SVJ/Cluster")
local DT = 1 / 60

describe("Automatic gearbox", function()
	it("drops through the gears while braking, never past the limiter", function()
		-- The owner braked from 300 km/h to 20 and was still in 7th (2026-10-27).
		local sim = DriveSim.new(SVJ)
		DriveSim.setSpeed(sim, 300 / 3.6, 7)
		local input = DriveSim.input({ brake = 1, drivingMode = "Strada" })
		local gearAt: { [number]: number } = {}
		local maxRpm = 0
		while DriveSim.forwardSpeed(sim) > 20 / 3.6 do
			local result = DriveSim.frame(sim, input, DT)
			maxRpm = math.max(maxRpm, result.telemetry.rpm)
			for _, kmh in { 100, 60 } do
				if gearAt[kmh] == nil and DriveSim.forwardSpeed(sim) < kmh / 3.6 then
					gearAt[kmh] = result.telemetry.gear
				end
			end
		end
		expect(gearAt[100] <= 5).toBe(true)
		expect(gearAt[60] <= 3).toBe(true)
		expect(maxRpm < SVJ.engine.limiterRpm).toBe(true)
	end)

	for _, mode in { "Strada", "Sport", "Corsa" } :: { any } do
		it(`lights the red on every full-throttle upshift in {mode}`, function()
			-- Strada used to upshift at 7000 rpm, so the rev counter never reached its red segments.
			local sim = DriveSim.new(SVJ)
			DriveSim.setSpeed(sim, 50 / 3.6, 2)
			local gear, peak = 2, 0
			local shiftRpms = {}
			for _ = 1, 60 * 10 do
				local telemetry =
					DriveSim.frame(sim, DriveSim.input({ throttle = 1, drivingMode = mode }), DT).telemetry
				-- The kickdown from 2nd at the start is not an upshift; only count 2 -> 3 onwards.
				if telemetry.gear > gear and gear >= 2 then
					table.insert(shiftRpms, peak)
				end
				if telemetry.gear ~= gear then
					gear, peak = telemetry.gear, 0
				end
				peak = math.max(peak, telemetry.rpm)
			end
			expect(#shiftRpms >= 3).toBe(true)
			for _, rpm in shiftRpms do
				expect(rpm > FACE.redlineRpm).toBe(true)
				expect(ClusterRules.isRed(FACE, ClusterRules.litCells(FACE, rpm))).toBe(true)
				expect(rpm < SVJ.engine.limiterRpm).toBe(true)
			end
		end)
	end

	it("keeps its gear off the throttle in Sport and Corsa, not in Strada", function()
		-- Lifting at 210 km/h in Corsa used to shift 4 -> 7 at once, three clunks in 0.15 s.
		local gearAfter: { [string]: number } = {}
		for _, mode in { "Strada", "Sport", "Corsa" } :: { any } do
			local sim = DriveSim.new(SVJ)
			DriveSim.setSpeed(sim, 180 / 3.6, 4)
			for _ = 1, 30 do
				DriveSim.frame(sim, DriveSim.input({ throttle = 1, drivingMode = mode }), DT)
			end
			local gear = 0
			for _ = 1, 60 do
				gear =
					DriveSim.frame(sim, DriveSim.input({ throttle = 0, drivingMode = mode }), DT).telemetry.gear
			end
			gearAfter[mode] = gear
		end
		expect(gearAfter.Corsa).toBe(4)
		expect(gearAfter.Sport).toBe(4)
		expect(gearAfter.Strada > 4).toBe(true)
	end)

	for _, fps in { 30, 60 } do
		it(`shifts 1, 2, 3 at full throttle from a standstill without stepping back, at {fps} FPS`, function()
			-- Sport hunted 1-2-1-2 around 70-77 km/h (#35): the rear slip read through the gearbox
			-- fell after the upshift and took second under the downshift point.
			for _, mode in { "Strada", "Sport", "Corsa" } :: { any } do
				local sim = DriveSim.new(SVJ)
				local input = DriveSim.input({ throttle = 1, drivingMode = mode })
				local targets = { 1 }
				while sim.time < 6 do
					DriveSim.frame(sim, input, 1 / fps)
					local target = sim.model.gearbox.target
					if target ~= targets[#targets] then
						table.insert(targets, target)
					end
				end
				expect(`{mode}: {table.concat(targets, ",")}`).toBe(`{mode}: 1,2,3`)
			end
		end)
	end
end)
