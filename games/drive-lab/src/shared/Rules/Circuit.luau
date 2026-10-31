--!strict
--[[
	The test circuit's centre line: straights and arcs, in metres on the horizontal plane, in
	Rules/TrackPath's frame and point format so the track lays it like any other road. Points are
	exact on each piece rather than stepped, so the lap closes on itself. Two straights are sized
	by the build to close the lap, whatever the other pieces are.
]]
local TrackPath = require("./TrackPath")

export type Straight = { kind: "Straight", length: number }
-- turn: degrees, positive to the right.
export type Arc = { kind: "Arc", radius: number, turn: number }
-- A straight the build sizes to close the lap, at least `minimum` metres long.
export type Closing = { kind: "Closing", minimum: number }
export type Segment = Straight | Arc | Closing

export type PieceKind = "Straight" | "Arc"
-- from: arc length at the piece's start; curvature in 1/m, positive bends right.
export type Piece = {
	kind: PieceKind,
	from: number,
	length: number,
	start: TrackPath.Point,
	curvature: number,
}

export type Course = { start: TrackPath.Point, pieces: { Piece }, length: number }

-- Metres along the start direction and to its right, from the start point.
export type Bounds = { alongMin: number, alongMax: number, acrossMin: number, acrossMax: number }

-- A stretch of one axis, metres.
export type Extent = { from: number, to: number }

-- Where the road crosses a line parallel to the start direction: arc length, the piece's index,
-- and the sine of the crossing angle (1 square across).
export type Crossing = { s: number, piece: number, sine: number }

local FULL_TURN = 360
local BISECTIONS = 48

local Circuit = {}

local function turned(dirX: number, dirZ: number, angle: number): (number, number)
	local c, s = math.cos(angle), math.sin(angle)
	return dirX * c - dirZ * s, dirX * s + dirZ * c
end

local function along(piece: Piece, u: number): TrackPath.Point
	local start = piece.start
	local k = piece.curvature
	if k == 0 then
		return {
			x = start.x + start.dirX * u,
			z = start.z + start.dirZ * u,
			dirX = start.dirX,
			dirZ = start.dirZ,
			s = piece.from + u,
		}
	end
	local angle = k * u
	local sine, versine = math.sin(angle), 1 - math.cos(angle)
	local dirX, dirZ = turned(start.dirX, start.dirZ, angle)
	return {
		x = start.x + (start.dirX * sine - start.dirZ * versine) / k,
		z = start.z + (start.dirX * versine + start.dirZ * sine) / k,
		dirX = dirX,
		dirZ = dirZ,
		s = piece.from + u,
	}
end

local function pieceFor(segment: Segment, length: number?, start: TrackPath.Point, from: number): Piece
	if segment.kind == "Arc" then
		assert(segment.radius > 0, "an arc's radius must be positive")
		local sign = if segment.turn < 0 then -1 else 1
		return {
			kind = "Arc",
			from = from,
			length = segment.radius * math.rad(math.abs(segment.turn)),
			start = start,
			curvature = sign / segment.radius,
		}
	end
	local size = if segment.kind == "Straight" then segment.length else length
	assert(size ~= nil and size > 0, "a straight's length must be positive")
	return { kind = "Straight", from = from, length = size, start = start, curvature = 0 }
end

-- The two closing straights' lengths, by segment index: what closes the lap from `start`.
local function closingLengths(segments: { Segment }, start: TrackPath.Point): { [number]: number }
	local reachX, reachZ, total = 0, 0, 0
	local point: TrackPath.Point = { x = 0, z = 0, dirX = start.dirX, dirZ = start.dirZ, s = 0 }
	local closing: { { index: number, dirX: number, dirZ: number, minimum: number } } = {}
	for index, segment in segments do
		if segment.kind == "Closing" then
			table.insert(
				closing,
				{ index = index, dirX = point.dirX, dirZ = point.dirZ, minimum = segment.minimum }
			)
		else
			local piece =
				pieceFor(segment, nil, { x = 0, z = 0, dirX = point.dirX, dirZ = point.dirZ, s = 0 }, 0)
			point = along(piece, piece.length)
			reachX += point.x
			reachZ += point.z
			if segment.kind == "Arc" then
				total += segment.turn
			end
		end
	end
	assert(#closing == 2, "a circuit needs exactly two closing straights")
	assert(
		math.abs(math.abs(total) - FULL_TURN) < 1e-6,
		`a circuit turns one full circle; this one turns {total} degrees`
	)
	local a, b = closing[1], closing[2]
	local determinant = a.dirX * b.dirZ - a.dirZ * b.dirX
	assert(math.abs(determinant) > 1e-6, "the two closing straights must not be parallel")
	local first = (-reachX * b.dirZ + reachZ * b.dirX) / determinant
	local second = (-a.dirX * reachZ + reachX * a.dirZ) / determinant
	assert(
		first >= a.minimum and second >= b.minimum,
		`the closing straights come out at {first} and {second} m, under their minimums`
	)
	return { [a.index] = first, [b.index] = second }
end

-- Lays the segments end to end from `start` (its s ignored: the lap starts at 0).
function Circuit.build(segments: { Segment }, start: TrackPath.Point): Course
	local lengths = closingLengths(segments, start)
	local pieces = table.create(#segments)
	local point: TrackPath.Point = { x = start.x, z = start.z, dirX = start.dirX, dirZ = start.dirZ, s = 0 }
	for index, segment in segments do
		local piece = pieceFor(segment, lengths[index], point, point.s)
		pieces[index] = piece
		point = along(piece, piece.length)
	end
	return { start = pieces[1].start, pieces = pieces, length = point.s }
end

-- The piece holding arc length s, wrapped into the lap.
function Circuit.pieceAt(course: Course, s: number): (Piece, number)
	local wrapped = if s < 0 or s > course.length then s % course.length else s
	for index, piece in course.pieces do
		if wrapped <= piece.from + piece.length then
			return piece, index
		end
	end
	return course.pieces[#course.pieces], #course.pieces
end

-- The point at arc length s, wrapped into the lap; s from 0 to the lap's length is kept as given.
function Circuit.pointAt(course: Course, s: number): TrackPath.Point
	local wrapped = if s < 0 or s > course.length then s % course.length else s
	local piece = Circuit.pieceAt(course, wrapped)
	return along(piece, math.min(wrapped - piece.from, piece.length))
end

-- Points every `step` metres after `from` and one at `to`, the last step between a quarter and a
-- step and a quarter long.
function Circuit.points(course: Course, from: number, to: number, step: number): { TrackPath.Point }
	local points = {}
	local s = from + step
	while s < to - step / 4 do
		table.insert(points, Circuit.pointAt(course, s))
		s += step
	end
	table.insert(points, Circuit.pointAt(course, to))
	return points
end

-- A point's place in the start's frame: metres along the start direction and to its right.
function Circuit.placeOf(course: Course, x: number, z: number): (number, number)
	local start = course.start
	local dx, dz = x - start.x, z - start.z
	return dx * start.dirX + dz * start.dirZ, dz * start.dirX - dx * start.dirZ
end

-- The box in the start's frame holding the centre line every `step` metres, `margin` wider all
-- round.
function Circuit.bounds(course: Course, margin: number, step: number): Bounds
	local bounds =
		{ alongMin = math.huge, alongMax = -math.huge, acrossMin = math.huge, acrossMax = -math.huge }
	local s = 0
	while true do
		local point = Circuit.pointAt(course, math.min(s, course.length))
		local alongStart, across = Circuit.placeOf(course, point.x, point.z)
		bounds.alongMin = math.min(bounds.alongMin, alongStart - margin)
		bounds.alongMax = math.max(bounds.alongMax, alongStart + margin)
		bounds.acrossMin = math.min(bounds.acrossMin, across - margin)
		bounds.acrossMax = math.max(bounds.acrossMax, across + margin)
		if s >= course.length then
			return bounds
		end
		s += step
	end
end

-- [from, to] cut into tiles about `size` long, each reaching `overlap` into its neighbours but
-- never past the ends: terrain only part-fills the voxels at a fill's edges, so tiles that merely
-- met would leave a groove along every seam.
function Circuit.tiles(from: number, to: number, size: number, overlap: number): { Extent }
	local count = math.max(1, math.ceil((to - from) / size - 1e-9))
	local length = (to - from) / count
	local tiles = table.create(count)
	for index = 1, count do
		local start = from + (index - 1) * length
		tiles[index] = {
			from = math.max(from, start - overlap),
			to = math.min(to, start + length + overlap),
		}
	end
	return tiles
end

-- Every place the centre line crosses the line `offset` metres right of the start and parallel
-- to its direction, found on a metre's sampling and refined by bisection.
function Circuit.crossings(course: Course, offset: number): { Crossing }
	local function side(piece: Piece, u: number): number
		local point = along(piece, u)
		local _, across = Circuit.placeOf(course, point.x, point.z)
		return across - offset
	end
	local found = {}
	for index, piece in course.pieces do
		local samples = math.max(1, math.ceil(piece.length))
		local previous = side(piece, 0)
		for sample = 1, samples do
			local u0, u1 = (sample - 1) / samples * piece.length, sample / samples * piece.length
			local current = side(piece, u1)
			if (previous < 0) ~= (current < 0) then
				for _ = 1, BISECTIONS do
					local middle = (u0 + u1) / 2
					if (side(piece, middle) < 0) == (previous < 0) then
						u0 = middle
					else
						u1 = middle
					end
				end
				local point = along(piece, (u0 + u1) / 2)
				local sine = math.abs(point.dirX * course.start.dirZ - point.dirZ * course.start.dirX)
				table.insert(found, { s = point.s, piece = index, sine = sine })
			end
			previous = current
		end
	end
	return found
end

return table.freeze(Circuit)
