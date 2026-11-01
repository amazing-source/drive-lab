--!strict
--[[
	The offline track's own scenarios, so a calibration spec measures what its name says.
]]
local DR458 = require("../src/shared/Config/Cars/DR458/Physics")
local DriveSim = require("../tools/DriveSim")
local SVJ = require("../src/shared/Config/Cars/SVJ/Physics")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local KMH = 1 / 3.6

describe("DriveSim", function()
	it("presses the brake at the speed asked for, after its settling coast in gear (#128)", function()
		for _, car in { SVJ, DR458 } do
			for _, fps in { 30, 60, 120 } do
				local stop = DriveSim.brake(car, 100 * KMH, 1 / fps)
				expect(stop.pedalSpeed / KMH).toBeNear(100, 0.05)
			end
		end
	end)
end)
