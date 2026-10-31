--!strict
--[[
	Where the test circuit's river passes under the road, and what each crossing is made of: a
	level deck spanning the channel and resting on solid road at both banks, a parapet along both
	of its edges whose face continues the guardrail's, a guardrail leading onto each parapet end,
	and a stretch around it kept clear of verge furniture, whose verges are not there.
]]
local Circuit = require("./Circuit")
local Roadside = require("./Roadside")
local Scatter = require("./Scatter")
local TrackPath = require("./TrackPath")

-- offset: metres right of the start line, the channel running parallel to the start direction.
export type River = { offset: number, width: number }

export type Layout = {
	-- Deck metres past the channel at each bank, and past the road's edge on each side.
	margin: number,
	kerb: number,
	-- Metres of guardrail leading onto each parapet end: whole sections.
	approach: number,
	-- Furniture kept this far past the approach guardrails' terminals.
	clearance: number,
	-- The full-depth road stops this far short of the channel.
	bankClearance: number,
	parapetWidth: number,
	-- The flattest crossing allowed, degrees off the river's line.
	minimumAngle: number,
}

-- Arc lengths (metres): where the centre line crosses, the channel's reach along the road, and
-- the deck.
export type Span = { crossing: number, channelFrom: number, channelTo: number, from: number, to: number }

-- side -1 left, 1 right; inner: metres right of the centre line to the face towards the road.
export type Parapet = { side: number, from: number, to: number, inner: number }

local Bridges = {}

-- The bridges where the river crosses the course, and why any crossing could not take one (the
-- road then crosses on full-depth ground). A bridge stands on one straight with its approach
-- guardrails and their terminals.
function Bridges.spans(
	course: Circuit.Course,
	river: River,
	layout: Layout,
	roadWidth: number,
	guardrails: Roadside.GuardrailLayout
): ({ Span }, { string })
	local spans, problems = {}, {}
	local steepest = math.sin(math.rad(layout.minimumAngle))
	for _, crossing in Circuit.crossings(course, river.offset) do
		local piece = course.pieces[crossing.piece]
		local where = string.format("%.0f m", crossing.s)
		if piece.kind ~= "Straight" then
			table.insert(problems, `the river crosses a bend at {where}`)
		elseif crossing.sine < steepest then
			table.insert(problems, `the river crosses at under {layout.minimumAngle} degrees at {where}`)
		else
			local cosine = math.sqrt(math.max(0, 1 - crossing.sine ^ 2))
			local half = river.width / 2 / crossing.sine
				+ (roadWidth / 2 + layout.kerb) * cosine / crossing.sine
			local span = {
				crossing = crossing.s,
				channelFrom = crossing.s - half,
				channelTo = crossing.s + half,
				from = crossing.s - half - layout.margin,
				to = crossing.s + half + layout.margin,
			}
			local reach = layout.approach + guardrails.terminal
			if span.from - reach < piece.from or span.to + reach > piece.from + piece.length then
				table.insert(problems, `the bridge at {where} and its guardrails run off their straight`)
			else
				table.insert(spans, span)
			end
		end
	end
	return spans, problems
end

-- Whether the road's step from a to b is laid on full-depth ground: not where its block, which
-- reaches past both ends of the step, would come within bankClearance of a channel.
function Bridges.fullDepth(
	spans: { Span },
	a: TrackPath.Point,
	b: TrackPath.Point,
	roadWidth: number,
	layout: Layout
): boolean
	local length = b.s - a.s
	local reach = (TrackPath.blockLength(length, roadWidth, TrackPath.turn(a, b)) - length) / 2
		+ layout.bankClearance
	return not Bridges.overChannel(spans, a.s - reach, b.s + reach)
end

-- Whether [from, to] reaches over a channel.
function Bridges.overChannel(spans: { Span }, from: number, to: number): boolean
	for _, span in spans do
		if to > span.channelFrom and from < span.channelTo then
			return true
		end
	end
	return false
end

-- The two parapets of a bridge, along the whole deck on its outer edges.
function Bridges.parapets(span: Span, layout: Layout, roadWidth: number): { Parapet }
	local inner = roadWidth / 2 + layout.kerb - layout.parapetWidth
	return {
		{ side = -1, from = span.from, to = span.to, inner = inner },
		{ side = 1, from = span.from, to = span.to, inner = inner },
	}
end

-- The guardrail pieces in [from, to) leading onto and away from every parapet end: whole
-- sections meeting the deck, a terminal at the far end of each, alternating section models.
function Bridges.guardrailPieces(
	spans: { Span },
	from: number,
	to: number,
	layout: Layout,
	guardrails: Roadside.GuardrailLayout
): { Roadside.Piece }
	local pieces = {}
	local function add(s: number, side: number, kind: Roadside.PieceKind, variant: number)
		if s >= from and s < to then
			table.insert(pieces, { s = s, side = side, kind = kind, variant = variant })
		end
	end
	local sections = math.floor(layout.approach / guardrails.section + 0.5)
	for _, span in spans do
		for _, side in { -1, 1 } do
			local first = span.from - sections * guardrails.section
			add(first, side, "Start", 1)
			for index = 0, sections - 1 do
				local variant = 1 + index % guardrails.variants
				add(first + index * guardrails.section, side, "Section", variant)
				add(span.to + index * guardrails.section, side, "Section", variant)
			end
			add(span.to + sections * guardrails.section, side, "End", 1)
		end
	end
	Roadside.sortPieces(pieces)
	return pieces
end

-- Where no verge furniture stands: each bridge, its approach guardrails and terminals, and a
-- clearance beyond.
function Bridges.keepOut(
	spans: { Span },
	layout: Layout,
	guardrails: Roadside.GuardrailLayout
): { Scatter.Zone }
	local reach = layout.approach + guardrails.terminal + layout.clearance
	local zones = table.create(#spans)
	for index, span in spans do
		zones[index] = { from = span.from - reach, to = span.to + reach }
	end
	return zones
end

return table.freeze(Bridges)
