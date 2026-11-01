--!strict
local Boss302Gauges = require("../src/shared/Config/Cars/Boss302/Gauges")
local Gauges = require("../src/shared/Config/Gauges")
local MessageCentre = require("../src/shared/Rules/MessageCentre")
local SevenSegment = require("../src/shared/Rules/SevenSegment")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local function litSet(cell: SevenSegment.Cell): string
	local lit = {}
	for index = 1, #SevenSegment.SEGMENTS do
		local segment = string.sub(SevenSegment.SEGMENTS, index, index)
		if SevenSegment.lit(cell, segment) then
			table.insert(lit, segment)
		end
	end
	return table.concat(lit)
end

describe("Seven-segment readout", function()
	it("lights each digit's datasheet segments", function()
		local expected = {
			["0"] = "abcdef",
			["1"] = "bc",
			["2"] = "abdeg",
			["3"] = "abcdg",
			["4"] = "bcfg",
			["5"] = "acdfg",
			["6"] = "acdefg",
			["7"] = "abc",
			["8"] = "abcdefg",
			["9"] = "abcdfg",
		}
		for digit, segments in expected do
			expect(litSet(SevenSegment.cells(digit, 1)[1])).toBe(segments)
		end
	end)

	it("prints right-aligned, a point lighting the digit before it", function()
		local cells = SevenSegment.cells("0.01", 3)
		expect(cells[1].point).toBe(true)
		expect(cells[2].point).toBe(false)
		expect(litSet(cells[3])).toBe("bc")
		local short = SevenSegment.cells("5", 3)
		expect(litSet(short[1]) .. "|" .. litSet(short[2]) .. "|" .. litSet(short[3])).toBe("||acdfg")
		local long = SevenSegment.cells("1234", 3)
		expect(litSet(long[1])).toBe("abdeg")
		expect(litSet(SevenSegment.cells("Z", 1)[1])).toBe("")
	end)

	it("prints a reading's magnitude to its decimals, held at what it can show", function()
		expect(SevenSegment.number(0, 3, 2)).toBe("0.00")
		expect(SevenSegment.number(0.004, 3, 2)).toBe("0.00")
		expect(SevenSegment.number(0.456, 3, 2)).toBe("0.46")
		expect(SevenSegment.number(-0.7, 3, 2)).toBe("0.70")
		expect(SevenSegment.number(12.3, 3, 2)).toBe("9.99")
		expect(SevenSegment.number(1.26, 3, 1)).toBe("1.3")
	end)

	it("lays every segment inside its cell, none overlapping another", function()
		local shape = Gauges.SEGMENT
		local rects = SevenSegment.layout(shape.thickness, shape.gap, shape.aspect)
		local names = {}
		for name, rect in rects do
			table.insert(names, name)
			expect(rect.x >= 0 and rect.y >= 0 and rect.x + rect.width <= 1 + 1e-9).toBe(true)
			expect(rect.y + rect.height <= 1 + 1e-9 and rect.width > 0 and rect.height > 0).toBe(true)
		end
		expect(#names).toBe(7)
		for _, a in names do
			for _, b in names do
				if a < b then
					local p, q = rects[a], rects[b]
					local across = math.min(p.x + p.width, q.x + q.width) - math.max(p.x, q.x)
					local down = math.min(p.y + p.height, q.y + q.height) - math.max(p.y, q.y)
					expect(if across > 1e-9 and down > 1e-9 then `{a} overlaps {b}` else "apart").toBe(
						"apart"
					)
				end
			end
		end
	end)
end)

describe("Message centre", function()
	local message = assert(Boss302Gauges.message, "the Boss has a message centre")

	it("shows the TracKey's message after a TracKey start until the car moves off", function()
		expect(table.concat(MessageCentre.lines(message, "TracKey", false, 0, 1000), " / ")).toBe(
			"TRACKEY ACTIVE / TRACK USE ONLY"
		)
		local moved = MessageCentre.movedOff(message, false, message.moveOffKmh + 1)
		expect(moved).toBe(true)
		expect(MessageCentre.movedOff(message, moved, 0)).toBe(true)
		expect(MessageCentre.movedOff(message, false, message.moveOffKmh)).toBe(false)
		expect(MessageCentre.lines(message, "TracKey", true, 0, 1000)[1]).toBe("TRIP A 0.0")
	end)

	it("shows the trip and the odometer in miles otherwise", function()
		local lines = MessageCentre.lines(message, "Standard", false, 1.609344 * 2.5, 1.609344 * 1313.9)
		expect(lines[1]).toBe("TRIP A 2.5")
		expect(lines[2]).toBe("1313.9 mi")
	end)
end)
