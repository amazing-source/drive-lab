--!strict
local Bridges = require("../src/shared/Rules/Bridges")
local Circuit = require("../src/shared/Rules/Circuit")
local Config = require("../src/shared/Config/Circuit")
local Roadside = require("../src/shared/Rules/Roadside")
local RoadsideConfig = require("../src/shared/Config/Roadside")
local StreetLamps = require("../src/shared/Rules/StreetLamps")
local T = require("../../../tools/test/T")
local Track = require("../src/shared/Config/Track")
local TrackPath = require("../src/shared/Rules/TrackPath")

local describe, it, expect = T.describe, T.it, T.expect

local GUARDRAILS = RoadsideConfig.GUARDRAILS
local BRIDGE = Config.BRIDGE
local START: TrackPath.Point = { x = 0, z = 0, dirX = 0, dirZ = -1, s = 0 }
local LAP = Circuit.build(Config.SEGMENTS, START)

local function spansOf(course: Circuit.Course, river: Bridges.River): ({ Bridges.Span }, { string })
	return Bridges.spans(course, river, BRIDGE, Track.ROAD_WIDTH, GUARDRAILS)
end

local SPANS = spansOf(LAP, Config.RIVER)

-- Where nothing else may stand: the deck, its guardrails and their terminals.
local function guardedReach(span: Bridges.Span): (number, number)
	local reach = BRIDGE.approach + GUARDRAILS.terminal
	return span.from - reach, span.to + reach
end

describe("Bridges", function()
	it("bridges every river crossing, each on a straight, square across, clear of the bends", function()
		local spans, problems = spansOf(LAP, Config.RIVER)
		expect(#problems).toBe(0)
		expect(#spans).toBe(#Circuit.crossings(LAP, Config.RIVER.offset))
		expect(#spans).toBe(2)
		for _, span in spans do
			local piece = Circuit.pieceAt(LAP, span.crossing)
			expect(piece.kind).toBe("Straight")
			local first, last = guardedReach(span)
			expect(first >= piece.from and last <= piece.from + piece.length).toBe(true)
			expect(span.channelTo - span.channelFrom >= Config.RIVER.width).toBe(true)
			expect(span.channelFrom - span.from).toBeNear(BRIDGE.margin, 1e-9)
			expect(span.to - span.channelTo).toBeNear(BRIDGE.margin, 1e-9)
		end
	end)

	it("reports a crossing on a bend, or too slanted, instead of bridging it", function()
		local _, onBends = spansOf(LAP, { offset = 600, width = Config.RIVER.width })
		expect(#onBends).toBe(2)
		expect(string.find(onBends[1], "bend") ~= nil).toBe(true)
		-- A lap with a straight at 45 degrees to the start line, which a river 120 m right crosses.
		local slanted = Circuit.build({
			{ kind = "Straight", length = 300 },
			{ kind = "Arc", radius = 50, turn = 45 },
			{ kind = "Straight", length = 300 },
			{ kind = "Arc", radius = 50, turn = 45 },
			{ kind = "Arc", radius = 50, turn = 90 },
			{ kind = "Closing", minimum = 10 },
			{ kind = "Arc", radius = 50, turn = 90 },
			{ kind = "Closing", minimum = 10 },
			{ kind = "Arc", radius = 50, turn = 90 },
		}, START)
		local spans, problems = spansOf(slanted, { offset = 120, width = Config.RIVER.width })
		local found = false
		for _, problem in problems do
			found = found or string.find(problem, "under") ~= nil
		end
		expect(found).toBe(true)
		for _, span in spans do
			expect(Circuit.pieceAt(slanted, span.crossing).kind).toBe("Straight")
		end
	end)

	it("keeps the full-depth road out of the channel and rests the deck on it at both banks", function()
		local points = Circuit.points(LAP, 0, LAP.length, Track.STEP)
		local gaps: { [number]: { from: number, to: number } } = {}
		local previous = Circuit.pointAt(LAP, 0)
		for _, point in points do
			local length = point.s - previous.s
			local reach = (
				TrackPath.blockLength(length, Track.ROAD_WIDTH, TrackPath.turn(previous, point)) - length
			) / 2
			if Bridges.fullDepth(SPANS, previous, point, Track.ROAD_WIDTH, BRIDGE) then
				expect(Bridges.overChannel(SPANS, previous.s - reach, point.s + reach)).toBe(false)
			else
				local inside = 0
				for index, span in SPANS do
					if previous.s >= span.from and point.s <= span.to then
						inside = index
					end
				end
				expect(inside > 0).toBe(true)
				local gap = gaps[inside] or { from = math.huge, to = -math.huge }
				gap.from = math.min(gap.from, previous.s)
				gap.to = math.max(gap.to, point.s)
				gaps[inside] = gap
			end
			previous = point
		end
		for index, span in SPANS do
			local gap = gaps[index]
			expect(gap ~= nil).toBe(true)
			assert(gap)
			expect(gap.from <= span.channelFrom and gap.to >= span.channelTo).toBe(true)
			expect(gap.from - span.from >= BRIDGE.bearing).toBe(true)
			expect(span.to - gap.to >= BRIDGE.bearing).toBe(true)
		end
	end)

	it("leaves the whole road's width clear between the parapets", function()
		expect(BRIDGE.kerb >= BRIDGE.parapetWidth).toBe(true)
		for _, span in SPANS do
			for _, parapet in Bridges.parapets(span, BRIDGE, Track.ROAD_WIDTH) do
				expect(parapet.inner >= Track.ROAD_WIDTH / 2).toBe(true)
				expect(parapet.inner + BRIDGE.parapetWidth).toBeNear(Track.ROAD_WIDTH / 2 + BRIDGE.kerb, 1e-9)
			end
		end
	end)

	it("runs a parapet along both edges of every deck, its face continuing the guardrail's", function()
		for _, span in SPANS do
			local sides = {}
			for _, parapet in Bridges.parapets(span, BRIDGE, Track.ROAD_WIDTH) do
				sides[parapet.side] = true
				expect(parapet.from <= span.from and parapet.to >= span.to).toBe(true)
				expect(parapet.inner).toBeNear(Track.ROAD_WIDTH / 2 + RoadsideConfig.GUARDRAIL_SETBACK, 1e-9)
			end
			expect(sides[-1] and sides[1]).toBe(true)
		end
	end)

	it("leads a guardrail onto and away from every parapet end, the same however the road is cut", function()
		local whole = Bridges.guardrailPieces(SPANS, 0, LAP.length, BRIDGE, GUARDRAILS)
		local cut = {}
		for from = 0, LAP.length, 600 do
			for _, piece in Bridges.guardrailPieces(SPANS, from, from + 600, BRIDGE, GUARDRAILS) do
				table.insert(cut, piece)
			end
		end
		expect(#cut).toBe(#whole)
		local sections = BRIDGE.approach / GUARDRAILS.section
		expect(sections).toBe(math.floor(sections))
		for _, span in SPANS do
			for _, side in { -1, 1 } do
				local found = { Start = 0, Section = 0, End = 0 }
				local reach = { from = math.huge, to = -math.huge }
				for _, piece in whole do
					if piece.side == side and piece.s >= span.from - 100 and piece.s <= span.to + 100 then
						found[piece.kind] += 1
						if piece.kind == "Section" then
							local inDeck = piece.s + GUARDRAILS.section > span.from and piece.s < span.to
							expect(inDeck).toBe(false)
							reach.from = math.min(reach.from, piece.s)
							reach.to = math.max(reach.to, piece.s + GUARDRAILS.section)
						elseif piece.kind == "Start" then
							expect(piece.s).toBeNear(span.from - BRIDGE.approach, 1e-9)
						else
							expect(piece.s).toBeNear(span.to + BRIDGE.approach, 1e-9)
						end
					end
				end
				expect(found.Start).toBe(1)
				expect(found.End).toBe(1)
				expect(found.Section).toBe(2 * sections)
				expect(reach.from).toBeNear(span.from - BRIDGE.approach, 1e-9)
				expect(reach.to).toBeNear(span.to + BRIDGE.approach, 1e-9)
			end
		end
	end)

	it("keeps lamps, posts, other guardrails and gantries off every bridge and its guardrails", function()
		local zones = Bridges.keepOut(SPANS, BRIDGE, GUARDRAILS)
		local function guarded(s: number): boolean
			for _, span in SPANS do
				local first, last = guardedReach(span)
				if s >= first - BRIDGE.clearance and s <= last + BRIDGE.clearance then
					return true
				end
			end
			return false
		end
		local lamps = StreetLamps.spots(0, LAP.length, Track.SEED, Track.LAMPS, zones)
		local posts = Roadside.delineators(
			0,
			LAP.length,
			Track.SEED,
			RoadsideConfig.DELINEATORS,
			GUARDRAILS,
			RoadsideConfig.DELINEATOR_CLEARANCE,
			zones
		)
		expect(#lamps > 50 and #posts > 30).toBe(true)
		for _, spot in lamps do
			expect(guarded(spot.s)).toBe(false)
		end
		for _, spot in posts do
			expect(guarded(spot.s)).toBe(false)
		end
		for _, s in Roadside.gantries(0, LAP.length, Track.SEED, RoadsideConfig.GANTRIES, zones) do
			expect(guarded(s)).toBe(false)
		end
		for _, stretch in Roadside.guardrails(0, LAP.length, Track.SEED, GUARDRAILS, zones) do
			for s = stretch.from - GUARDRAILS.terminal, stretch.to + GUARDRAILS.terminal, 1 do
				expect(guarded(s)).toBe(false)
			end
		end
	end)
end)
