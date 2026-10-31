--!strict
--[[
	What a manual car's driver publishes for its lever, hand and foot, and the instant its shift
	engages (Rules/ShiftSync), on synthetic readings and on the Boss 302 driven through tools/DriveSim.
]]
local Boss302 = require("../src/shared/Config/Cars/Boss302/Physics")
local DriveSim = require("../tools/DriveSim")
local HBox = require("../src/shared/Vehicle/HBox")
local Interface = require("../src/shared/Vehicle/Interface")
local ShiftPlan = require("../src/shared/Vehicle/ShiftPlan")
local ShiftSync = require("../src/shared/Rules/ShiftSync")
local Types = require("../src/shared/Config/Cars/Types")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local MANUAL = Boss302.gearbox.manual :: Types.ManualGearboxConfig
local GATES = MANUAL.gates

local function telemetry(overrides: { [string]: any }): Interface.Telemetry
	local base: { [string]: any } = {
		gear = 2,
		clutchPedal = 0,
		handAt = 0,
		footAt = 0,
		shiftFrom = 2,
		shiftTo = 2,
		shiftElapsed = 0,
	}
	for key, value in overrides do
		base[key] = value
	end
	return (base :: any) :: Interface.Telemetry
end

describe("ShiftSync", function()
	it("publishes the clutch in effect, the foot and hand shares and the shift running", function()
		local readout = ShiftSync.readout(
			telemetry({
				clutchPedal = 0.8,
				footAt = 1,
				handAt = 0.6,
				shiftFrom = 2,
				shiftTo = 3,
				shiftElapsed = 0.12,
			}),
			HBox.newState(),
			GATES
		)
		expect(readout.ClutchPedal).toBe(0.8)
		expect(readout.ClutchFoot).toBe(1)
		expect(readout.ShiftHand).toBe(0.6)
		expect(readout.ShiftFrom).toBe(2)
		expect(readout.ShiftTo).toBe(3)
		expect(readout.ShiftElapsed).toBe(0.12)
		expect(readout.LeverColumn).toBe(GATES[2].column)
		expect(readout.LeverRow).toBe(GATES[2].row)
		expect(readout.KnobDown).toBe(0)
	end)

	it("rests the lever in its gear's gate with no shift running", function()
		for gear = -1, 6 do
			local column, row, knob = ShiftSync.lever(HBox.newState(), GATES, gear)
			expect(column).toBe(GATES[gear].column)
			expect(row).toBe(GATES[gear].row)
			expect(knob).toBe(0)
		end
	end)

	it(
		"moves the lever along the shift running and pushes the knob down only on the way into reverse",
		function()
			for _, shift in { { 1, 2 }, { 2, 3 }, { 0, -1 }, { 1, -1 }, { -1, 1 } } do
				local hbox = HBox.newState()
				local plan = ShiftPlan.plan(GATES, MANUAL.timing, shift[1], shift[2], 0, 0)
				hbox.plan = plan
				local pushed = 0
				local step = plan.clutchUp / 50
				for index = 0, 50 do
					hbox.time = index * step
					local column, row, knob = ShiftSync.lever(hbox, GATES, shift[1])
					local planColumn, planRow = ShiftPlan.lever(plan, GATES, hbox.time)
					expect(column).toBe(planColumn)
					expect(row).toBe(planRow)
					expect(knob).toBe(ShiftPlan.knob(plan, hbox.time))
					pushed = math.max(pushed, knob)
				end
				expect(pushed).toBe(if shift[2] == -1 then 1 else 0)
				hbox.time = plan.gateIn
				local column, row = ShiftSync.lever(hbox, GATES, shift[1])
				expect(column).toBe(GATES[shift[2]].column)
				expect(row).toBe(GATES[shift[2]].row)
			end
		end
	)

	it("says a shift engaged only on the frame its gear flips onto the shift's target", function()
		expect(ShiftSync.engaged(nil, telemetry({ gear = 3, shiftFrom = 2, shiftTo = 3 }))).toBe(false)
		expect(ShiftSync.engaged(2, telemetry({ gear = 2, shiftFrom = 2, shiftTo = 3 }))).toBe(false)
		expect(ShiftSync.engaged(2, telemetry({ gear = 3, shiftFrom = 2, shiftTo = 3 }))).toBe(true)
		expect(ShiftSync.engaged(3, telemetry({ gear = 3, shiftFrom = 2, shiftTo = 3 }))).toBe(false)
		-- A gear change with no shift running (the selector at a standstill) is not a shift's gate.
		expect(ShiftSync.engaged(0, telemetry({ gear = 1, shiftFrom = 1, shiftTo = 1 }))).toBe(false)
	end)

	it(
		"fires once per shift of the Boss flat out in auto, as its plan reaches the gate (DriveSim)",
		function()
			local sim = DriveSim.new(Boss302)
			local input = DriveSim.input({ throttle = 1, gearboxMode = "auto", drivingMode = "Normal" })
			local previous: number? = nil
			local engagedCount, gearChanges = 0, 0
			while sim.time < 12 do
				local result = DriveSim.frame(sim, input, 1 / 60)
				local reading = result.telemetry
				local hbox = sim.model.gearbox.hbox
				if previous ~= nil and reading.gear ~= previous and reading.gear > 0 and previous > 0 then
					gearChanges += 1
				end
				if ShiftSync.engaged(previous, reading) then
					engagedCount += 1
					local plan = assert(hbox.plan, "a plan runs as its gear engages")
					expect(hbox.time >= plan.gateIn).toBe(true)
					expect(reading.gear).toBe(plan.to)
					local column, row = ShiftSync.lever(hbox, GATES, reading.gear)
					expect(column).toBe(GATES[plan.to].column)
					expect(row).toBe(GATES[plan.to].row)
				end
				previous = reading.gear
			end
			expect(gearChanges >= 3).toBe(true)
			expect(engagedCount).toBe(gearChanges)
		end
	)
end)
