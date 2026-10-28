--!strict
--[[
	Where the rain is emitted round the camera. Streaks stay where they are emitted in the world
	and fall straight down with the wind's lean, so a moving camera or car runs into them. The
	rain is a few rings of falling streaks round a hole: round the camera on foot and in the
	chase view, round the car's box in the cockpit and hood views. The hole reaches along the
	motion as far as the camera, relative to the drifting streaks, travels in a streak's life: a
	streak emitted beyond it is gone before the camera arrives, so none crosses the lens or the
	cabin.

	Each ring is four blocks laid as a pinwheel round its hole, each taking one corner, so they
	tile the ring exactly. Every streak enters at the top of its block and lives exactly as long
	as it takes to fall to the ground, so the air in a block is evenly filled and no streak's
	centre ever goes under the road (where it would take the ground's darkness).

	Frame: X right, Z back (forward is -Z), any length unit as long as all share it.
]]
export type Rect = { x0: number, x1: number, z0: number, z1: number }

-- The heights a block spans: its bottom (where a streak's lower end meets the ground), its top,
-- the thickness of the inlet at the top that streaks enter through, and their life.
export type Column = { bottom: number, top: number, inlet: number, lifetime: number }

local RainRings = {}

local function finite(value: number): number
	return if value ~= value or value == math.huge or value == -math.huge then 0 else value
end

local function grow(rect: Rect, by: number): Rect
	return { x0 = rect.x0 - by, x1 = rect.x1 + by, z0 = rect.z0 - by, z1 = rect.z1 + by }
end

-- The smallest rect holding both.
function RainRings.union(a: Rect, b: Rect): Rect
	return {
		x0 = math.min(a.x0, b.x0),
		x1 = math.max(a.x1, b.x1),
		z0 = math.min(a.z0, b.z0),
		z1 = math.max(a.z1, b.z1),
	}
end

-- The hole round `base` (grown by `margin`) that no streak living `lifetime` may be emitted
-- into, for a camera moving at (vx, vz) relative to the streaks: base swept along that motion
-- for the streak's life. The swept shape is held by its bounding rect.
function RainRings.hole(base: Rect, margin: number, vx: number, vz: number, lifetime: number): Rect
	local life = math.max(finite(lifetime), 0)
	local reachX, reachZ = finite(vx) * life, finite(vz) * life
	local grown = grow(base, math.max(finite(margin), 0))
	return {
		x0 = grown.x0 + math.min(reachX, 0),
		x1 = grown.x1 + math.max(reachX, 0),
		z0 = grown.z0 + math.min(reachZ, 0),
		z1 = grown.z1 + math.max(reachZ, 0),
	}
end

-- The four blocks of the ring `depth` deep round a hole, `ahead` deeper still in front (-Z):
-- ahead, right, behind, left, each also taking one corner. The third is behind the hole (+Z).
function RainRings.blocks(hole: Rect, depth: number, ahead: number): { Rect }
	local d = math.max(finite(depth), 0)
	local front = d + math.max(finite(ahead), 0)
	local h = hole
	return {
		{ x0 = h.x0 - d, x1 = h.x1, z0 = h.z0 - front, z1 = h.z0 },
		{ x0 = h.x1, x1 = h.x1 + d, z0 = h.z0 - front, z1 = h.z1 },
		{ x0 = h.x0, x1 = h.x1 + d, z0 = h.z1, z1 = h.z1 + d },
		{ x0 = h.x0 - d, x1 = h.x0, z0 = h.z0, z1 = h.z1 + d },
	}
end

-- The rect a ring's blocks surround.
function RainRings.outer(hole: Rect, depth: number, ahead: number): Rect
	local grown = grow(hole, math.max(finite(depth), 0))
	grown.z0 -= math.max(finite(ahead), 0)
	return grown
end
-- A ring's column over the ground: streaks `halfLength` from centre to end, falling at `fall`,
-- in a column `height` tall, entering through an inlet `inlet` thick. A streak born at the
-- inlet's lowest point lives until its lower end touches the ground; one born higher dies that
-- much above it.
function RainRings.column(
	ground: number,
	height: number,
	halfLength: number,
	inlet: number,
	fall: number
): Column
	local bottom = finite(ground) + math.max(finite(halfLength), 0)
	local top = math.max(finite(ground) + finite(height), bottom)
	local thickness = math.clamp(finite(inlet), 0, top - bottom)
	local speed = math.max(finite(fall), 1e-6)
	return { bottom = bottom, top = top, inlet = thickness, lifetime = (top - bottom - thickness) / speed }
end

-- The share of the rate a block behind the camera keeps in the car views: the views look ahead,
-- and the faster the car the less of what falls behind is ever seen.
function RainRings.behind(forwardSpeed: number, fadeSpeed: number): number
	if fadeSpeed <= 0 then
		return 1
	end
	return math.clamp(1 - math.max(finite(forwardSpeed), 0) / fadeSpeed, 0, 1)
end

function RainRings.area(rect: Rect): number
	return math.max(rect.x1 - rect.x0, 0) * math.max(rect.z1 - rect.z0, 0)
end

return table.freeze(RainRings)
