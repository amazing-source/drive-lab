--!strict
local DR458Switches = require("../src/shared/Config/Cars/DR458/Switches")
local T = require("../../../tools/test/T")
local Wiper = require("../src/shared/Rules/Wiper")

local describe, it, expect = T.describe, T.it, T.expect

-- Binary fractions, so a wipe ends exactly on a step: one second at the first speed, half a
-- second at the second.
local TUNING: Wiper.Tuning = { speeds = { 1, 0.5 }, afterWash = 2 }
local DT = 1 / 8

-- Steps the wiper for `seconds` and returns how many wipes it finished.
local function run(state: Wiper.State, washer: boolean, seconds: number, tuning: Wiper.Tuning?): number
	local wipes, last = 0, state.phase
	for _ = 1, math.round(seconds / DT) do
		Wiper.step(state, tuning or TUNING, washer, DT)
		local phase = state.phase
		if last ~= nil and (phase == nil or phase < last) then
			wipes += 1
		end
		last = phase
	end
	return wipes
end

describe("Wiper", function()
	it("steps through its speeds and back to off", function()
		local state = Wiper.newState(TUNING)
		local seen = {}
		for _ = 1, 4 do
			Wiper.cycle(state, TUNING)
			table.insert(seen, state.speed)
		end
		expect(table.concat(seen, ",")).toBe("1,2,0,1")
	end)

	it("stays parked until switched on, then sweeps out and back in one wipe", function()
		local state = Wiper.newState(TUNING)
		run(state, false, 3)
		expect(Wiper.sweep(state)).toBe(0)
		Wiper.cycle(state, TUNING)
		run(state, false, 0.5)
		expect(Wiper.sweep(state)).toBeNear(1, 1e-9)
		run(state, false, 0.25)
		expect(Wiper.sweep(state)).toBeNear(0.5, 1e-9)
		expect(run(state, false, 4)).toBe(4)
	end)

	it("wipes at each speed's own rate", function()
		local state = Wiper.newState(TUNING)
		Wiper.cycle(state, TUNING)
		expect(run(state, false, 4)).toBe(4)
		Wiper.cycle(state, TUNING)
		expect(run(state, false, 4)).toBe(8)
	end)

	it("keeps the blade where it is on the glass when the speed changes", function()
		local state = Wiper.newState(TUNING)
		Wiper.cycle(state, TUNING)
		run(state, false, 0.25)
		local before = Wiper.sweep(state)
		Wiper.cycle(state, TUNING)
		expect(Wiper.sweep(state)).toBe(before)
		-- A quarter of a wipe at the second speed is an eighth of a second.
		run(state, false, 0.125)
		expect(Wiper.sweep(state)).toBeNear(1, 1e-9)
	end)

	it("switched off, finishes the wipe in progress at the speed it had and parks", function()
		local state = Wiper.newState(TUNING)
		Wiper.cycle(state, TUNING)
		Wiper.cycle(state, TUNING)
		run(state, false, 0.125)
		Wiper.cycle(state, TUNING)
		expect(state.speed).toBe(0)
		-- Still at the fast speed: the far end an eighth of a second later.
		run(state, false, 0.125)
		expect(Wiper.sweep(state)).toBeNear(1, 1e-9)
		expect(run(state, false, 3)).toBe(1)
		expect(state.phase).toBe(nil)
		expect(Wiper.sweep(state)).toBe(0)
	end)

	it("runs at its first speed while the washer is held, makes its wipes after, then parks", function()
		local state = Wiper.newState(TUNING)
		expect(run(state, true, 2)).toBe(2)
		expect(state.washing).toBe(true)
		expect(state.phase ~= nil).toBe(true)
		-- The release falls on the start of a wipe: the two owed are two whole wipes.
		expect(run(state, false, 5)).toBe(2)
		expect(state.washing).toBe(false)
		expect(state.phase).toBe(nil)
	end)

	it("washing while on its fastest speed keeps the faster speed", function()
		local state = Wiper.newState(TUNING)
		Wiper.cycle(state, TUNING)
		Wiper.cycle(state, TUNING)
		expect(run(state, true, 2)).toBe(4)
	end)

	it("keeps wiping after a wash while switched on", function()
		local state = Wiper.newState(TUNING)
		Wiper.cycle(state, TUNING)
		run(state, true, 1)
		expect(run(state, false, 6)).toBe(6)
		expect(state.phase ~= nil).toBe(true)
	end)

	it("the DR458's two speeds sit inside FMVSS 104: one at 45 wipes a minute or more, 15 apart", function()
		local tuning = DR458Switches.wiper
		assert(tuning, "the DR458 has a wiper")
		expect(#tuning.speeds).toBe(2)
		local slow, fast = 60 / tuning.speeds[1], 60 / tuning.speeds[2]
		expect(slow >= 20).toBe(true)
		expect(fast >= 45).toBe(true)
		expect(fast - slow >= 15 - 1e-9).toBe(true)
		local state = Wiper.newState(tuning)
		Wiper.cycle(state, tuning)
		local slowWipes = run(state, false, 60, tuning)
		expect(slowWipes >= 44 and slowWipes <= 45).toBe(true)
		Wiper.cycle(state, tuning)
		local fastWipes = run(state, false, 60, tuning)
		expect(fastWipes >= 64 and fastWipes <= 65).toBe(true)
	end)
end)
