--!strict
--[[
	The gearbox modes T steps through and the grinds the audio counts (Rules/GearboxModes).
]]
local Boss302 = require("../src/shared/Config/Cars/Boss302/Physics")
local CarSwitches = require("../src/shared/Config/CarSwitches")
local Catalog = require("../src/shared/Config/Cars/Catalog")
local Contract = require("../src/shared/Config/Cars/Contract")
local DR458 = require("../src/shared/Config/Cars/DR458/Physics")
local GearboxModes = require("../src/shared/Rules/GearboxModes")
local SVJ = require("../src/shared/Config/Cars/SVJ/Physics")
local T = require("../../../tools/test/T")
local Types = require("../src/shared/Config/Cars/Types")

local describe, it, expect = T.describe, T.it, T.expect

local function cycle(gearbox: Types.GearboxConfig, keyboard: boolean): string
	local seen, mode = {}, "auto" :: any
	for _ = 1, 4 do
		mode = GearboxModes.after(gearbox, mode, keyboard)
		table.insert(seen, mode)
	end
	return table.concat(seen, " ")
end

-- The Boss's gearbox with the player's clutch taken away.
local function withoutClutch(): Types.GearboxConfig
	local manual = table.clone(Boss302.gearbox.manual :: Types.ManualGearboxConfig)
	manual.playerClutch = false
	local gearbox = table.clone(Boss302.gearbox)
	gearbox.manual = manual
	return gearbox
end

describe("Gearbox modes", function()
	it("steps auto and manual on the ISR cars, on any device", function()
		for _, car in { SVJ, DR458 } do
			expect(cycle(car.gearbox, true)).toBe("manual auto manual auto")
			expect(cycle(car.gearbox, false)).toBe("manual auto manual auto")
		end
	end)

	it("adds the clutch mode on the Boss's H box, on the keyboard only", function()
		expect(cycle(Boss302.gearbox, true)).toBe("manual manualClutch auto manual")
		expect(cycle(Boss302.gearbox, false)).toBe("manual auto manual auto")
	end)

	it("leaves the clutch mode out on an H box that does not offer the player's clutch", function()
		expect(cycle(withoutClutch(), true)).toBe("manual auto manual auto")
	end)

	it("turns a clutch mode carried onto a car or device without it into manual", function()
		expect(GearboxModes.valid(SVJ.gearbox, "manualClutch", true)).toBe("manual")
		expect(GearboxModes.valid(Boss302.gearbox, "manualClutch", false)).toBe("manual")
		expect(GearboxModes.valid(Boss302.gearbox, "manualClutch", true)).toBe("manualClutch")
		expect(GearboxModes.valid(SVJ.gearbox, "auto", true)).toBe("auto")
	end)

	it("gives the clutch key a control only on a car that offers the player's clutch", function()
		expect(CarSwitches.NEEDS.CLUTCH).toBe("playerClutch")
		for _, entry in Catalog.cars do
			expect(Contract.features(entry).playerClutch).toBe(
				GearboxModes.offersClutch(entry.physics.gearbox, true)
			)
		end
		expect(Contract.features(Catalog.cars.SVJ).playerClutch).toBe(false)
		expect(GearboxModes.offersClutch(Boss302.gearbox, true)).toBe(true)
	end)

	it("counts a grind only for a shift refused with the clutch up", function()
		expect(GearboxModes.grinds(3, "clutchUp")).toBe(4)
		expect(GearboxModes.grinds(3, "overRev")).toBe(3)
		expect(GearboxModes.grinds(3, nil)).toBe(3)
	end)
end)
