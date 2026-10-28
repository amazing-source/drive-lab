--!strict
--[[
	The endless road's centre line, in metres on the horizontal plane. The bend at each
	distance comes from smooth seeded noise, so the same seed always lays the same road and a
	piece can be rebuilt from its distance alone. A dead zone in the noise leaves stretches
	dead straight; elsewhere the bend never passes 1 / MIN_RADIUS.
]]
local Track = require("../Config/Track")

export type Point = {
	x: number,
	z: number,
	-- Unit direction of travel.
	dirX: number,
	dirZ: number,
	-- Distance along the road from its start.
	s: number,
}

local TrackPath = {}

-- A lattice value in [-1, 1]: three xorshift rounds over the index and seed, integer-only so
-- it is the same on every machine.
local function lattice(index: number, seed: number): number
	local x = (index * 2654435 + seed * 40503 + 1) % 4294967296
	for _ = 1, 3 do
		x = bit32.bxor(x, bit32.lshift(x, 13))
		x = bit32.bxor(x, bit32.rshift(x, 17))
		x = bit32.bxor(x, bit32.lshift(x, 5))
	end
	return x / 4294967295 * 2 - 1
end

local function smoothNoise(t: number, seed: number): number
	local i = math.floor(t)
	local f = t - i
	local w = f * f * (3 - 2 * f)
	return lattice(i, seed) * (1 - w) + lattice(i + 1, seed) * w
end

local function noise(t: number, seed: number): number
	return 0.7 * smoothNoise(t, seed) + 0.3 * smoothNoise(t * 2.3 + 17, seed + 1)
end

-- Curvature (1/m, positive bends right) at distance `s` along the road. `bends` defaults to
-- Track.BENDS; without bends the road is one straight line.
function TrackPath.curvature(s: number, seed: number, bends: boolean?): number
	local into = s - Track.START_STRAIGHT
	if into <= 0 or not (if bends == nil then Track.BENDS else bends) then
		return 0
	end
	local n = noise(into / Track.WAVELENGTH, seed)
	local magnitude = math.max(0, math.abs(n) - Track.STRAIGHT_SHARE) / (1 - Track.STRAIGHT_SHARE)
	local ramp = math.min(1, into / Track.RAMP)
	local bend = math.clamp(magnitude * 1.6, 0, 1)
	return (if n < 0 then -1 else 1) * bend * ramp / Track.MIN_RADIUS
end

-- The next point `ds` metres on, turning by the curvature at the middle of the step.
function TrackPath.advance(point: Point, ds: number, seed: number, bends: boolean?): Point
	local angle = TrackPath.curvature(point.s + ds / 2, seed, bends) * ds
	-- Positive curvature bends right. Right of a direction (x, z) is (-z, x), which is where
	-- this rotation by +angle moves it.
	local c, sn = math.cos(angle), math.sin(angle)
	local dirX = point.dirX * c - point.dirZ * sn
	local dirZ = point.dirX * sn + point.dirZ * c
	return {
		x = point.x + (point.dirX + dirX) / 2 * ds,
		z = point.z + (point.dirZ + dirZ) / 2 * ds,
		dirX = dirX,
		dirZ = dirZ,
		s = point.s + ds,
	}
end

function TrackPath.generate(start: Point, count: number, ds: number, seed: number, bends: boolean?): { Point }
	local points = table.create(count)
	local point = start
	for i = 1, count do
		point = TrackPath.advance(point, ds, seed, bends)
		points[i] = point
	end
	return points
end

return table.freeze(TrackPath)
