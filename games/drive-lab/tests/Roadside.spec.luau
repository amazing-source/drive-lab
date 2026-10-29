--!strict
local Config = require("../src/shared/Config/Roadside")
local Roadside = require("../src/shared/Rules/Roadside")
local T = require("../../../tools/test/T")
local Track = require("../src/shared/Config/Track")

local describe, it, expect = T.describe, T.it, T.expect

local SEED = 2026
local ROAD_HALF_WIDTH = 5.5
local GUARDRAILS = Config.GUARDRAILS

local function cut<V>(total: number, step: number, lay: (from: number, to: number) -> { V }): { V }
	local pieces = {}
	for from = 0, total - step, step do
		for _, value in lay(from, from + step) do
			table.insert(pieces, value)
		end
	end
	return pieces
end

describe("Roadside", function()
	describe("guardrails", function()
		it("lays the same pieces whichever way the road is cut", function()
			local whole = Roadside.guardrailPieces(0, 6000, SEED, GUARDRAILS)
			local pieces = cut(6000, 600, function(from, to)
				return Roadside.guardrailPieces(from, to, SEED, GUARDRAILS)
			end)
			expect(#whole > 20).toBe(true)
			expect(#pieces).toBe(#whole)
			for index, piece in whole do
				expect(pieces[index].s).toBeNear(piece.s, 1e-9)
				expect(pieces[index].side).toBe(piece.side)
				expect(pieces[index].kind).toBe(piece.kind)
				expect(pieces[index].variant).toBe(piece.variant)
			end
		end)

		it("cuts each stretch to whole sections inside its own slot, none overlapping", function()
			local stretches = Roadside.guardrails(0, 40000, SEED, GUARDRAILS)
			local lastEnd = { [-1] = -math.huge, [1] = -math.huge }
			table.sort(stretches, function(a, b)
				return a.from < b.from
			end)
			for _, stretch in stretches do
				local length = stretch.to - stretch.from
				local sections = length / GUARDRAILS.section
				expect(sections).toBeNear(math.floor(sections + 0.5), 1e-9)
				expect(sections >= 1).toBe(true)
				expect(stretch.from - GUARDRAILS.terminal >= stretch.slot * GUARDRAILS.spacing - 1e-9).toBe(
					true
				)
				expect(stretch.to + GUARDRAILS.terminal <= (stretch.slot + 1) * GUARDRAILS.spacing + 1e-9).toBe(
					true
				)
				expect(stretch.from - GUARDRAILS.terminal >= lastEnd[stretch.side]).toBe(true)
				lastEnd[stretch.side] = stretch.to + GUARDRAILS.terminal
			end
		end)

		it("guards a share of each verge, not all of it, and alternates the section models", function()
			local covered = { [-1] = 0, [1] = 0 }
			for _, stretch in Roadside.guardrails(0, 40000, SEED, GUARDRAILS) do
				covered[stretch.side] += stretch.to - stretch.from
			end
			for _, length in covered do
				expect(length / 40000 > 0.1 and length / 40000 < 0.5).toBe(true)
			end
			local variants = {}
			for _, piece in Roadside.guardrailPieces(0, 40000, SEED, GUARDRAILS) do
				if piece.kind == "Section" then
					variants[piece.variant] = (variants[piece.variant] or 0) + 1
				end
			end
			expect((variants[1] or 0) > 50 and (variants[2] or 0) > 50).toBe(true)
		end)
	end)

	describe("delineators", function()
		it("stand about 50 m apart, unevenly, and never where a guardrail runs", function()
			local reach = GUARDRAILS.terminal + Config.DELINEATOR_CLEARANCE
			local stretches = Roadside.guardrails(-1000, 21000, SEED, GUARDRAILS)
			local spots = Roadside.delineators(
				0,
				20000,
				SEED,
				Config.DELINEATORS,
				GUARDRAILS,
				Config.DELINEATOR_CLEARANCE
			)
			local last: { [number]: number } = {}
			local gaps: { number } = {}
			for _, spot in spots do
				expect(Roadside.guarded(stretches, spot.s, spot.side, reach)).toBe(false)
				local previous = last[spot.side]
				if
					previous and not Roadside.guarded(stretches, (previous + spot.s) / 2, spot.side, reach)
				then
					table.insert(gaps, spot.s - previous)
				end
				last[spot.side] = spot.s
			end
			table.sort(gaps)
			local median = gaps[#gaps // 2]
			expect(median).toBeNear(50, 4)
			expect(gaps[#gaps // 10] < 47 and gaps[#gaps - #gaps // 10] > 53).toBe(true)
		end)
	end)

	describe("gantries", function()
		it("span the road about every kilometre, unevenly", function()
			local found = Roadside.gantries(0, 60000, SEED, Config.GANTRIES)
			local gaps = {}
			for index = 2, #found do
				table.insert(gaps, found[index] - found[index - 1])
			end
			table.sort(gaps)
			expect(#found > 35 and #found < 80).toBe(true)
			expect(gaps[1] > 250).toBe(true)
			expect(gaps[#gaps] - gaps[1] > 500).toBe(true)
		end)
	end)

	describe("marks", function()
		it("are the same whichever way the road is cut", function()
			local whole = Roadside.marks(0, 3000, SEED, Config.MARKS)
			local pieces = cut(3000, 600, function(from, to)
				return Roadside.marks(from, to, SEED, Config.MARKS)
			end)
			expect(#pieces).toBe(#whole)
			for index, mark in whole do
				expect(pieces[index].s).toBeNear(mark.s, 1e-9)
				expect(pieces[index].kind).toBe(mark.kind)
				expect(pieces[index].offset).toBeNear(mark.offset, 1e-9)
				expect(pieces[index].length).toBeNear(mark.length, 1e-9)
			end
		end)

		it("stay on the asphalt, every kind present, some cracks across the road", function()
			local kinds: { [string]: number } = {}
			local across = 0
			for _, mark in Roadside.marks(0, 20000, SEED, Config.MARKS) do
				local reach = math.abs(math.sin(mark.yaw)) * mark.length / 2
					+ math.abs(math.cos(mark.yaw)) * mark.width / 2
				expect(math.abs(mark.offset) + reach <= ROAD_HALF_WIDTH).toBe(true)
				kinds[mark.kind] = (kinds[mark.kind] or 0) + 1
				if mark.kind == "Crack" and math.abs(math.cos(mark.yaw)) < 0.5 then
					across += 1
				end
			end
			for _, spec in Config.MARKS.kinds do
				expect((kinds[spec.kind] or 0) > 20).toBe(true)
			end
			expect(across / kinds.Crack > 0.2 and across / kinds.Crack < 0.5).toBe(true)
		end)
	end)
end)

describe("Roadside road end", function()
	it("spans the width with the fewest whole sections, centred and end to end", function()
		local section = GUARDRAILS.section
		for _, width in { 11, 24, 25, 131 } do
			local lefts = Roadside.roadEnd(width, section)
			expect(#lefts).toBe(math.ceil(width / section))
			expect(lefts[1] <= -width / 2 + 1e-9).toBe(true)
			expect(lefts[#lefts] + section >= width / 2 - 1e-9).toBe(true)
			expect(lefts[1] + lefts[#lefts] + section).toBeNear(0, 1e-9)
			for index = 2, #lefts do
				expect(lefts[index] - lefts[index - 1]).toBeNear(section, 1e-9)
			end
		end
	end)

	it("closes the whole road and both verges behind the spawn", function()
		local width = Track.ROAD_WIDTH + 2 * Track.VERGE_WIDTH
		local lefts = Roadside.roadEnd(width, GUARDRAILS.section)
		expect(-lefts[1] >= width / 2).toBe(true)
		expect(lefts[#lefts] + GUARDRAILS.section >= width / 2).toBe(true)
		expect(Config.ROAD_END_SETBACK > 0).toBe(true)
	end)
end)
