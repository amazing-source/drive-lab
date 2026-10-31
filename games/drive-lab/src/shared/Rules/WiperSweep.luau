--!strict
--[[
	Where a wiper blade passes on the windscreen (Atmosphere/Windshield clears the drops there). The
	blade is the segment between its two ends, turning with its arm about the hinge; a point of the
	pane is swept between two turns of the arm when the blade, at some turn between them, lies over
	it. Worked in the plane square to the hinge's axis through its pivot, so a blade that does not
	point at the pivot, and an axis not quite square to the glass, are both handled exactly. Vectors
	are in the chassis's space (Rules/Hinge), metres.
]]
local Hinge = require("./Hinge")
local WindshieldDrops = require("./WindshieldDrops")

type Vector = Hinge.Vector
type Flat = { x: number, y: number }

export type Geometry = {
	pane: WindshieldDrops.Pane,
	-- The hinge, and the plane square to it: u toward the parked blade's outer end, v where a
	-- positive turn takes u.
	pivot: Vector,
	axis: Vector,
	u: Vector,
	v: Vector,
	-- The parked blade's ends in that plane.
	inner: Flat,
	outer: Flat,
	-- Radians from parked to the far end of the sweep.
	travel: number,
	-- Metres either side of the blade's edge that it still clears.
	reach: number,
}

local WiperSweep = {}

local function sub(a: Vector, b: Vector): Vector
	return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }
end

local function dot(a: Vector, b: Vector): number
	return a.x * b.x + a.y * b.y + a.z * b.z
end

local function scaled(a: Vector, k: number): Vector
	return { x = a.x * k, y = a.y * k, z = a.z * k }
end

local function cross(a: Vector, b: Vector): Vector
	return { x = a.y * b.z - a.z * b.y, y = a.z * b.x - a.x * b.z, z = a.x * b.y - a.y * b.x }
end

local function unit(a: Vector): Vector
	local length = math.sqrt(dot(a, a))
	assert(length > 1e-9, "the wiper needs a length and an axis")
	return scaled(a, 1 / length)
end

local function flat(g: Geometry, point: Vector): Flat
	local offset = sub(point, g.pivot)
	return { x = dot(offset, g.u), y = dot(offset, g.v) }
end

-- The geometry of a blade from `inner` to `outer` (parked), turning by up to `travel` radians
-- about `axis` through `pivot`, over `pane`.
function WiperSweep.geometry(
	pane: WindshieldDrops.Pane,
	pivot: Vector,
	axis: Vector,
	inner: Vector,
	outer: Vector,
	travel: number,
	reach: number
): Geometry
	local along = unit(axis)
	local offset = sub(outer, pivot)
	local u = unit(sub(offset, scaled(along, dot(offset, along))))
	local geometry: Geometry = {
		pane = pane,
		pivot = pivot,
		axis = along,
		u = u,
		v = cross(along, u),
		inner = { x = 0, y = 0 },
		outer = { x = 0, y = 0 },
		travel = travel,
		reach = reach,
	}
	geometry.inner = flat(geometry, inner)
	geometry.outer = flat(geometry, outer)
	return geometry
end

-- The angles (radians) of the parked blade's points at distance `radius` from the pivot: none, one
-- or two, where the blade's segment crosses that circle.
local function anglesAt(g: Geometry, radius: number): { number }
	local a, b = g.inner, g.outer
	local dx, dy = b.x - a.x, b.y - a.y
	local qa = dx * dx + dy * dy
	local qb = 2 * (a.x * dx + a.y * dy)
	local qc = a.x * a.x + a.y * a.y - radius * radius
	local found: { number } = {}
	local discriminant = qb * qb - 4 * qa * qc
	if qa < 1e-12 or discriminant < 0 then
		return found
	end
	local root = math.sqrt(discriminant)
	for _, t in { (-qb - root) / (2 * qa), (-qb + root) / (2 * qa) } do
		if t >= 0 and t <= 1 then
			table.insert(found, math.atan2(a.y + dy * t, a.x + dx * t))
		end
	end
	return found
end

-- Whether the blade passes over the pane's point (x, y) while the sweep goes from `fromShare` to
-- `toShare` (0 parked, 1 the far end, as Rules/Wiper.sweep), in either direction.
function WiperSweep.swept(g: Geometry, fromShare: number, toShare: number, x: number, y: number): boolean
	local low = g.travel * math.min(fromShare, toShare)
	local high = g.travel * math.max(fromShare, toShare)
	local point = flat(g, WindshieldDrops.point(g.pane, x, y))
	local radius = math.sqrt(point.x * point.x + point.y * point.y)
	if radius < 1e-9 then
		return false
	end
	local slack = g.reach / radius
	local angle = math.atan2(point.y, point.x)
	for _, blade in anglesAt(g, radius) do
		-- The turn that brings this point of the blade over the drop, in (-pi, pi].
		local turn = (angle - blade + math.pi) % (2 * math.pi) - math.pi
		if turn >= low - slack and turn <= high + slack then
			return true
		end
	end
	return false
end

-- Where the blade's point `share` of the way from its inner to its outer end sits on the pane at a
-- sweep of `sweepShare`, carried along the hinge's axis onto the pane as `swept` reads the pane:
-- pane (x, y), metres from its rectangle's left edge and its top.
function WiperSweep.bladeOnPane(g: Geometry, share: number, sweepShare: number): (number, number)
	local a, b = g.inner, g.outer
	local px, py = a.x + (b.x - a.x) * share, a.y + (b.y - a.y) * share
	local turn = g.travel * sweepShare
	local cosine, sine = math.cos(turn), math.sin(turn)
	local rx, ry = px * cosine - py * sine, px * sine + py * cosine
	local point = {
		x = g.pivot.x + g.u.x * rx + g.v.x * ry,
		y = g.pivot.y + g.u.y * rx + g.v.y * ry,
		z = g.pivot.z + g.u.z * rx + g.v.z * ry,
	}
	local pane = g.pane
	local along = -dot(sub(point, pane.centre), pane.normal) / dot(g.axis, pane.normal)
	local offset = sub({
		x = point.x + g.axis.x * along,
		y = point.y + g.axis.y * along,
		z = point.z + g.axis.z * along,
	}, pane.centre)
	return dot(offset, pane.right) + pane.width / 2, dot(offset, pane.down) + pane.height / 2
end

return table.freeze(WiperSweep)
