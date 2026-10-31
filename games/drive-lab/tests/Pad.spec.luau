--!strict
local Config = require("../src/shared/Config/Pad")
local Pad = require("../src/shared/Rules/Pad")
local T = require("../../../tools/test/T")
local Units = require("../src/shared/Units")

local describe, it, expect = T.describe, T.it, T.expect

local AREA, PAVING, MARKINGS = Config.AREA, Config.PAVING, Config.MARKINGS
-- A terrain voxel is 4 studs; Roblox caps a part's size at 2048 studs.
local VOXEL = Units.studsToMetres(4)
local LONGEST_PART = Units.studsToMetres(2048)

local function inside(bounds: Pad.Bounds, along: number, across: number, margin: number): boolean
	return along >= bounds.alongFrom + margin
		and along <= bounds.alongTo - margin
		and across >= bounds.acrossFrom + margin
		and across <= bounds.acrossTo - margin
end

local function ofKind(kind: Pad.StripeKind): { Pad.Stripe }
	local found = {}
	for _, stripe in Pad.stripes(AREA, MARKINGS) do
		if stripe.kind == kind then
			table.insert(found, stripe)
		end
	end
	return found
end

describe("Pad", function()
	it("paves about 800 m square round the parked cars, with room on every side of them", function()
		local outer = Pad.bounds(AREA)
		expect(outer.alongTo - outer.alongFrom).toBeNear(800, 1e-9)
		expect(outer.acrossTo - outer.acrossFrom).toBeNear(800, 1e-9)
		expect(inside(Pad.inner(AREA), 0, 0, 20)).toBe(true)
	end)

	it("covers every metre of the square with asphalt fills that overlap by more than a voxel", function()
		expect(PAVING.overlap > VOXEL).toBe(true)
		local outer = Pad.bounds(AREA)
		local fills = Pad.fills(AREA, PAVING)
		for _, fill in fills do
			expect(fill.alongFrom >= outer.alongFrom and fill.alongTo <= outer.alongTo).toBe(true)
			expect(fill.acrossFrom >= outer.acrossFrom and fill.acrossTo <= outer.acrossTo).toBe(true)
		end
		-- Every point is inside a fill by at least the overlap, unless it is within that of the edge.
		for along = outer.alongFrom, outer.alongTo, 0.5 do
			for across = outer.acrossFrom, outer.acrossTo, 7.3 do
				local deepest = 0
				for _, fill in fills do
					local depth = math.min(
						along - fill.alongFrom,
						fill.alongTo - along,
						across - fill.acrossFrom,
						fill.acrossTo - across
					)
					deepest = math.max(deepest, depth)
				end
				local fromEdge = math.min(
					along - outer.alongFrom,
					outer.alongTo - along,
					across - outer.acrossFrom,
					outer.acrossTo - across
				)
				expect(deepest >= math.min(PAVING.overlap, fromEdge) - 1e-9).toBe(true)
			end
		end
	end)

	it("keeps every painted line inside the run-off's edge line", function()
		local inner = Pad.inner(AREA)
		for _, stripe in Pad.stripes(AREA, MARKINGS) do
			local first, last = Pad.ends(stripe)
			local margin = if stripe.kind == "Edge" then -MARKINGS.width else MARKINGS.width
			expect(inside(inner, first.along, first.across, margin)).toBe(true)
			expect(inside(inner, last.along, last.across, margin)).toBe(true)
		end
		expect(AREA.runOff >= 50).toBe(true)
	end)

	it("draws each circle true and closed at its diameter", function()
		local circles = ofKind("Circle")
		local index = 1
		for _, spec in MARKINGS.circles do
			local radius = spec.diameter / 2
			local count = math.max(8, math.ceil(2 * math.pi * radius / MARKINGS.chord))
			local turned = 0
			for _ = 1, count do
				local stripe = circles[index]
				index += 1
				local reach = math.sqrt((stripe.along - spec.along) ^ 2 + (stripe.across - spec.across) ^ 2)
				local half = math.asin((stripe.length - MARKINGS.width) / (2 * radius))
				-- The chord's middle sits a sagitta inside the circle, and the sagitta stays small.
				expect(reach).toBeNear(radius * math.cos(half), 1e-9)
				expect(radius - reach <= 0.05).toBe(true)
				-- Square to the radius.
				local outward = math.atan2(stripe.across - spec.across, stripe.along - spec.along)
				expect(math.abs(math.cos(stripe.yaw - outward))).toBeNear(0, 1e-9)
				turned += 2 * half
			end
			expect(turned).toBeNear(2 * math.pi, 1e-9)
		end
		expect(index - 1).toBe(#circles)
		expect(MARKINGS.circles[1].diameter).toBe(60)
		expect(MARKINGS.circles[2].diameter).toBe(120)
	end)

	it("keeps the circles and the straight apart", function()
		local specs = MARKINGS.circles
		local straight = MARKINGS.straight
		for i, a in specs do
			for j = i + 1, #specs do
				local b = specs[j]
				local apart = math.sqrt((a.along - b.along) ^ 2 + (a.across - b.across) ^ 2)
				expect(apart - (a.diameter + b.diameter) / 2 >= 30).toBe(true)
			end
			expect(math.abs(a.across - straight.across) - a.diameter / 2 >= 30).toBe(true)
		end
	end)

	it("runs a long straight with a cross mark every 100 m from end to end", function()
		local straight = MARKINGS.straight
		expect(straight.to - straight.from >= 500).toBe(true)
		local length = 0
		for _, stripe in ofKind("Straight") do
			length += stripe.length
			expect(stripe.yaw).toBe(0)
			expect(stripe.across).toBe(straight.across)
		end
		expect(length).toBeNear(straight.to - straight.from, 1e-9)
		local marks = ofKind("Mark")
		expect(#marks).toBe(math.floor((straight.to - straight.from) / straight.every) + 1)
		for index, mark in marks do
			expect(mark.along).toBeNear(straight.from + (index - 1) * straight.every, 1e-9)
			expect(mark.length).toBe(straight.mark)
		end
	end)

	it("makes no part longer than Roblox allows", function()
		expect(MARKINGS.longest <= LONGEST_PART).toBe(true)
		for _, stripe in Pad.stripes(AREA, MARKINGS) do
			expect(stripe.length <= MARKINGS.longest + MARKINGS.width + 1e-9).toBe(true)
		end
	end)

	it("paints lines the car's wheels and body pass through, just clear of the asphalt", function()
		local stripe = Config.STRIPE
		-- The wheels' rays (VehicleRunner) skip a part only if it cannot be queried, which Roblox
		-- allows only for a part that does not collide.
		expect(stripe.canQuery).toBe(false)
		expect(stripe.canCollide).toBe(false)
		expect(stripe.canTouch).toBe(false)
		expect(stripe.lift > 0).toBe(true)
		expect(stripe.lift + stripe.thickness <= 0.02).toBe(true)
	end)
end)
