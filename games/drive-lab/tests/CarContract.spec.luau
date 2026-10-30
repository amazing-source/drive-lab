--!strict
local Catalog = require("../src/shared/Config/Cars/Catalog")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

-- Stands in for a car model: only its "Car" attribute is read.
local function modelNamed(name: unknown): Instance
	return (
		{
			GetAttribute = function(_, attribute: string): unknown
				return if attribute == "Car" then name else nil
			end,
		} :: any
	) :: Instance
end

describe("Car catalog", function()
	it("finds a car's entry by the model's Car attribute, and nothing for any other value", function()
		expect(Catalog.of(modelNamed("SVJ"))).toBe(Catalog.cars.SVJ)
		expect(Catalog.of(modelNamed("Unknown"))).toBe(nil)
		expect(Catalog.of(modelNamed(nil))).toBe(nil)
		expect(Catalog.of(modelNamed(1))).toBe(nil)
	end)

	it("freezes every entry all the way down", function()
		for _, entry in Catalog.cars do
			expect(function()
				(entry :: any).physics = nil
			end).toThrow()
			expect(function()
				(entry.model.wheels :: any)[1] = "Other"
			end).toThrow()
		end
	end)
end)
