--!strict
--[[
	Seeded scatter along the road. Things stand on a lattice of slots along the road's arc
	length, the two sides staggered by half a slot; each slot is shifted by a seeded jitter and
	some are left empty, so a row looks scattered but the same road always gets the same things,
	whichever chunk lays them. Every choice comes from a hash of (seed, slot, channel), never
	from a running random stream, which is what makes a chunk's answer independent of its
	neighbours'.
]]
local Scatter = {}

export type Layout = {
	-- Metres between slots on one side, the jitter as a share of it, the share of slots empty.
	spacing: number,
	jitter: number,
	skip: number,
	-- Nothing before this arc length (metres): the start is kept clear for the spawn.
	start: number,
}

-- side is -1 (left) or 1 (right); slot is the lattice index, for further seeded choices.
export type Spot = { s: number, side: number, slot: number }

-- A value in [0, 1) from the seed, a slot and a channel: integer mixing, the same everywhere.
function Scatter.hash(seed: number, slot: number, channel: number): number
	local h = bit32.bxor(seed * 374761393, slot * 668265263, channel * 2246822519)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = (h * 1274126177) % 4294967296
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h / 4294967296
end

-- Every spot with arc length in [from, to), metres, in order of arc length.
function Scatter.spots(from: number, to: number, seed: number, layout: Layout): { Spot }
	local spots = {}
	for sideIndex, side in { -1, 1 } do
		local phase = if side > 0 then 0.5 else 0
		local first = math.floor(from / layout.spacing - phase) - 1
		local last = math.ceil(to / layout.spacing - phase) + 1
		for slot = first, last do
			local jitter = (Scatter.hash(seed, slot, sideIndex * 2) * 2 - 1) * layout.jitter
			local s = (slot + phase + jitter) * layout.spacing
			local empty = Scatter.hash(seed, slot, sideIndex * 2 + 1) < layout.skip
			if not empty and s >= from and s < to and s >= layout.start then
				table.insert(spots, { s = s, side = side, slot = slot })
			end
		end
	end
	table.sort(spots, function(a, b)
		return a.s < b.s
	end)
	return spots
end

return table.freeze(Scatter)
