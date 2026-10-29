--!strict
--[[
	Where the roadside furniture and the road's surface marks go. Speed is felt through things
	close to the car streaming past, so the verges carry delineator posts and guardrails and
	gantries span the road; the asphalt carries patches, sealed cracks, skid marks, stains and
	drip lines. Everything sits on Rules/Scatter's seeded lattices, so a chunk gets the same
	furniture whichever way the road is cut, and the spacing is irregular: evenly spaced objects
	strobe at 60 frames a second.

	Guardrails run in stretches of whole sections inside one lattice slot each, a terminal past
	each end, so stretches on one side never overlap; delineators give way to them.
]]
local Scatter = require("./Scatter")

local Roadside = {}

export type GuardrailLayout = {
	-- Metres of road per slot on one side, and the share of slots left without a guardrail.
	spacing: number,
	skip: number,
	-- The stretch's length range in metres, before it is cut to whole sections.
	shortest: number,
	longest: number,
	-- No stretch begins before this arc length (metres).
	start: number,
	-- One section's length (metres), how many section models alternate, a terminal's length.
	section: number,
	variants: number,
	terminal: number,
}

export type Stretch = { from: number, to: number, side: number, slot: number }

export type PieceKind = "Start" | "Section" | "End"
export type Piece = { s: number, side: number, kind: PieceKind, variant: number }

export type MarkKind = "Patch" | "Crack" | "Skid" | "Stain" | "Drips"

export type MarkSpec = {
	kind: MarkKind,
	weight: number,
	length: { min: number, max: number },
	width: { min: number, max: number },
	-- Metres either way from the lane's centre.
	lateral: number,
	-- The largest turn off the road's line (radians), and the share laid across the road.
	yaw: number,
	transverse: number,
}

export type MarkLayout = {
	lattice: Scatter.Layout,
	-- Metres from the road's centre to a lane's centre.
	lane: number,
	kinds: { MarkSpec },
}

-- offset: metres to the right of the centreline; yaw: radians off the road's line; shade in
-- [0, 1) for each mark's own darkness.
export type Mark = {
	s: number,
	offset: number,
	kind: MarkKind,
	length: number,
	width: number,
	yaw: number,
	shade: number,
}

-- Each kind of thing draws from its own seed, so their lattices do not move together.
local DELINEATOR_SALT = 101
local GUARDRAIL_SALT = 211
local GANTRY_SALT = 307
local MARK_SALT = 401

local function lerp(range: { min: number, max: number }, share: number): number
	return range.min + (range.max - range.min) * share
end

local function stretchIn(slot: number, sideIndex: number, seed: number, layout: GuardrailLayout): Stretch?
	local salted = seed + GUARDRAIL_SALT
	if Scatter.hash(salted, slot, sideIndex * 8) < layout.skip then
		return nil
	end
	local room = layout.spacing - 2 * layout.terminal
	local wanted = layout.shortest
		+ (layout.longest - layout.shortest) * Scatter.hash(salted, slot, sideIndex * 8 + 1)
	local sections = math.max(1, math.floor(math.min(wanted, room) / layout.section))
	local length = sections * layout.section
	local from = slot * layout.spacing
		+ layout.terminal
		+ (room - length) * Scatter.hash(salted, slot, sideIndex * 8 + 2)
	if from - layout.terminal < layout.start then
		return nil
	end
	return { from = from, to = from + length, side = if sideIndex == 1 then -1 else 1, slot = slot }
end

-- Every guardrail stretch whose span, terminals included, overlaps [from, to).
function Roadside.guardrails(from: number, to: number, seed: number, layout: GuardrailLayout): { Stretch }
	local stretches = {}
	for sideIndex = 1, 2 do
		for slot = math.floor(from / layout.spacing) - 1, math.floor(to / layout.spacing) + 1 do
			local stretch = stretchIn(slot, sideIndex, seed, layout)
			if stretch and stretch.to + layout.terminal > from and stretch.from - layout.terminal < to then
				table.insert(stretches, stretch)
			end
		end
	end
	return stretches
end

-- The guardrail pieces a stretch of road [from, to) lays: each piece belongs to the stretch of
-- road holding its own arc length s (a section's start, a terminal's end of the beam).
function Roadside.guardrailPieces(from: number, to: number, seed: number, layout: GuardrailLayout): { Piece }
	local pieces = {}
	local function add(s: number, side: number, kind: PieceKind, variant: number)
		if s >= from and s < to then
			table.insert(pieces, { s = s, side = side, kind = kind, variant = variant })
		end
	end
	for _, stretch in Roadside.guardrails(from, to, seed, layout) do
		add(stretch.from, stretch.side, "Start", 1)
		local sections = math.floor((stretch.to - stretch.from) / layout.section + 0.5)
		for index = 0, sections - 1 do
			local channel = if stretch.side > 0 then 31 else 37
			local pick = Scatter.hash(seed + GUARDRAIL_SALT, stretch.slot * 64 + index, channel)
			add(
				stretch.from + index * layout.section,
				stretch.side,
				"Section",
				1 + math.floor(pick * layout.variants)
			)
		end
		add(stretch.to, stretch.side, "End", 1)
	end
	table.sort(pieces, function(a, b)
		if a.s ~= b.s then
			return a.s < b.s
		end
		return if a.kind ~= b.kind then a.kind < b.kind else a.side < b.side
	end)
	return pieces
end

-- Whether a guardrail stretch, its terminals and a clearance (metres) cover s on that side.
function Roadside.guarded(stretches: { Stretch }, s: number, side: number, reach: number): boolean
	for _, stretch in stretches do
		if stretch.side == side and s > stretch.from - reach and s < stretch.to + reach then
			return true
		end
	end
	return false
end

-- Delineator posts in [from, to): the lattice's spots, less those a guardrail stands at.
function Roadside.delineators(
	from: number,
	to: number,
	seed: number,
	posts: Scatter.Layout,
	guardrails: GuardrailLayout,
	clearance: number
): { Scatter.Spot }
	local reach = guardrails.terminal + clearance
	local stretches = Roadside.guardrails(from - reach, to + reach, seed, guardrails)
	local kept = {}
	for _, spot in Scatter.spots(from, to, seed + DELINEATOR_SALT, posts) do
		if not Roadside.guarded(stretches, spot.s, spot.side, reach) then
			table.insert(kept, spot)
		end
	end
	return kept
end

-- The barrier across the road's start: the fewest whole sections (metres long) that span `width`,
-- centred on the road. Each section's left end, in metres right of the road's centre, in order;
-- the line's own ends take the terminals.
function Roadside.roadEnd(width: number, section: number): { number }
	local count = math.ceil(width / section - 1e-9)
	local first = -count * section / 2
	local lefts = table.create(count)
	for index = 1, count do
		lefts[index] = first + (index - 1) * section
	end
	return lefts
end

-- Sign gantries in [from, to), by arc length: one lattice side only, as a gantry spans both.
function Roadside.gantries(from: number, to: number, seed: number, layout: Scatter.Layout): { number }
	local found = {}
	for _, spot in Scatter.spots(from, to, seed + GANTRY_SALT, layout) do
		if spot.side > 0 then
			table.insert(found, spot.s)
		end
	end
	return found
end

local function pickKind(kinds: { MarkSpec }, share: number): MarkSpec
	local total = 0
	for _, spec in kinds do
		total += spec.weight
	end
	local target = share * total
	for _, spec in kinds do
		target -= spec.weight
		if target < 0 then
			return spec
		end
	end
	return kinds[#kinds]
end

-- Surface marks centred in [from, to); a spot's side is its lane.
function Roadside.marks(from: number, to: number, seed: number, layout: MarkLayout): { Mark }
	local marks = {}
	local salted = seed + MARK_SALT
	for _, spot in Scatter.spots(from, to, salted, layout.lattice) do
		local function roll(channel: number): number
			return Scatter.hash(salted, spot.slot, (if spot.side > 0 then 16 else 32) + channel)
		end
		local spec = pickKind(layout.kinds, roll(0))
		local across = roll(1) < spec.transverse
		local turn = (roll(2) * 2 - 1) * spec.yaw
		local lateral = if across then 0 else (roll(3) * 2 - 1) * spec.lateral
		table.insert(marks, {
			s = spot.s,
			offset = spot.side * layout.lane + lateral,
			kind = spec.kind,
			length = lerp(spec.length, roll(4)),
			width = lerp(spec.width, roll(5)),
			yaw = if across then math.pi / 2 + turn else turn,
			shade = roll(6),
		})
	end
	return marks
end

return table.freeze(Roadside)
