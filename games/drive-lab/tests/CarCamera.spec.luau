--!strict
local CarCamera = require("../src/shared/Config/CarCamera")
local Rules = require("../src/shared/Rules/CarCamera")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

describe("CarCamera", function()
	it("closes the same share of a gap whatever the frame rate", function()
		local coarse = Rules.blend(0.1, 0.25)
		local fine = 0
		for _ = 1, 10 do
			fine += (1 - fine) * Rules.blend(0.01, 0.25)
		end
		expect(fine).toBeNear(coarse, 1e-9)
	end)

	it("widens the view with speed, up to its limit", function()
		expect(Rules.fieldOfView(0)).toBe(CarCamera.BASE_FOV)
		expect(Rules.fieldOfView(CarCamera.FOV_SPEED)).toBe(CarCamera.BASE_FOV + CarCamera.FOV_GAIN)
		expect(Rules.fieldOfView(1000)).toBe(CarCamera.BASE_FOV + CarCamera.FOV_GAIN)
	end)

	it("widens a little more under acceleration only, within its cap", function()
		local kick = CarCamera.FOV_KICK
		expect(Rules.kickTarget(0)).toBe(0)
		expect(Rules.kickTarget(-1.2)).toBe(0)
		expect(Rules.kickTarget(0.5)).toBeNear(kick.perG * 0.5, 1e-12)
		expect(Rules.kickTarget(5)).toBeNear(kick.perG * kick.maxG, 1e-12)
		expect(Rules.kickTarget(0 / 0)).toBe(0)
	end)

	it("eases the kick in quicker than out", function()
		local kick = CarCamera.FOV_KICK
		expect(Rules.easeKick(0, 3, kick.attack)).toBeNear(1.5, 1e-12)
		expect(Rules.easeKick(3, 0, kick.release)).toBeNear(1.5, 1e-12)
		expect(Rules.easeKick(3, 0, kick.attack) > 1.5).toBe(true)
	end)
end)
