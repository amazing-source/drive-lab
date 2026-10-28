--!strict
local ArmIK = require("../src/shared/Rules/ArmIK")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

-- The elbow and wrist in the plane of the arm: shoulder at the origin, wrist along +x.
local function joints(upper: number, lower: number, distance: number): (number, number, number)
	local solved = ArmIK.solve(upper, lower, distance)
	return upper * math.cos(solved.bend), upper * math.sin(solved.bend), solved.reach
end

describe("ArmIK", function()
	it("puts the elbow where both bones meet, for any wrist within reach", function()
		for _, distance in { 0.3, 0.9, 1.5, 1.9, 2.1 } do
			local elbowX, elbowY, reach = joints(1.17, 1.05, distance)
			expect(reach).toBeNear(distance, 1e-9)
			expect(math.sqrt(elbowX ^ 2 + elbowY ^ 2)).toBeNear(1.17, 1e-9)
			expect(math.sqrt((reach - elbowX) ^ 2 + elbowY ^ 2)).toBeNear(1.05, 1e-6)
		end
	end)

	it("bends the elbow more as the wrist comes closer", function()
		local _, far = joints(1.17, 1.05, 2.0)
		local _, near = joints(1.17, 1.05, 1.2)
		expect(near > far).toBe(true)
	end)

	it("straightens the arm toward a wrist out of reach instead of breaking", function()
		local elbowX, elbowY, reach = joints(1.17, 1.05, 5)
		expect(reach).toBeNear(2.22, 1e-5)
		expect(elbowY).toBeNear(0, 1e-2)
		expect(elbowX).toBeNear(1.17, 1e-3)
	end)

	it("folds no closer than the bones allow", function()
		local _, _, reach = joints(1.17, 1.05, 0)
		expect(reach).toBeNear(0.12, 1e-5)
	end)
end)
