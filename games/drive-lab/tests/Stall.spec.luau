--!strict
--[[
	A stall's round trip on the driving client (Rules/Stall): reported while the engine runs, the
	model restarted when the key start has it running again, a report the server never acts on sent
	again then given up, and the car left to roll.
]]
local Stall = require("../src/shared/Rules/Stall")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local TIMING: Stall.Timing = { resendAfter = 0.5, resumeAfter = 1.5 }
local FRAME = 0.125

-- Steps the tracker through frames of { stalled, engineOn }, FRAME apart, and returns the actions in
-- order.
local function run(frames: { { boolean } }): string
	local tracker, seen = Stall.newTracker(), {}
	for index, frame in frames do
		table.insert(seen, Stall.step(tracker, frame[1], frame[2], index * FRAME, TIMING) or "-")
	end
	return table.concat(seen, " ")
end

-- Frames of a stall the server never turns into an engine stop, for `seconds` after the report.
local function ignored(seconds: number): { { boolean } }
	local frames = { { false, true } }
	for _ = 0, math.round(seconds / FRAME) do
		table.insert(frames, { true, true })
	end
	return frames
end

-- The frame index (from the report) of each action in `actions`.
local function at(actions: string): { string }
	local found = {}
	for index, action in string.split(actions, " ") do
		if action ~= "-" then
			table.insert(found, `{action}@{index - 2}`)
		end
	end
	return found
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

	it(
		"sends a report the server ignores once more, then runs the engine again as the server shows it",
		function()
			local seconds = TIMING.resumeAfter + 0.3
			local actions = at(run(ignored(seconds)))
			local resend = math.round(TIMING.resendAfter / FRAME)
			local resume = math.round(TIMING.resumeAfter / FRAME)
			expect(table.concat(actions, " ")).toBe(
				`Report@0 Report@{resend} Restart@{resume} Report@{resume + 1}`
			)
		end
	)

	it("neither sends again nor resumes when the server stops the engine in time", function()
		local frames = { { false, true }, { true, true }, { true, true }, { true, false } }
		for _ = 1, math.round(2 * TIMING.resumeAfter / FRAME) do
			table.insert(frames, { true, false })
		end
		expect(table.concat(at(run(frames)), " ")).toBe("Report@0")
	end)

	it("lets the driver's input through once drivable, or while the car rolls stalled", function()
		expect(Stall.drives(true, false)).toBe(true)
		expect(Stall.drives(false, true)).toBe(true)
		expect(Stall.drives(false, false)).toBe(false)
	end)
end)
