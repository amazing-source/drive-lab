--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Catalog = require("../src/shared/Config/Cars/Catalog")
local Contract = require("../src/shared/Config/Cars/Contract")
local DR458Hud = require("../src/shared/Config/Cars/DR458/Hud")
local HudDesign = require("../src/shared/Config/HudDesign")
local Rules = require("../src/shared/Rules/Hud")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

-- Config/Hud holds Color3 and Vector2 values, which Lune has only through its roblox library:
-- loaded from its file with them, so these tests read the global HUD's real values.
local function globalHud(): any
	local path = "games/drive-lab/src/shared/Config/Hud.luau"
	local chunk = luau.load(fs.readFile(path), {
		debugName = path,
		environment = { Color3 = roblox.Color3, Vector2 = roblox.Vector2 },
	})
	return chunk()
end

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

-- An unfrozen copy of the DR458's HUD with one change made by `change`.
local function hudWith(change: (any) -> ()): HudDesign.Design
	local hud = copy(DR458Hud)
	change(hud)
	return hud
end

local function refuses(change: (any) -> (), message: string)
	local ok, problem = pcall(HudDesign.check, hudWith(change))
	expect(ok).toBe(false)
	expect(string.find(tostring(problem), message, 1, true) ~= nil).toBe(true)
end

local function rgb(colour: any): { number }
	return { math.round(colour.R * 255), math.round(colour.G * 255), math.round(colour.B * 255) }
end

-- A value written out with its keys in order, so two tables compare by content and a mismatch
-- prints both.
local function show(value: any): string
	if type(value) ~= "table" then
		return if type(value) == "number" then string.format("%.10g", value) else tostring(value)
	end
	local keys = {}
	for key in value do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	local parts = {}
	for _, key in keys do
		table.insert(parts, `{tostring(key)}={show(value[key])}`)
	end
	return `\{{table.concat(parts, ",")}\}`
end

local function same(actual: any, expected: any)
	expect(show(actual)).toBe(show(expected))
end

describe("Car HUDs", function()
	it("gives the DR458 its own HUD and leaves the SVJ on the global one", function()
		expect(Catalog.cars.DR458.hud).toBe(DR458Hud)
		expect(Catalog.cars.SVJ.hud).toBe(nil)
	end)

	it("keeps the global HUD the SVJ falls back to, value for value", function()
		local hud = globalHud()
		expect(hud.FRAME_IMAGE).toBe("rbxassetid://136575325662647")
		expect(hud.PARTS_IMAGE).toBe("rbxassetid://122022683037511")
		same({ hud.FRAME_SIZE.X, hud.FRAME_SIZE.Y }, { 2078, 477 })
		same(hud.SEGMENTS, {
			{ 314, 65, 499, 101 },
			{ 479, 62, 647, 101 },
			{ 625, 62, 788, 101 },
			{ 767, 62, 929, 101 },
			{ 908, 62, 1071, 101 },
			{ 1050, 62, 1211, 101 },
			{ 1190, 62, 1350, 101 },
			{ 1332, 62, 1500, 101 },
			{ 1474, 62, 1642, 101 },
			{ 1618, 62, 1750, 93 },
		})
		same(hud.PARTS, {
			first = { 0, 0, 185, 36 },
			middle = { 189, 0, 168, 39 },
			last = { 361, 0, 132, 31 },
			light = { 497, 0, 80, 62 },
		})
		same(hud.READOUTS, {
			mode = { 271, 244, 489, 280 },
			tcText = { 305, 341, 355, 366 },
			tcLine = { 284, 389, 376, 396 },
			absText = { 518, 342, 599, 366 },
			absLine = { 510, 390, 609, 395 },
			box = { 1021, 194, 1058, 219 },
			gear = { 910, 240, 1115, 438 },
			speed = { 1347, 219, 1765, 345 },
			light = { 1763, 378, 1825, 425 },
			indicatorLeft = { 1708, 376, 1743, 428 },
			indicatorRight = { 1843, 376, 1878, 428 },
		})
		same({
			hud.HEIGHT,
			hud.COCKPIT_HEIGHT,
			hud.MAX_WIDTH,
			hud.MARGIN,
			hud.MINIMAL_SCALE,
			hud.RPM_PER_SEGMENT,
			hud.FLASH_HZ,
			hud.CAP_HEIGHT,
			hud.UPDATE_INTERVAL,
			hud.GEAR_POP,
			hud.LAUNCH_TEXT,
		}, { 0.17, 0.13, 0.9, 14, 0.72, 1000, 2.5, 0.59, 1 / 30, 0.12, "LAUNCH" })
		same({
			rgb(hud.YELLOW),
			rgb(hud.RED),
			rgb(hud.BLUE),
			rgb(hud.WHITE),
			rgb(hud.GREY),
			rgb(hud.LINE_GREY),
			rgb(hud.GREEN),
			rgb(hud.OFF),
		}, {
			{ 253, 208, 2 },
			{ 240, 20, 24 },
			{ 61, 123, 255 },
			{ 242, 242, 242 },
			{ 82, 82, 83 },
			{ 61, 61, 60 },
			{ 0, 216, 55 },
			{ 58, 57, 56 },
		})
	end)

	it("has the rev bar's ten segments on both HUDs", function()
		expect(HudDesign.SEGMENTS).toBe(10)
		expect(#DR458Hud.segments).toBe(10)
		expect(#globalHud().SEGMENTS).toBe(10)
		refuses(function(hud)
			table.remove(hud.segments)
		end, "9 rev segments, not 10")
	end)

	it(
		"starts each car's red zone at its own redline: the DR458's last segment, half of the SVJ's ninth",
		function()
			local perSegment = globalHud().RPM_PER_SEGMENT
			local dr458 = Contract.redline(Catalog.cars.DR458)
			expect(dr458).toBe(9000)
			expect(Rules.segmentShare(dr458, 9, perSegment)).toBe(1)
			expect(Rules.segmentShare(dr458, 10, perSegment)).toBe(0)
			local svj = Contract.redline(Catalog.cars.SVJ)
			expect(svj).toBe(8500)
			expect(Rules.segmentShare(svj, 9, perSegment)).toBe(0.5)
		end
	)

	it(
		"accepts the DR458's HUD as it is, and without glyphs, its gear and speed then upright text",
		function()
			HudDesign.check(DR458Hud)
			HudDesign.check(hudWith(function(hud)
				hud.glyphs = nil
			end))
			expect(DR458Hud.digitFace.family).toBe("rbxasset://fonts/families/Sarpanch.json")
			expect(DR458Hud.digitFace.weight).toBe("Bold")
		end
	)

	it("refuses images that are not uploaded assets", function()
		refuses(function(hud)
			hud.frameImage = "rbxassetid://0"
		end, "not uploaded assets")
		refuses(function(hud)
			hud.partsImage = "hud_parts.png"
		end, "not uploaded assets")
	end)

	it("refuses a box outside the frame", function()
		refuses(function(hud)
			hud.segments[10][3] = 2173
		end, "rev segment 10 lies outside its frame")
		refuses(function(hud)
			hud.texts.speed[1] = -1
		end, "speed lies outside its frame")
		refuses(function(hud)
			hud.light.box = { 2100, 614, 2187, 678 }
		end, "headlight lies outside its frame")
	end)

	it("refuses a mask outside the atlas, or a part drawn at another size than its mask", function()
		refuses(function(hud)
			hud.segmentRect[1] = 800
		end, "rev segment 1 mask lies outside its atlas")
		refuses(function(hud)
			hud.glyphs.rects["7"][2] = 500
		end, "glyph 7 lies outside its atlas")
		refuses(function(hud)
			hud.indicators.left.box[3] += 1
		end, "left indicator is drawn at another size than its mask")
	end)

	it("refuses a missing glyph, digits of different widths, or a box too narrow for them", function()
		refuses(function(hud)
			hud.glyphs.rects.R = nil
		end, "no glyph for R")
		refuses(function(hud)
			hud.glyphs.rects["3"][3] = 170
		end, "digit 3 is not as wide as the others")
		refuses(function(hud)
			hud.glyphs.speed[1] += 2
		end, "does not hold 3 digits")
		refuses(function(hud)
			hud.glyphs.gear = { 1000, 439, 1172, 657 }
		end, "gear 1 is wider than its box")
	end)

	it("refuses a car whose HUD fails, at load", function()
		local entry = copy(Catalog.cars.DR458)
		entry.hud.segments[1][1] = -5
		expect(function()
			Contract.define(entry)
		end).toThrow()
	end)
end)
