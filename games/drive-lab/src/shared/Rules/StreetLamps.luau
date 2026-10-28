--!strict
--[[
	Where the street lamps stand along the road and when they are lit. Lamps sit on a lattice of
	slots along the road's arc length, the two sides staggered by half a slot; each slot is
	shifted by a seeded jitter and some are left empty, so the row looks scattered but the same
	road always gets the same lamps, whichever chunk lays them.
]]
local StreetLamps = {}

export type Layout = {
	-- Metres between slots on one side, the jitter as a share of it, the share of slots empty.
	spacing: number,
	jitter: number,
	skip: number,
	-- No lamps before this arc length (metres): the start is kept clear for the spawn.
	start: number,
}

export type Spot = { s: number, side: number }

-- A value in [0, 1) from the seed, a slot and a channel: integer mixing, the same everywhere.
local function hash(seed: number, slot: number, channel: number): number
	local h = bit32.bxor(seed * 374761393, slot * 668265263, channel * 2246822519)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = (h * 1274126177) % 4294967296
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h / 4294967296
end

-- Every lamp spot with arc length in [from, to), metres; side is -1 (left) or 1 (right).
function StreetLamps.spots(from: number, to: number, seed: number, layout: Layout): { Spot }
	local spots = {}
	for sideIndex, side in { -1, 1 } do
		local phase = if side > 0 then 0.5 else 0
		local first = math.floor(from / layout.spacing - phase) - 1
		local last = math.ceil(to / layout.spacing - phase) + 1
		for slot = first, last do
			local jitter = (hash(seed, slot, sideIndex * 2) * 2 - 1) * layout.jitter
			local s = (slot + phase + jitter) * layout.spacing
			local empty = hash(seed, slot, sideIndex * 2 + 1) < layout.skip
			if not empty and s >= from and s < to and s >= layout.start then
				table.insert(spots, { s = s, side = side })
			end
		end
	end
	table.sort(spots, function(a, b)
		return a.s < b.s
	end)
	return spots
end

-- Whether lamps are lit at this time of day (hours, 0-24): from dusk until dawn.
function StreetLamps.isNight(clockTime: number, dusk: number, dawn: number): boolean
	return clockTime >= dusk or clockTime < dawn
end

-- A lamp's own delay, seconds in [0, spread), from where it stands: they do not all switch at
-- once, as real ones on separate photocells do not.
function StreetLamps.delay(x: number, z: number, spread: number): number
	return hash(math.floor(x), math.floor(z), 7) * spread
end

return table.freeze(StreetLamps)
