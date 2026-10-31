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

	it("gives a frame the height that makes it its width share of a reference frame's width", function()
		local reference = 2078 / 477
		expect(Hud.frameHeight(0.17, 1, reference, reference)).toBe(0.17)
		-- A frame of the reference's own shape keeps its height exactly, whatever the shape: (0.1 * 3) / 3
		-- is not 0.1 in floating point.
		expect(Hud.frameHeight(0.1, 1, 3, 3)).toBe(0.1)
		expect(Hud.frameHeight(0.2, 1, 3, 3)).toBe(0.2)
		expect(Hud.frameHeight(0.17, 1, 3, reference)).toBeNear(0.17 * reference / 3, 1e-12)
		expect(Hud.frameHeight(0.17, 1, 3, reference) * 3).toBeNear(0.17 * reference, 1e-12)
		expect(Hud.frameHeight(0.13, 0.5, reference, reference)).toBe(0.065)
	end)

	it("insets a frame its margin from the edge it is anchored to, and none at the centre", function()
		expect(Hud.inset(1, 14)).toBe(-14)
		expect(Hud.inset(0, 14)).toBe(14)
		expect(Hud.inset(0.5, 14)).toBe(0)
	end)

	it("shows the launch text in the drive mode's place while launch control is on", function()
		expect(Hud.modeText("Corsa", true, "LAUNCH")).toBe("LAUNCH")
		expect(Hud.modeText("Corsa", false, "LAUNCH")).toBe("CORSA")
		expect(Hud.modeText(nil, false, "LAUNCH")).toBe("")
	end)

	-- Sprites 20 px wide and 14 tall: capitals of 10 with 2 px of padding, digits 12 apart.
	local glyphs: Hud.Glyphs = {
		rects = { ["1"] = { 0, 0, 20, 14 }, ["2"] = { 24, 0, 20, 14 }, N = { 48, 0, 16, 14 } },
		height = 10,
		pad = 2,
		advance = 12,
	}

	it("lays a right-aligned run of glyphs out from the box's right edge, a digit's advance apart", function()
		-- Capitals 20 high: every sprite drawn twice its size.
		local boxes = Hud.glyphBoxes("12", glyphs, { 0, 100, 200, 120 }, "Right")
		expect(#boxes).toBe(2)
		expect(boxes[2][3]).toBe(204)
		expect(boxes[2][1]).toBe(164)
		expect(boxes[1][1]).toBe(140)
		expect(boxes[1][2]).toBe(96)
		expect(boxes[1][4]).toBe(124)
		expect(Hud.glyphRunLeft("12", glyphs, { 0, 100, 200, 120 }, "Right")).toBe(144)
	end)

	it("centres a glyph in its box, and skips a character with no glyph", function()
		local boxes = Hud.glyphBoxes("N", glyphs, { 100, 0, 140, 10 }, "Center")
		expect(boxes[1][1]).toBe(112)
		expect(boxes[1][3]).toBe(128)
		local skipped = Hud.glyphBoxes("1?", glyphs, { 0, 0, 100, 10 }, "Right")
		expect(#skipped).toBe(1)
	end)
end)
