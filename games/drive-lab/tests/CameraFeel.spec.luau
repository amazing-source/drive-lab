--!strict
local CameraFeel = require("../src/shared/Config/CameraFeel")
local Rules = require("../src/shared/Rules/CameraFeel")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

describe("CameraFeel", function()
	it("keeps the base field of view up to walking pace and widens to the sprint's", function()
		expect(Rules.fieldOfView(0, 12.5, 26)).toBe(CameraFeel.BASE_FOV)
		expect(Rules.fieldOfView(12.5, 12.5, 26)).toBe(CameraFeel.BASE_FOV)
		expect(Rules.fieldOfView(26, 12.5, 26)).toBe(CameraFeel.SPRINT_FOV)
		expect(Rules.fieldOfView(40, 12.5, 26)).toBe(CameraFeel.SPRINT_FOV)
		expect(Rules.fieldOfView(19.25, 12.5, 26)).toBeNear(
			(CameraFeel.BASE_FOV + CameraFeel.SPRINT_FOV) / 2,
			1e-9
		)
	end)

	it("closes the same share of a gap whatever the frame rate", function()
		local coarse = Rules.blend(0.1, 0.05)
		local fine = 0
		for _ = 1, 10 do
			fine += (1 - fine) * Rules.blend(0.01, 0.05)
		end
		expect(fine).toBeNear(coarse, 1e-9)
		expect(Rules.blend(0.05, 0.05)).toBeNear(0.5, 1e-9)
	end)
end)
