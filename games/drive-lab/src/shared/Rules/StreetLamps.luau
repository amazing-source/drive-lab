--!strict
--[[
	Where the street lamps stand along the road and when they are lit. Lamps are scattered on
	Rules/Scatter's lattice: the same road always gets the same lamps, whichever chunk lays them.
]]
local Scatter = require("./Scatter")

local StreetLamps = {}

export type Layout = Scatter.Layout
export type Spot = Scatter.Spot

-- Every lamp spot with arc length in [from, to), metres; side is -1 (left) or 1 (right).
function StreetLamps.spots(from: number, to: number, seed: number, layout: Layout): { Spot }
	return Scatter.spots(from, to, seed, layout)
end

-- Whether lamps are lit at this time of day (hours, 0-24): from dusk until dawn.
function StreetLamps.isNight(clockTime: number, dusk: number, dawn: number): boolean
	return clockTime >= dusk or clockTime < dawn
end

-- A lamp's own delay, seconds in [0, spread), from where it stands: they do not all switch at
-- once, as real ones on separate photocells do not.
function StreetLamps.delay(x: number, z: number, spread: number): number
	return Scatter.hash(math.floor(x), math.floor(z), 7) * spread
end

return table.freeze(StreetLamps)
