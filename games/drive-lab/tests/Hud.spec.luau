--!strict
local Hud = require("../src/shared/Rules/Hud")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

describe("Hud", function()
	it("cycles Full, Minimal, Off", function()
		expect(Hud.nextMode("Full")).toBe("Minimal")
		expect(Hud.nextMode("Minimal")).toBe("Off")
		expect(Hud.nextMode("Off")).toBe("Full")
	end)

	it("lights each rev segment for its own thousand rpm", function()
		expect(Hud.segmentShare(0, 1, 1000)).toBe(0)
		expect(Hud.segmentShare(450, 1, 1000)).toBe(0.45)
		expect(Hud.segmentShare(4500, 4, 1000)).toBe(1)
		expect(Hud.segmentShare(4500, 5, 1000)).toBe(0.5)
		expect(Hud.segmentShare(4500, 6, 1000)).toBe(0)
		expect(Hud.segmentShare(12000, 10, 1000)).toBe(1)
	end)

	it("starts the red zone inside the segment the redline falls in", function()
		expect(Hud.segmentShare(8500, 8, 1000)).toBe(1)
		expect(Hud.segmentShare(8500, 9, 1000)).toBe(0.5)
		expect(Hud.segmentShare(8500, 10, 1000)).toBe(0)
	end)

	it("flashes for the upshift in manual only, at its rate", function()
		expect(Hud.shiftFlash(8600, 8500, true, 0.1, 2.5)).toBe(true)
		expect(Hud.shiftFlash(8600, 8500, true, 0.3, 2.5)).toBe(false)
		expect(Hud.shiftFlash(8600, 8500, false, 0.1, 2.5)).toBe(false)
		expect(Hud.shiftFlash(8000, 8500, true, 0.1, 2.5)).toBe(false)
	end)

	it("shows the launch text in the drive mode's place while launch control is on", function()
		expect(Hud.modeText("Corsa", true, "LAUNCH")).toBe("LAUNCH")
		expect(Hud.modeText("Corsa", false, "LAUNCH")).toBe("CORSA")
		expect(Hud.modeText(nil, false, "LAUNCH")).toBe("")
	end)
end)
