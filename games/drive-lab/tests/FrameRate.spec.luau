--!strict
--[[
	The same car must drive the same at any frame rate Roblox may give it. Each measurement is
	taken at 30, 60 and 120 FPS and compared with 240 FPS, the closest to continuous time.
]]
local T = require("../../../tools/test/T")
local DriveSim = require("../tools/DriveSim")
local InputHelp = require("../src/shared/Config/InputHelp")
local SVJ = require("../src/shared/Config/Cars/SVJ")

local describe, it, expect = T.describe, T.it, T.expect

local RATES = { 30, 60, 120 }
local REFERENCE = 240
local TOLERANCE = 0.02

-- Yaw rate 0.5, 1 and 2 s into a keyboard step steer at 80 km/h, input filter on.
local function stepSteer(dt: number): { number }
	local sim = DriveSim.new(SVJ, InputHelp.keyboard)
	DriveSim.setSpeed(sim, 80 / 3.6, 3)
	local samples: { number } = {}
	local marks = { 0.5, 1, 2 }
	local start = sim.time
	while #samples < #marks do
		DriveSim.frame(sim, DriveSim.input({ throttle = 0.3, steer = 0.3, gearboxMode = "manual" }), dt)
		if sim.time - start >= marks[#samples + 1] - 1e-9 then
			table.insert(samples, sim.body.yawRate)
		end
	end
	return samples
end

describe("Frame-rate consistency", function()
	local reference = {
		launch = DriveSim.launch(SVJ, 1 / REFERENCE),
		brake = DriveSim.brake(SVJ, 100 / 3.6, 1 / REFERENCE),
		steer = stepSteer(1 / REFERENCE),
	}

	for _, fps in RATES do
		it(`launches, brakes and turns within 2 % of 240 FPS at {fps} FPS`, function()
			local dt = 1 / fps
			local launch = DriveSim.launch(SVJ, dt)
			expect(launch.time100 / reference.launch.time100).toBeNear(1, TOLERANCE)
			expect(launch.time200 / reference.launch.time200).toBeNear(1, TOLERANCE)
			local brake = DriveSim.brake(SVJ, 100 / 3.6, dt)
			expect(brake.distance / reference.brake.distance).toBeNear(1, TOLERANCE)
			local steer = stepSteer(dt)
			for index, yawRate in steer do
				expect(yawRate / reference.steer[index]).toBeNear(1, TOLERANCE)
			end
		end)
	end

	it("parks at 30 FPS without drift or jitter", function()
		local drift, jitter = DriveSim.rest(SVJ, 30, 1 / 30)
		expect(drift < 0.002 and jitter < 0.001).toBeTruthy()
	end)
end)
