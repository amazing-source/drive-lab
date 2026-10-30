--!strict
local T = require("../../../tools/test/T")
local SVJ = require("../src/shared/Config/Cars/SVJ/Physics")
local Types = require("../src/shared/Config/Cars/Types")

local describe, it, expect = T.describe, T.it, T.expect

-- A deep copy of the SVJ with one field changed, for checking that `define` refuses it.
local function withChange(path: { string }, value: unknown): Types.CarConfig
	local function copy(source: any): any
		if type(source) ~= "table" then
			return source
		end
		local out = {}
		for key, child in source do
			out[key] = copy(child)
		end
		return out
	end
	local car = copy(SVJ)
	local node = car
	for index = 1, #path - 1 do
		node = node[path[index]]
	end
	node[path[#path]] = value
	return car
end

describe("Car config", function()
	it("is frozen all the way down", function()
		expect(function()
			(SVJ.front.tyre :: any).peakMuX = 2
		end).toThrow()
		expect(function()
			(SVJ.gearbox.ratios :: any)[1] = 5
		end).toThrow()
	end)

	it("refuses a tyre that never peaks, gears out of order, or a ride height outside the travel", function()
		expect(function()
			Types.define(withChange({ "rear", "tyre", "slidingRatioX" }, 1))
		end).toThrow()
		expect(function()
			Types.define(withChange({ "gearbox", "ratios" }, { 2.4, 3.9 }))
		end).toThrow()
		expect(function()
			Types.define(withChange({ "suspension", "staticCompression" }, 0.1))
		end).toThrow()
	end)

	it("refuses a reverse cut that is empty or wider than reverse's top speed", function()
		expect(function()
			Types.define(withChange({ "gearbox", "reverseCutBand" }, 0))
		end).toThrow()
		expect(function()
			Types.define(withChange({ "gearbox", "reverseCutBand" }, SVJ.gearbox.reverseMaxSpeed))
		end).toThrow()
	end)

	it("accepts an unchanged copy", function()
		expect(Types.define(withChange({ "name" }, "Copy")).name).toBe("Copy")
	end)
end)

describe("SVJ data", function()
	it("gears 7th to the EPA's 36.6 rpm per mph through the 3.52 effective reduction (02 T6)", function()
		local overall = SVJ.gearbox.ratios[7] * SVJ.driveline.rearReduction
		local rpmPerMetrePerSecond = overall / SVJ.rear.tyre.radius * 60 / (2 * math.pi)
		expect(rpmPerMetrePerSecond * 0.44704).toBeNear(36.6, 0.2)
	end)

	it("turns the front and rear wheels at the same road speed when the coupling is locked", function()
		local front = SVJ.driveline.frontReduction / SVJ.front.tyre.radius
		local rear = SVJ.driveline.rearReduction / SVJ.rear.tyre.radius
		expect(front / rear).toBeNear(1, 0.002)
	end)
end)
