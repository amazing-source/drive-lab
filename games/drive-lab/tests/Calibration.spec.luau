--!strict
--[[
	The SVJ's measured behaviour, driven on tools/DriveSim at 60 FPS. Each target names its
	source in 02_aventador_svj_data.md and its status there; tolerances are set before the run,
	not after. The car is never told the answer: these come out of the data and the physics.
]]
local T = require("../../../tools/test/T")
local DriveSim = require("../tools/DriveSim")
local SVJ = require("../src/shared/Config/Cars/SVJ")

local describe, it, expect = T.describe, T.it, T.expect

local DT = 1 / 60
local KMH = 1 / 3.6

describe("SVJ calibration", function()
	local launch = DriveSim.launch(SVJ, DT)

	it("reaches 100 km/h in 2.8 s ± 0.15 (OEM, 02 P1)", function()
		expect(launch.time100).toBeNear(2.8, 0.15)
	end)

	it("reaches 200 km/h in 8.6 s ± 0.5 (OEM via press, 02 P2)", function()
		expect(launch.time200).toBeNear(8.6, 0.5)
	end)

	it("stops from 100 km/h in 30 m ± 1.5 with ABS (OEM, 02 P7)", function()
		local stop = DriveSim.brake(SVJ, 100 * KMH, DT)
		expect(stop.distance).toBeNear(30, 1.5)
	end)

	it(
		"tops each gear within 1.5 % of the 8,700 rpm speed in 02 §2.5 (the table has no tyre slip)",
		function()
			local limiter = SVJ.engine.limiterRpm * 2 * math.pi / 60
			for gear = 1, 6 do
				local ratio = SVJ.gearbox.ratios[gear] * SVJ.driveline.rearReduction
				local theory = limiter * SVJ.rear.tyre.radius / ratio
				local top = DriveSim.gearTop(SVJ, gear, DT)
				expect(top / theory).toBeNear(1 - 0.0075, 0.0075)
			end
		end
	)

	it("tops out in 7th between 350 and 360 km/h (OEM > 350, 02 P9), drag-limited below the cut", function()
		local speed, rpm, gear = DriveSim.topSpeed(SVJ, 300 * KMH, DT)
		expect(gear).toBe(7)
		expect(speed / KMH).toBeNear(355, 5)
		expect(rpm < SVJ.engine.limiterRpm - SVJ.engine.limiterHysteresis).toBeTruthy()
	end)

	it("holds 1.10 g ± 0.05 on a 40 m skidpad (EST working value, 02 P10)", function()
		expect(DriveSim.skidpad(SVJ, 40, DT)).toBeNear(1.10, 0.05)
	end)

	it("rests on flat ground for 30 s without drifting or jittering", function()
		local drift, jitter = DriveSim.rest(SVJ, 30, DT)
		expect(drift < 0.002).toBeTruthy()
		expect(jitter < 0.001).toBeTruthy()
	end)
end)
