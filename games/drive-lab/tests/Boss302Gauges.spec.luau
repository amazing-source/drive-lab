--!strict
--[[
	The Boss 302's analog cluster (Config/Cars/Boss302/Gauges) against its model binding and its
	start-up, through the contract's own check: while the car is out of the catalog, the only
	problems are the needles and screens the 3D manifest has not measured yet, each also pending in
	its binding.
]]
local Boss302Gauges = require("../src/shared/Config/Cars/Boss302/Gauges")
local Boss302Binding = require("../tools/Boss302Binding")
local Contract = require("../src/shared/Config/Cars/Contract")
local Model = require("../src/shared/Config/Cars/Boss302/Model")
local ModelPending = require("../src/shared/Config/Cars/Boss302/ModelPending")
local Rules = require("../src/shared/Rules/Gauges")
local Startup = require("../src/shared/Config/Cars/Boss302/Startup")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local function copy<V>(value: V): V
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for key, child in value :: any do
		out[key] = copy(child)
	end
	return out :: any
end

-- The binding as the 3D manifest will make it once every needle's sweep and both windows are
-- measured: each missing needle a half turn about the tachometer's axis, each display a small
-- screen.
local function measured(): any
	local model = copy(Model) :: any
	model.needles = model.needles or {}
	for _, name in Boss302Binding.needles or {} do
		local needle = copy(model.needles.Needle_Tach)
		needle.part = name
		model.needles[name] = model.needles[name] or needle
	end
	model.displays = {}
	for display in Boss302Binding.displays or {} do
		model.displays[display] =
			{ forward = 0.3, right = -0.25, up = 0.33, width = 0.04, height = 0.02, tilt = 0.3 }
	end
	return model
end

local function problemsWith(change: (model: any, gauges: any, startup: any) -> ()): { string }
	local model, gauges, startup = measured(), copy(Boss302Gauges) :: any, copy(Startup) :: any
	change(model, gauges, startup)
	return Contract.gaugeProblems(model, startup, gauges)
end

local function mentions(problems: { string }, words: string): boolean
	return string.find(table.concat(problems, "\n"), words, 1, true) ~= nil
end

describe("Boss 302 gauges", function()
	it(
		"lists only the needles and screens its manifest has not measured, each pending in the binding",
		function()
			local problems = Contract.gaugeProblems(Model, Startup, Boss302Gauges)
			local pending = table.concat(ModelPending, "\n")
			for _, problem in problems do
				local subject = string.match(problem, "the (Needle_%a+) dial")
					or string.match(problem, "on the (%a+) display")
				expect(subject ~= nil and "a pending needle or screen" or problem).toBe(
					"a pending needle or screen"
				)
				local part = if string.sub(subject :: string, 1, 7) == "Needle_"
					then subject
					else (Boss302Binding.displays or {})[subject :: string]
				expect(part and string.find(pending, part, 1, true) ~= nil and "pending" or problem).toBe(
					"pending"
				)
			end
			expect(mentions(problems, "Needle_Speedo") or mentions(problems, "Needle_Tach")).toBe(false)
		end
	)

	it("has no problem once every needle and screen is measured", function()
		expect(table.concat(problemsWith(function() end), "; ")).toBe("")
	end)

	it("turns every needle and draws on every screen its binding settings name", function()
		local dials: { [string]: boolean } = {}
		for _, dial in Boss302Gauges.dials do
			dials[dial.needle] = true
		end
		for _, needle in Boss302Binding.needles or {} do
			expect(dials[needle] and needle).toBe(needle)
		end
		local displays = Boss302Binding.displays or {}
		expect(displays[(Boss302Gauges.readout :: any).display] ~= nil).toBe(true)
		expect(displays[(Boss302Gauges.message :: any).display] ~= nil).toBe(true)
	end)

	it("puts 180 mph and 9,000 rpm at the end of the bound half turn", function()
		local speedo, tach = Boss302Gauges.dials[1], Boss302Gauges.dials[2]
		expect(Rules.share(speedo, 180 * 1.609344)).toBeNear(1, 1e-9)
		expect(Rules.share(tach, 9000)).toBe(1)
		expect(Rules.share(tach, Boss302Gauges.redlineRpm)).toBeNear(7500 / 9000, 1e-9)
		expect((Model.needles :: any).Needle_Tach.travel).toBeNear(math.pi, 1e-4)
	end)

	it("refuses a dial on a needle the binding does not bind", function()
		local problems = problemsWith(function(model)
			model.needles.Needle_Oil = nil
		end)
		expect(mentions(problems, "the Needle_Oil dial turns a needle the binding does not bind")).toBe(true)
	end)

	it("refuses two dials on one needle", function()
		local problems = problemsWith(function(_, gauges)
			gauges.dials[6].needle = "Needle_Oil"
		end)
		expect(mentions(problems, "two dials turn Needle_Oil")).toBe(true)
	end)

	it("refuses a reading printed in a unit it cannot be read in", function()
		local problems = problemsWith(function(_, gauges)
			gauges.dials[1].unit = "psi"
		end)
		expect(mentions(problems, "prints its speed in psi")).toBe(true)
	end)

	it("refuses a scale that does not rise, falls, or leaves the needle's travel", function()
		for _, scale in
			{ { { 0, 0 } }, { { 0, 0 }, { 0, 1 } }, { { 0, 0.6 }, { 10, 0.4 } }, { { 0, 0 }, { 10, 1.2 } } }
		do
			local problems = problemsWith(function(_, gauges)
				gauges.dials[2].scale = scale
			end)
			expect(mentions(problems, "the Needle_Tach dial has")).toBe(true)
		end
	end)

	it("refuses needle timings that are not positive", function()
		for _, field in { "response", "catchUp", "maxRate" } do
			local problems = problemsWith(function(_, gauges)
				gauges.dials[1][field] = 0
			end)
			expect(mentions(problems, "needs a positive response, catch-up and top speed")).toBe(true)
		end
	end)

	it("refuses lighting with a control its start-up never moves", function()
		local problems = problemsWith(function(_, gauges)
			gauges.lightsWith = "MasterSwitch"
		end)
		expect(mentions(problems, '"MasterSwitch", which the start-up never moves')).toBe(true)
	end)

	it("refuses a sweep that takes no time", function()
		local problems = problemsWith(function(_, gauges)
			gauges.sweep = 0
		end)
		expect(mentions(problems, "the gauges' sweep needs a duration")).toBe(true)
		expect(#problemsWith(function(_, gauges)
			gauges.sweep = 1.2
		end)).toBe(0)
	end)

	it("refuses a screen the binding lacks", function()
		local problems = problemsWith(function(model)
			model.displays.PodReadout = nil
		end)
		expect(mentions(problems, "on the PodReadout display, which the binding lacks")).toBe(true)
	end)
end)
