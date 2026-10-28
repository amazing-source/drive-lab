--!strict
local ArmPieces = require("../src/shared/Rules/ArmPieces")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

describe("Arm pieces: gloves only in one's own cockpit view", function()
	it("hides the sleeves for the local driver in the cockpit view", function()
		expect(ArmPieces.sleevesShown("Cockpit", true, true)).toBe(false)
	end)

	it("keeps the full arms in every other view", function()
		for _, view in { "Chase", "Hood", "OnFoot", "Unknown" } do
			expect(ArmPieces.sleevesShown(view, true, true)).toBe(true)
		end
		expect(ArmPieces.sleevesShown(nil, true, true)).toBe(true)
	end)

	it("keeps the full arms of every other driver, even from the cockpit", function()
		expect(ArmPieces.sleevesShown("Cockpit", false, true)).toBe(true)
	end)

	it("keeps the full arms everywhere when the cockpit gloves-only view is switched off", function()
		expect(ArmPieces.sleevesShown("Cockpit", true, false)).toBe(true)
	end)
end)
