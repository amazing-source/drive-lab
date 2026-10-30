--!strict
local DriveModes = require("../src/shared/Rules/DriveModes")
local SVJ = require("../src/shared/Config/Cars/SVJ/Physics")
local T = require("../../../tools/test/T")
local Types = require("../src/shared/Config/Cars/Types")

local describe, it, expect = T.describe, T.it, T.expect

local MANETTINO = { "OFF", "1", "2" }

describe("Drive modes", function()
	it("reads the mode the model names when it is one of the car's", function()
		expect(DriveModes.current(MANETTINO, "1")).toBe("1")
		expect(DriveModes.current(SVJ.modeOrder, "Corsa")).toBe("Corsa")
	end)

	it("reads the car's first mode for another car's mode, no mode or a value that is no name", function()
		expect(DriveModes.current(MANETTINO, "Corsa")).toBe("OFF")
		expect(DriveModes.current(MANETTINO, nil)).toBe("OFF")
		expect(DriveModes.current(MANETTINO, 1)).toBe("OFF")
		expect(DriveModes.current(SVJ.modeOrder, "OFF")).toBe("Strada")
	end)

	it("steps through the car's modes in order, from the last back to the first", function()
		expect(DriveModes.after(MANETTINO, "OFF")).toBe("1")
		expect(DriveModes.after(MANETTINO, "1")).toBe("2")
		expect(DriveModes.after(MANETTINO, "2")).toBe("OFF")
		expect(DriveModes.after(SVJ.modeOrder, "Strada")).toBe("Sport")
		expect(DriveModes.after(SVJ.modeOrder, "Corsa")).toBe("Strada")
	end)

	it("steps a mode the car does not have to the car's first", function()
		expect(DriveModes.after(MANETTINO, "Sport")).toBe("OFF")
	end)

	it("steps a car with one mode to that mode", function()
		expect(DriveModes.after({ "Race" }, "Race")).toBe("Race")
	end)
end)

-- An unfrozen copy of the SVJ's physics with one change made by `change`, for `define` to judge.
local function svjWith(change: (any) -> ()): Types.CarConfig
	local function copy(value: any): any
		if type(value) ~= "table" then
			return value
		end
		local out = {}
		for key, child in value do
			out[key] = copy(child)
		end
		return out
	end
	local car = copy(SVJ)
	change(car)
	return car
end

describe("A car's drive modes", function()
	it("accepts the SVJ's", function()
		expect(Types.define(svjWith(function() end)).modeOrder[1]).toBe("Strada")
	end)

	it("accepts modes with other names, as a manettino's", function()
		local car = Types.define(svjWith(function(car)
			car.modes = { OFF = car.modes.Sport, ["1"] = car.modes.Strada, ["2"] = car.modes.Corsa }
			car.modeOrder = { "OFF", "1", "2" }
			car.launch.mode = "2"
		end))
		expect(car.modes[car.modeOrder[3]].tcSlipRatio).toBe(SVJ.modes.Corsa.tcSlipRatio)
	end)

	it("refuses a car without a mode, or an order naming a mode the car does not have", function()
		expect(function()
			Types.define(svjWith(function(car)
				car.modeOrder = {}
			end))
		end).toThrow()
		expect(function()
			Types.define(svjWith(function(car)
				car.modeOrder = { "Strada", "Sport", "Corsa", "Pista" }
			end))
		end).toThrow()
	end)

	it("refuses an order that names a mode twice or leaves one out", function()
		expect(function()
			Types.define(svjWith(function(car)
				car.modeOrder = { "Strada", "Sport", "Sport", "Corsa" }
			end))
		end).toThrow()
		expect(function()
			Types.define(svjWith(function(car)
				car.modeOrder = { "Strada", "Corsa" }
			end))
		end).toThrow()
	end)

	it("refuses launch control in a mode the car does not have", function()
		expect(function()
			Types.define(svjWith(function(car)
				car.launch.mode = "Pista"
			end))
		end).toThrow()
	end)
end)
