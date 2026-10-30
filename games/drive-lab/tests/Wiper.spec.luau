--!strict
local T = require("../../../tools/test/T")
local Wiper = require("../src/shared/Rules/Wiper")

local describe, it, expect = T.describe, T.it, T.expect

-- Binary fractions, so a wipe ends exactly on a step.
local TUNING: Wiper.Tuning = { wipeSeconds = 1, afterWash = 2 }
local DT = 1 / 8

-- Steps the wiper for `seconds` and returns how many wipes it finished.
local function run(state: Wiper.State, washer: boolean, seconds: number): number
	local wipes, last = 0, state.wipeAt
	for _ = 1, math.round(seconds / DT) do
		Wiper.step(state, TUNING, washer, DT)
		local at = state.wipeAt
		if last ~= nil and (at == nil or at < last) then
			wipes += 1
		end
		last = at
	end
	return wipes
end

describe("Wiper", function()
	it("stays parked until switched on, then sweeps out and back in one wipe", function()
		local state = Wiper.newState()
		run(state, false, 3)
		expect(Wiper.sweep(state, TUNING)).toBe(0)
		Wiper.toggle(state)
		run(state, false, 0.5)
		expect(Wiper.sweep(state, TUNING)).toBeNear(1, 1e-9)
		run(state, false, 0.25)
		expect(Wiper.sweep(state, TUNING)).toBeNear(0.5, 1e-9)
		expect(run(state, false, 4)).toBe(4)
	end)

	it("switched off, finishes the wipe in progress and parks", function()
		local state = Wiper.newState()
		Wiper.toggle(state)
		run(state, false, 0.25)
		Wiper.toggle(state)
		-- Still out on the screen a quarter of a wipe later, at the far end.
		run(state, false, 0.25)
		expect(Wiper.sweep(state, TUNING)).toBeNear(1, 1e-9)
		expect(run(state, false, 3)).toBe(1)
		expect(state.wipeAt).toBe(nil)
		expect(Wiper.sweep(state, TUNING)).toBe(0)
	end)

	it("runs while the washer is held and makes its wipes after, then parks", function()
		local state = Wiper.newState()
		run(state, true, 2)
		expect(state.washing).toBe(true)
		expect(state.wipeAt ~= nil).toBe(true)
		-- The release falls on the start of a wipe: the two owed are two whole wipes.
		expect(run(state, false, 5)).toBe(2)
		expect(state.washing).toBe(false)
		expect(state.wipeAt).toBe(nil)
	end)

	it("keeps wiping after a wash while switched on", function()
		local state = Wiper.newState()
		Wiper.toggle(state)
		run(state, true, 1)
		expect(run(state, false, 6)).toBe(6)
		expect(state.wipeAt ~= nil).toBe(true)
	end)
end)
