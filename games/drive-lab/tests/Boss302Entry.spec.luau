--!strict
--[[
	The Boss 302's car entry, piece by piece (its init.luau defines it once the binding has the
	gauges' needles and screens, so this spec does not require it): the driver against the model
	binding and the contract's rules, and the door's direct seating.
]]
local Contract = require("../src/shared/Config/Cars/Contract")
local Door = require("../src/shared/Config/Cars/Boss302/Door")
local Driver = require("../src/shared/Config/Cars/Boss302/Driver")
local EntryPending = require("../src/shared/Config/Cars/Boss302/EntryPending")
local Gauges = require("../src/shared/Config/Cars/Boss302/Gauges")
local Model = require("../src/shared/Config/Cars/Boss302/Model")
local Physics = require("../src/shared/Config/Cars/Boss302/Physics")
local Startup = require("../src/shared/Config/Cars/Boss302/Startup")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

describe("Boss 302 entry", function()
	it(
		"puts the driver's feet on the pedals the binding hinges and its right hand on the bound lever",
		function()
			expect(table.concat(Contract.footwellMismatches(Model, Driver.footwell), "; ")).toBe("")
			Contract.checkShift(
				({ driver = Driver, model = Model, physics = Physics } :: any) :: Contract.Entry
			)
			expect(Driver.shift ~= nil).toBe(true)
		end
	)

	it("gives the hand-over in metres in the seat frame, as the drawn hands read it", function()
		local handOver = assert(Driver.handOver, "a hand-over")
		for _, pose in { handOver.right, handOver.left } do
			local p = pose.position
			-- A wrist on the driver's lap is well inside half a metre of the hip point; the same pose
			-- in studs would be over five times further out.
			expect(math.sqrt(p.x ^ 2 + p.y ^ 2 + p.z ^ 2) < 0.6).toBe(true)
			local q = pose.rotation
			expect(math.sqrt(q.w ^ 2 + q.x ^ 2 + q.y ^ 2 + q.z ^ 2)).toBeNear(1, 1e-3)
		end
	end)

	it("seats the driver directly from its own mark until its clips exist", function()
		expect(Door.direct).toBe(true)
		expect(Door.mark.right).toBe(-1)
		expect(Door.mark.forward).toBe(-0.8)
		-- Getting out stands the driver clear outboard of the mark.
		expect(Door.exitEnd.right < Door.mark.right).toBe(true)
		for _, name in { "OutsideOpen", "GetIn", "InsideClose", "InsideOpen", "GetOut", "OutsideClose" } do
			expect(Door.clips[name] ~= nil).toBe(true)
		end
	end)

	it("waits only on the gauges' parts the binding lacks, and lists them", function()
		local problems = Contract.gaugeProblems(Model, Startup, Gauges)
		expect(#problems > 0).toBe(#EntryPending > 0)
		for _, item in EntryPending do
			expect(string.find(item, "gauges", 1, true) ~= nil).toBe(true)
		end
	end)

	it("defines the whole entry: every rule of the car contract holds", function()
		local entry = require("../src/shared/Config/Cars/Boss302") :: any
		expect(entry.gauges ~= nil and entry.cluster == nil and entry.binnacle == nil).toBe(true)
		expect(entry.driver.shift ~= nil).toBe(true)
		expect(#EntryPending).toBe(0)
	end)
end)
