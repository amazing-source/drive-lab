--!strict
--[[
	A stall's round trip on the driving client (Rules/Stall): reported once while the engine runs,
	the model restarted when the key start has it running again, and the car left to roll.
]]
local Stall = require("../src/shared/Rules/Stall")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

-- Steps the tracker through frames of { stalled, engineOn } and returns the actions in order.
local function run(frames: { { boolean } }): string
	local tracker, seen = Stall.newTracker(), {}
	for _, frame in frames do
		table.insert(seen, Stall.step(tracker, frame[1], frame[2]) or "-")
	end
	return table.concat(seen, " ")
end

describe("Stall round trip", function()
	it("reports a stall while the engine runs once, however long the server takes", function()
		expect(run({ { false, true }, { true, true }, { true, true }, { true, true }, { true, false } })).toBe(
			"- Report - - -"
		)
	end)

	it("restarts the model when the engine runs again, and only then", function()
		expect(run({
			{ false, true },
			{ true, true },
			{ true, false },
			{ true, false },
			{ true, true },
			{ false, true },
		})).toBe("- Report - - Restart -")
	end)

	it("never reports a model that stalled with the engine off, and starts it with the engine", function()
		expect(run({ { false, false }, { true, false }, { true, false }, { true, true }, { false, true } })).toBe(
			"- - - Restart -"
		)
	end)

	it("reports a second stall after the first was restarted", function()
		expect(run({
			{ false, true },
			{ true, true },
			{ true, false },
			{ true, true },
			{ false, true },
			{ true, true },
		})).toBe("- Report - Restart - Report")
	end)

	it("lets the driver's input through once drivable, or while the car rolls stalled", function()
		expect(Stall.drives(true, false)).toBe(true)
		expect(Stall.drives(false, true)).toBe(true)
		expect(Stall.drives(false, false)).toBe(false)
	end)
end)
