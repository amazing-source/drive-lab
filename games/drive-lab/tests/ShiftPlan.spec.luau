--!strict
--[[
	The shift plan of an H box (Vehicle/ShiftPlan) on the Boss 302's gates and timing: the order of
	its moments, the lever's path and speed, the clutch, reverse's lockout, and a retarget.
]]
local Boss302 = require("../src/shared/Config/Cars/Boss302/Physics")
local ShiftPlan = require("../src/shared/Vehicle/ShiftPlan")
local T = require("../../../tools/test/T")
local Types = require("../src/shared/Config/Cars/Types")

local describe, it, expect = T.describe, T.it, T.expect

local MANUAL = Boss302.gearbox.manual :: Types.ManualGearboxConfig
local GATES, TIMING = MANUAL.gates, MANUAL.timing

local function ordered(plan: ShiftPlan.Plan): boolean
	local times = {
		0,
		plan.reachEnd,
		plan.pressStart,
		plan.clutchDown,
		plan.leverOut,
		plan.across,
		plan.gateIn,
		plan.clutchUp,
	}
	for index = 2, #times do
		if times[index] < times[index - 1] - 1e-12 then
			return false
		end
	end
	return true
end

describe("Shift plan", function()
	it("orders its moments, and the hand and foot already there skip the reach", function()
		for _, pair in { { 1, 2 }, { 2, 3 }, { 5, 3 }, { 0, -1 }, { -1, 1 }, { 6, 5 } } do
			expect(ordered(ShiftPlan.plan(GATES, TIMING, pair[1], pair[2], 0, 0))).toBe(true)
		end
		local ready = ShiftPlan.plan(GATES, TIMING, 1, 2, 1, 1)
		expect(ready.pressStart).toBe(0)
		local cold = ShiftPlan.plan(GATES, TIMING, 1, 2, 0, 0)
		expect(cold.pressStart).toBeNear(math.max(TIMING.reach, TIMING.footMove), 1e-12)
		local half = ShiftPlan.plan(GATES, TIMING, 1, 2, 0.5, 1)
		expect(half.reachEnd).toBeNear(TIMING.reach / 2, 1e-12)
	end)

	it("takes longer across the rail: 2-3 crosses a column, 3-4 does not, 2-5 crosses two", function()
		local across = ShiftPlan.plan(GATES, TIMING, 2, 3, 1, 1)
		local straight = ShiftPlan.plan(GATES, TIMING, 3, 4, 1, 1)
		expect(across.gateIn - straight.gateIn).toBeNear(TIMING.crossBase + TIMING.crossPerColumn, 1e-9)
		local skip = ShiftPlan.plan(GATES, TIMING, 2, 5, 1, 1)
		expect(skip.gateIn - across.gateIn).toBeNear(TIMING.crossPerColumn, 1e-9)
		expect(ShiftPlan.plan(GATES, TIMING, 1, 2, 1, 1).gateIn).toBeNear(straight.gateIn, 1e-12)
	end)

	it(
		"keeps the lever in its gate until the clutch is down, and puts it in the target gate at gateIn",
		function()
			local plan = ShiftPlan.plan(GATES, TIMING, 2, 3, 0, 0)
			local column, row = ShiftPlan.lever(plan, GATES, plan.clutchDown - 1e-6)
			expect(column).toBe(GATES[2].column)
			expect(row).toBe(GATES[2].row)
			column, row = ShiftPlan.lever(plan, GATES, plan.gateIn)
			expect(column).toBe(GATES[3].column)
			expect(row).toBe(GATES[3].row)
			column, row = ShiftPlan.lever(plan, GATES, plan.leverOut)
			expect(row).toBeNear(0, 1e-6)
			column, row = ShiftPlan.lever(plan, GATES, (plan.leverOut + plan.across) / 2)
			expect(row).toBe(0)
			expect(column > GATES[2].column and column < GATES[3].column).toBe(true)
		end
	)

	it("moves the lever without a jump, starting and stopping at rest, never stopping between", function()
		local step = 1 / 2000
		for _, pair in { { 2, 3 }, { 1, 2 }, { 6, 3 } } do
			local plan = ShiftPlan.plan(GATES, TIMING, pair[1], pair[2], 1, 1)
			local lastColumn, lastRow = ShiftPlan.lever(plan, GATES, plan.clutchDown)
			local speeds = {}
			local t = plan.clutchDown + step
			while t <= plan.gateIn + 1e-9 do
				local column, row = ShiftPlan.lever(plan, GATES, t)
				table.insert(speeds, math.sqrt((column - lastColumn) ^ 2 + (row - lastRow) ^ 2) / step)
				lastColumn, lastRow = column, row
				t += step
			end
			local fastest, slowest = 0, math.huge
			for index = 2, #speeds - 1 do
				fastest = math.max(fastest, speeds[index])
				if index > 40 and index < #speeds - 40 then
					slowest = math.min(slowest, speeds[index])
				end
			end
			-- No sample moves the lever more than a peak-speed step (continuity), it leaves and enters
			-- its gates at under 1 % of that speed, and away from them it never stops.
			expect(fastest < 30).toBe(true)
			expect(speeds[1] < fastest / 100).toBe(true)
			expect(speeds[#speeds] < fastest / 100).toBe(true)
			expect(slowest > fastest / 10).toBe(true)
		end
	end)

	it("presses the clutch before the lever moves and lets it up only after the gear engages", function()
		local plan = ShiftPlan.plan(GATES, TIMING, 1, 2, 0, 0)
		expect(ShiftPlan.clutch(plan, plan.pressStart - 1e-6)).toBe(0)
		expect(ShiftPlan.clutch(plan, plan.clutchDown)).toBe(1)
		expect(ShiftPlan.clutch(plan, plan.gateIn - 1e-6)).toBe(1)
		expect(ShiftPlan.clutch(plan, (plan.gateIn + plan.clutchUp) / 2)).toBeNear(0.5, 1e-9)
		expect(ShiftPlan.clutch(plan, plan.clutchUp)).toBe(0)
		expect(ShiftPlan.phase(plan, plan.gateIn - 1e-6)).toBe("enterGate")
		expect(ShiftPlan.phase(plan, plan.gateIn)).toBe("clutchOut")
		expect(ShiftPlan.phase(plan, plan.clutchUp)).toBe("done")
	end)

	it("pushes the knob down only on a path into reverse, before crossing to it", function()
		local into = ShiftPlan.plan(GATES, TIMING, 0, -1, 1, 1)
		expect(into.knobDown).toBe(true)
		expect(into.pushBudget).toBe(TIMING.push)
		local pushedAt = into.leverOut + (into.across - into.leverOut) * 0.5
		expect(ShiftPlan.knob(into, into.across) > 0.99).toBe(true)
		expect(ShiftPlan.knob(into, into.clutchDown) == 0).toBe(true)
		expect(ShiftPlan.knob(into, into.gateIn)).toBe(0)
		expect(ShiftPlan.knob(into, pushedAt) > 0).toBe(true)
		local crossedPushing, pushes = false, 0
		local t = into.leverOut
		while t < into.across do
			local knob = ShiftPlan.knob(into, t)
			local column = ShiftPlan.lever(into, GATES, t)
			if knob > 0 and knob < 1 then
				pushes += 1
				crossedPushing = crossedPushing or column ~= into.startColumn
			end
			t += 1 / 2000
		end
		expect(pushes > 0).toBe(true)
		expect(crossedPushing).toBe(false)
		local out = ShiftPlan.plan(GATES, TIMING, -1, 1, 1, 1)
		expect(out.knobDown).toBe(false)
		expect(out.pushBudget).toBe(0)
	end)

	it("retargets from where the lever is, with the clutch already down", function()
		local first = ShiftPlan.plan(GATES, TIMING, 2, 3, 1, 1)
		local midway = (first.leverOut + first.across) / 2
		local column, row = ShiftPlan.lever(first, GATES, midway)
		local second = ShiftPlan.plan(GATES, TIMING, 2, 5, 1, 1, column, row, 1)
		expect(second.clutchDown).toBe(0)
		expect(second.leaveBudget).toBe(0)
		local startColumn, startRow = ShiftPlan.lever(second, GATES, 0)
		expect(startColumn).toBe(column)
		expect(startRow).toBe(row)
		local endColumn, endRow = ShiftPlan.lever(second, GATES, second.gateIn)
		expect(endColumn).toBe(GATES[5].column)
		expect(endRow).toBe(GATES[5].row)
	end)
end)
