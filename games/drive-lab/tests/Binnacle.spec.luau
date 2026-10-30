--!strict
local Binnacle = require("../src/shared/Config/Binnacle")
local DR458Screen = require("../src/shared/Config/Cars/DR458/Binnacle")
local DR458Switches = require("../src/shared/Config/Cars/DR458/Switches")
local Rules = require("../src/shared/Rules/Binnacle")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local GREEN = { r = 0, g = 255, b = 0 }
local RED = { r = 255, g = 0, b = 0 }
local LIGHTS: Binnacle.RevLights = {
	fromRpm = 6000,
	toRpm = 8000,
	colours = { GREEN, GREEN, RED },
	flashRpm = 9000,
	flashHz = 2,
}

local READOUT: Rules.Readout = { rpm = 6789.4, gear = -1, speedKmh = 59.6, tcOn = false, mode = "OFF" }

local function lit(shown: { any }, count: number): string
	local marks = table.create(count)
	for index = 1, count do
		marks[index] = if shown[index] then "x" else "."
	end
	return table.concat(marks)
end

describe("Binnacle shift lights", function()
	it("spreads the rev lights evenly from the first threshold to the last", function()
		expect(Rules.lightRpm(LIGHTS, 1)).toBe(6000)
		expect(Rules.lightRpm(LIGHTS, 2)).toBe(7000)
		expect(Rules.lightRpm(LIGHTS, 3)).toBe(8000)
	end)

	it("lights each rev light from its threshold, in its own colour", function()
		expect(lit(Rules.revLights(LIGHTS, 5999, 0), 3)).toBe("...")
		expect(lit(Rules.revLights(LIGHTS, 7000, 0), 3)).toBe("xx.")
		local all = Rules.revLights(LIGHTS, 8500, 0)
		expect(lit(all, 3)).toBe("xxx")
		expect(all[1]).toBe(GREEN)
		expect(all[3]).toBe(RED)
	end)

	it("flashes every rev light from the flash rpm, lit the first half of each period", function()
		expect(lit(Rules.revLights(LIGHTS, 9100, 0.1), 3)).toBe("xxx")
		expect(lit(Rules.revLights(LIGHTS, 9100, 0.3), 3)).toBe("...")
		expect(lit(Rules.revLights(LIGHTS, 8999, 0.3), 3)).toBe("xxx")
	end)

	it("puts a lamp at each end of the strip, lit while its state holds", function()
		local screen = DR458Screen
		local count = #screen.revLights.colours + 2
		local idle = Rules.strip(screen, 1000, 0, { pitLimiter = false, fault = false })
		expect(lit(idle, count)).toBe("........")
		local pit = Rules.strip(screen, 1000, 0, { pitLimiter = true, fault = false })
		expect(lit(pit, count)).toBe(".......x")
		expect(pit[count]).toBe(screen.rightLamp.rgb)
		local fault = Rules.strip(screen, 1000, 0, { pitLimiter = false, fault = true })
		expect(lit(fault, count)).toBe("x.......")
	end)
end)

describe("Binnacle pages", function()
	it("fills the rpm bar across its range", function()
		expect(Rules.barShare(DR458Screen, 1000)).toBe(0)
		expect(Rules.barShare(DR458Screen, 5500)).toBeNear(0.5, 1e-9)
		expect(Rules.barShare(DR458Screen, 9500)).toBe(1)
	end)

	it("steps through its pages and back to the first", function()
		local pages = DR458Screen.pages
		expect(Rules.page(DR458Screen, 1)).toBe(pages[1])
		expect(Rules.page(DR458Screen, 3)).toBe(pages[3])
		expect(Rules.page(DR458Screen, 4)).toBe(pages[1])
	end)

	it("shows each field's readout, its fixed text, or -- for what is not simulated", function()
		local function text(reading: Binnacle.Reading, fixed: string?): string
			return Rules.fieldText({ label = "X", reading = reading, text = fixed }, READOUT)
		end
		expect(text("rpm")).toBe("6789")
		expect(text("gear")).toBe("R")
		expect(text("speed")).toBe("60")
		expect(text("tcs")).toBe("OFF")
		expect(text("manettino")).toBe("OFF")
		expect(text("static", "DDU3_v35F458_09")).toBe("DDU3_v35F458_09")
		expect(text("none")).toBe("--")
	end)
end)

describe("The DR458's binnacle", function()
	-- The labels photographed on a 458 Challenge Evo (12 §2.4, documented).
	local PHOTOGRAPHED = {
		{ "GEAR", "SPEED", "TCS", "POS", "OIL P", "P FUEL", "WATER T", "OIL T" },
		{
			"ABS FAIL",
			"TCS FAIL",
			"EDIFF FAIL",
			"BRAKE FAIL",
			"FRONT DISK",
			"REAR DISK",
			"BRAKE OIL",
			"PAD WEAR",
			"ODOMETER",
			"MANETTINO",
			"DDU FIRMWARE",
		},
		{
			"RPM",
			"FUEL %",
			"CHECK",
			"V_BATT",
			"T_WATER",
			"ANGLE",
			"TOIL ENGINE",
			"P_OIL",
			"P CARTER",
			"TOIL GEAR",
			"P_FUEL",
		},
	}

	it("has the three photographed pages, each with every label photographed on it", function()
		expect(#DR458Screen.pages).toBe(3)
		expect(DR458Switches.displayPages).toBe(3)
		for index, labels in PHOTOGRAPHED do
			local found: { [string]: boolean } = {}
			for _, field in DR458Screen.pages[index].fields do
				found[field.label] = true
			end
			for _, label in labels do
				expect(found[label] and label).toBe(label)
			end
		end
		expect(DR458Screen.pages[2].title).toBe("CHASSIS - BODY")
		expect(DR458Screen.pages[3].title).toBe("MECHANIC")
	end)

	it(
		"has one lamp, six rev lights and one lamp (12 §3.1, documented), and its bar marked 2 to 9",
		function()
			expect(#DR458Screen.revLights.colours).toBe(6)
			expect(DR458Screen.barFromRpm).toBe(2000)
			expect(DR458Screen.barToRpm).toBe(9000)
			expect(table.concat(DR458Screen.barMarks, ",")).toBe("2,3,4,5,6,7,8,9")
		end
	)
end)
