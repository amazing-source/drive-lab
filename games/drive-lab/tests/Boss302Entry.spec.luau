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
local Shift = require("../src/shared/Config/Cars/Boss302/Shift")
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

	it("gets the driver in and out through its own clips, from its own mark", function()
		expect(Door.direct).toBe(nil)
		expect(Door.mark.right).toBe(-1)
		expect(Door.mark.forward).toBe(-0.8)
		expect(Door.exitEnd.right < Door.mark.right).toBe(true)
		local DR458Door = require("../src/shared/Config/Cars/DR458/Door")
		for _, name in { "OutsideOpen", "GetIn", "InsideClose", "InsideOpen", "GetOut", "OutsideClose" } do
			local clip = assert(Door.clips[name], name)
			-- The Boss's own upload, not the DR458's stand-in.
			expect(clip.seated ~= DR458Door.clips[name].seated).toBe(true)
			expect(clip.duration > 0).toBe(true)
		end
		expect(Door.seatedPose ~= DR458Door.seatedPose).toBe(true)
		-- Opening from outside ends open, getting in ends shut, the stance is reached inside OutsideClose.
		local function last(curve: { values: { number } }?): number
			local values = assert(curve, "a door curve").values
			return values[#values]
		end
		expect(last(Door.clips.OutsideOpen.door)).toBe(1)
		expect(last(Door.clips.GetIn.door)).toBe(0)
		expect(Door.exitEnd.at <= Door.clips.OutsideClose.duration).toBe(true)
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

	it("puts the Knob hand mesh at the centre the shift animator's poses give", function()
		-- poses.json (v2), the Knob R hand's centre in its wrist frame, studs of the 1.5x world.
		local studs, perMetre = { x = -0.0594, y = -0.1644, z = -0.3289 }, 5.357142857142857
		local mesh = assert(Shift.mesh, "the shift data places the Knob mesh")
		expect(mesh.x).toBeNear(studs.x / perMetre, 1e-6)
		expect(mesh.y).toBeNear(studs.y / perMetre, 1e-6)
		expect(mesh.z).toBeNear(studs.z / perMetre, 1e-6)
	end)
end)
