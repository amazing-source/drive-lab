--!strict
--[[
	Fills a voxel grid from a shape described as a function: inside(x, y, z) at each voxel's
	centre, in real units, and the key to paint it with. Fine voxels (0.2 to 0.3 studs) sculpted
	from smooth signed-distance shapes read as precise curved bodies, and the greedy mesher
	keeps the part count down by merging every run of same-key voxels.

	Shapes are combined with the helpers below; each returns a signed distance (negative
	inside), so union, subtraction and rounding compose like ordinary arithmetic.
]]
export type Field = (x: number, y: number, z: number) -> number

-- Anything with VoxelGrid's set, so the module loads alone over HTTP as well as in a tree.
type Grid = { set: (self: any, x: number, y: number, z: number, key: string?) -> () }

local Sculpt = {}

-- A box centred at (cx, cy, cz) with half sizes (hx, hy, hz) and corners rounded by r.
function Sculpt.box(cx: number, cy: number, cz: number, hx: number, hy: number, hz: number, r: number): Field
	return function(x, y, z)
		local qx = math.abs(x - cx) - hx + r
		local qy = math.abs(y - cy) - hy + r
		local qz = math.abs(z - cz) - hz + r
		local outside = Vector3.new(math.max(qx, 0), math.max(qy, 0), math.max(qz, 0)).Magnitude
		return outside + math.min(math.max(qx, qy, qz), 0) - r
	end
end

-- A cylinder along x, centred at (cx, cy, cz), radius rad, half length h.
function Sculpt.cylinderX(cx: number, cy: number, cz: number, rad: number, h: number): Field
	return function(x, y, z)
		local radial = Vector2.new(y - cy, z - cz).Magnitude - rad
		local axial = math.abs(x - cx) - h
		local outside = Vector2.new(math.max(radial, 0), math.max(axial, 0)).Magnitude
		return outside + math.min(math.max(radial, axial), 0)
	end
end

function Sculpt.union(...: Field): Field
	local fields = { ... }
	return function(x, y, z)
		local best = math.huge
		for _, field in fields do
			best = math.min(best, field(x, y, z))
		end
		return best
	end
end

function Sculpt.subtract(base: Field, cut: Field): Field
	return function(x, y, z)
		return math.max(base(x, y, z), -cut(x, y, z))
	end
end

-- Union with a smooth blend of width k, for body panels that flow into each other.
function Sculpt.smoothUnion(a: Field, b: Field, k: number): Field
	return function(x, y, z)
		local da, db = a(x, y, z), b(x, y, z)
		local h = math.clamp(0.5 + 0.5 * (db - da) / k, 0, 1)
		return db + (da - db) * h - k * h * (1 - h)
	end
end

-- Paints every voxel inside `field` within the given bounds with `key`, at voxel size `step`.
function Sculpt.fill(grid: Grid, field: Field, key: string, step: number, min: Vector3, max: Vector3): number
	local filled = 0
	for i = math.floor(min.X / step), math.ceil(max.X / step) do
		for j = math.floor(min.Y / step), math.ceil(max.Y / step) do
			for k = math.floor(min.Z / step), math.ceil(max.Z / step) do
				if field((i + 0.5) * step, (j + 0.5) * step, (k + 0.5) * step) <= 0 then
					grid:set(i, j, k, key)
					filled += 1
				end
			end
		end
	end
	return filled
end

return Sculpt
