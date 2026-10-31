--!strict
--[[
	What a manual car's driver publishes for its lever, hand and foot, and the instant its shift
	engages (Rules/ShiftSync), on synthetic readings and on the Boss 302 driven through tools/DriveSim.
]]
local Boss302 = require("../src/shared/Config/Cars/Boss302/Physics")
local DriveSim = require("../tools/DriveSim")
local Interface = require("../src/shared/Vehicle/Interface")
local ShiftSync = require("../src/shared/Rules/ShiftSync")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

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
		local readout = ShiftSync.readout(telemetry({
			clutchPedal = 0.8,
			footAt = 1,
			handAt = 0.6,
			shiftFrom = 2,
			shiftTo = 3,
			shiftElapsed = 0.12,
		}))
		expect(readout.ClutchPedal).toBe(0.8)
		expect(readout.ClutchFoot).toBe(1)
		expect(readout.ShiftHand).toBe(0.6)
		expect(readout.ShiftFrom).toBe(2)
		expect(readout.ShiftTo).toBe(3)
		expect(readout.ShiftElapsed).toBe(0.12)
	end)

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
				end
				previous = reading.gear
			end
			expect(gearChanges >= 3).toBe(true)
			expect(engagedCount).toBe(gearChanges)
		end
	)
end)
