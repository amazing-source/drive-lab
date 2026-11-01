--!strict
--[[
	A seven-segment display: which segments light for a character, how a number is printed on a
	given count of digits, and where each segment sits in its cell. Segments are named as on a
	datasheet: a top, b top right, c bottom right, d bottom, e bottom left, f top left, g middle.
]]

-- One digit's place: the segments it lights and whether its decimal point does.
export type Cell = { segments: string, point: boolean }

-- A segment's rectangle in its cell, as shares of the cell's width and height from its top left.
export type Rect = { x: number, y: number, width: number, height: number }

local SEGMENTS = "abcdefg"

local GLYPHS: { [string]: string } = table.freeze({
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
	["-"] = "g",
	[" "] = "",
})

local SevenSegment = { SEGMENTS = SEGMENTS }

-- The cells `text` lights on `digits` digits, right-aligned; a "." lights the point of the digit
-- before it. Characters the display cannot show stay dark.
function SevenSegment.cells(text: string, digits: number): { Cell }
	local found: { Cell } = {}
	for index = 1, #text do
		local character = string.sub(text, index, index)
		if character == "." and #found > 0 then
			found[#found].point = true
		else
			table.insert(found, { segments = GLYPHS[character] or "", point = false })
		end
	end
	local cells: { Cell } = table.create(digits)
	for index = 1, digits do
		cells[index] = found[#found - digits + index] or { segments = "", point = false }
	end
	return cells
end

function SevenSegment.lit(cell: Cell, segment: string): boolean
	return string.find(cell.segments, segment, 1, true) ~= nil
end

-- `value`'s magnitude with `decimals` places, held at the largest the digits can show.
function SevenSegment.number(value: number, digits: number, decimals: number): string
	local largest = 10 ^ (digits - decimals) - 10 ^ -decimals
	local shown = math.min(math.abs(value), largest)
	return string.format(`%.{decimals}f`, shown)
end

--[[
	Each segment's rectangle in a cell whose bars are `thickness` of the cell's height thick, a
	`gap` of its height clear of each other at the corners: the horizontal bars span the cell's
	width between the vertical ones, the vertical bars each half its height.
]]
function SevenSegment.layout(thickness: number, gap: number, aspect: number): { [string]: Rect }
	local barX = thickness / aspect
	local half = (1 - thickness) / 2
	local across = { x = barX + gap / aspect, width = 1 - 2 * (barX + gap / aspect) }
	local upper = { y = thickness / 2 + gap, height = half - 2 * gap }
	local lower = { y = 0.5 + gap, height = half - 2 * gap }
	return {
		a = { x = across.x, y = 0, width = across.width, height = thickness },
		g = { x = across.x, y = 0.5 - thickness / 2, width = across.width, height = thickness },
		d = { x = across.x, y = 1 - thickness, width = across.width, height = thickness },
		f = { x = 0, y = upper.y, width = barX, height = upper.height },
		b = { x = 1 - barX, y = upper.y, width = barX, height = upper.height },
		e = { x = 0, y = lower.y, width = barX, height = lower.height },
		c = { x = 1 - barX, y = lower.y, width = barX, height = lower.height },
	}
end

return table.freeze(SevenSegment)
