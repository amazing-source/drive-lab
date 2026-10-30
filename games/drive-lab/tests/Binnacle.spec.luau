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

describe("Binnacle band, pills and page fit", function()
	local function segment(rpm: number): Binnacle.Segment
		return {
			rpm = rpm,
			corners = { 0, 0, 0, 0, 0, 0, 0, 0 },
			rect = { x = 0, y = 0, width = 0, height = 0 },
			sprite = { image = "", x = 0, y = 0, width = 0, height = 0 },
		}
	end

	it("lights the band's segments from the first, each from its own rpm", function()
		local segments = { segment(1000), segment(1500), segment(2500) }
		expect(Rules.litSegments(segments, 999)).toBe(0)
		expect(Rules.litSegments(segments, 1000)).toBe(1)
		expect(Rules.litSegments(segments, 2499)).toBe(2)
		expect(Rules.litSegments(segments, 9000)).toBe(3)
	end)

	it("colours a pill by the text it shows, and nothing it has no colour for", function()
		local field: Binnacle.Field = { label = "TCS", reading = "tcs", pill = { OFF = RED, ON = GREEN } }
		expect(Rules.pillColour(field, "OFF")).toBe(RED)
		expect(Rules.pillColour(field, "ON")).toBe(GREEN)
		expect(Rules.pillColour(field, "--")).toBe(nil)
		expect(Rules.pillColour({ label = "OIL P", reading = "none" }, "--")).toBe(nil)
	end)

	it("centres a page at full height on a wider screen, at full width on a narrower one", function()
		local wide = Rules.fitPage(2.55, 2.4)
		expect(wide.y).toBe(0)
		expect(wide.height).toBe(1)
		expect(wide.width).toBeNear(2.4 / 2.55, 1e-9)
		expect(wide.x).toBeNear((1 - 2.4 / 2.55) / 2, 1e-9)
		local narrow = Rules.fitPage(2, 2.4)
		expect(narrow.x).toBe(0)
		expect(narrow.width).toBe(1)
		expect(narrow.height).toBeNear(2 / 2.4, 1e-9)
		expect(narrow.y).toBeNear((1 - 2 / 2.4) / 2, 1e-9)
	end)
end)

describe("The DR458's design layout", function()
	local driving = DR458Screen.pages[1].art
	local band = driving.band :: Binnacle.Band
	local function aspect(art: Binnacle.PageArt): number
		return art.art.width / art.art.height
	end

	local function inside(rect: Binnacle.Rect): boolean
		return rect.x >= 0 and rect.y >= 0 and rect.x + rect.width <= 1 and rect.y + rect.height <= 1
	end

	local function overlap(a: Binnacle.Rect | Binnacle.Sprite, b: Binnacle.Rect | Binnacle.Sprite): boolean
		return a.x < b.x + b.width and b.x < a.x + a.width and a.y < b.y + b.height and b.y < a.y + a.height
	end

	-- The middle of a segment's top edge, with x in the page's height units.
	local function top(segment: Binnacle.Segment): (number, number)
		local c = segment.corners
		return (c[1] + c[3]) / 2 * aspect(driving), (c[2] + c[4]) / 2
	end

	-- Where along the band (a fractional segment index) the point nearest (x, y) on the line
	-- through the segments' top edges lies.
	local function along(x: number, y: number): number
		local segments, best, at = band.segments, math.huge, 1
		for index = 1, #segments - 1 do
			local ax, ay = top(segments[index])
			local bx, by = top(segments[index + 1])
			local dx, dy = bx - ax, by - ay
			local t = math.clamp(((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy), 0, 1)
			local ex, ey = ax + t * dx - x, ay + t * dy - y
			if ex * ex + ey * ey < best then
				best, at = ex * ex + ey * ey, index + t
			end
		end
		return at
	end

	it("has every segment of the band side by side, rising in rpm from below its first mark", function()
		local segments = band.segments
		expect(#segments).toBe(59)
		for index, current in segments do
			expect(inside(current.rect) and `segment {index} on the page`).toBe(`segment {index} on the page`)
			local following = segments[index + 1]
			if following then
				expect(following.rpm > current.rpm and "rising").toBe("rising")
				expect(following.corners[1] >= current.corners[3] and "apart").toBe("apart")
			end
		end
		expect(segments[1].rpm < DR458Screen.barFromRpm and "below").toBe("below")
		expect(segments[#segments].rpm >= DR458Screen.redlineRpm and "past").toBe("past")
	end)

	it("reads each printed mark between the segments it is printed over", function()
		expect(#band.marks).toBe(#DR458Screen.barMarks)
		for index, mark in band.marks do
			expect(mark.rpm).toBe(DR458Screen.barMarks[index] * 1000)
			local at = along(mark.x * aspect(driving), mark.y)
			local below, above = band.segments[math.floor(at)].rpm, band.segments[math.ceil(at)].rpm
			local read = if below <= mark.rpm and mark.rpm <= above
				then mark.rpm
				else `{below} to {above} at segment {at}`
			expect(read).toBe(mark.rpm)
		end
	end)

	-- The label a value's slot reads as belonging to: the closest one above it and across its
	-- middle, or for a pill the closest one to its left on the same row.
	local function owner(art: Binnacle.PageArt, slot: Binnacle.Rect, pill: boolean): string?
		local sx, sy = slot.x + slot.width / 2, slot.y + slot.height / 2
		local found, best = nil, math.huge
		for name, label in art.labels do
			local gap: number? = nil
			if pill then
				local sameRow = math.abs(label.y + label.height / 2 - sy) <= label.height / 2
				if sameRow and label.x + label.width <= slot.x then
					gap = slot.x - (label.x + label.width)
				end
			elseif label.y + label.height <= slot.y and label.x <= sx and sx <= label.x + label.width then
				gap = slot.y - (label.y + label.height)
			end
			if gap and gap < best then
				found, best = name, gap
			end
		end
		return found
	end

	it("puts each value under its own label, or on the pill beside it", function()
		for _, page in DR458Screen.pages do
			local art = page.art
			for _, field in page.fields do
				local slot = art.slots[field.label]
				expect(slot and inside(slot) and field.label).toBe(field.label)
				expect(owner(art, slot, field.pill ~= nil)).toBe(field.label)
			end
		end
	end)

	it("keeps the slots of a page apart", function()
		for _, page in DR458Screen.pages do
			local fields = page.fields
			for i = 1, #fields do
				for j = i + 1, #fields do
					local a, b = fields[i].label, fields[j].label
					local apart = not overlap(page.art.slots[a], page.art.slots[b])
					expect(apart and "apart" or `{a} and {b}`).toBe("apart")
				end
			end
		end
	end)

	it("has a lens, an unlit and a lit image for each lamp of the strip", function()
		local lamps = #DR458Screen.revLights.colours + 2
		expect(#DR458Screen.lenses).toBe(lamps)
		expect(#DR458Screen.lamps.off).toBe(lamps)
		expect(#DR458Screen.lamps.on).toBe(lamps)
	end)

	it("gives every picture an uploaded image and its own part of its sheet", function()
		local sprites: { Binnacle.Sprite } = {}
		for _, page in DR458Screen.pages do
			table.insert(sprites, page.art.art)
			for _, pill in page.art.pills or {} do
				table.insert(sprites, pill.sprite)
			end
			for _, lit in if page.art.band then page.art.band.segments else {} do
				table.insert(sprites, lit.sprite)
			end
		end
		for _, kind in { DR458Screen.lamps.off, DR458Screen.lamps.on } do
			for _, lamp in kind do
				table.insert(sprites, lamp)
			end
		end
		for i, a in sprites do
			expect(string.match(a.image, "^rbxassetid://%d+$") ~= nil and "uploaded").toBe("uploaded")
			for j = i + 1, #sprites do
				local b = sprites[j]
				local apart = a.image ~= b.image or not overlap(a, b)
				expect(apart and "apart" or `pictures {i} and {j}`).toBe("apart")
			end
		end
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
