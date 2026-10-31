--!strict
local Circuit = require("../src/shared/Rules/Circuit")
local Config = require("../src/shared/Config/Circuit")
local T = require("../../../tools/test/T")
local Track = require("../src/shared/Config/Track")
local TrackPath = require("../src/shared/Rules/TrackPath")
local Units = require("../src/shared/Units")

local describe, it, expect = T.describe, T.it, T.expect

-- A terrain voxel is 4 studs.
local VOXEL = Units.studsToMetres(4)

local NORTH: TrackPath.Point = { x = 0, z = 0, dirX = 0, dirZ = -1, s = 0 }
local SLANTED: TrackPath.Point = { x = 40, z = -25, dirX = 0.6, dirZ = 0.8, s = 0 }

local function course(start: TrackPath.Point?): Circuit.Course
	return Circuit.build(Config.SEGMENTS, start or NORTH)
end

local function withTurn(index: number, turn: number): { Circuit.Segment }
	local segments = table.clone(Config.SEGMENTS)
	local arc = segments[index]
	assert(arc.kind == "Arc", "not an arc")
	segments[index] = { kind = "Arc", radius = arc.radius, turn = turn }
	return segments
end

describe("Circuit", function()
	it("closes on itself, wherever it starts and whichever way it faces", function()
		for _, start in { NORTH, SLANTED } do
			local lap = course(start)
			local finish = Circuit.pointAt(lap, lap.length)
			expect(math.sqrt((finish.x - start.x) ^ 2 + (finish.z - start.z) ^ 2) < 0.01).toBe(true)
			expect(finish.dirX).toBeNear(start.dirX, 1e-9)
			expect(finish.dirZ).toBeNear(start.dirZ, 1e-9)
			expect(lap.length > 2500 and lap.length < 3200).toBe(true)
		end
	end)

	it("turns one full circle, and refuses a layout that does not", function()
		local total = 0
		for _, segment in Config.SEGMENTS do
			if segment.kind == "Arc" then
				total += segment.turn
			end
		end
		expect(math.abs(total)).toBeNear(360, 1e-9)
		expect(function()
			Circuit.build(withTurn(2, 170), NORTH)
		end).toThrow()
	end)

	it("sizes both closing straights at or above their minimums", function()
		local lap = course()
		local closing = 0
		for index, segment in Config.SEGMENTS do
			if segment.kind == "Closing" then
				closing += 1
				expect(lap.pieces[index].kind).toBe("Straight")
				expect(lap.pieces[index].length >= segment.minimum).toBe(true)
			end
		end
		expect(closing).toBe(2)
	end)

	it("keeps every radius in bounds, with corners tighter than the endless road's and a fast one", function()
		local tight, widest = 0, 0
		for _, segment in Config.SEGMENTS do
			if segment.kind == "Arc" then
				expect(segment.radius >= Config.RADII.min and segment.radius <= Config.RADII.max).toBe(true)
				if segment.radius < Track.MIN_RADIUS then
					tight += 1
				end
				widest = math.max(widest, segment.radius)
			end
		end
		expect(tight >= 3).toBe(true)
		expect(widest >= 200).toBe(true)
	end)

	it("lays points a step apart on the exact arcs, the last one at the lap's end", function()
		local lap = course()
		local points = Circuit.points(lap, 0, lap.length, Track.STEP)
		local previous = Circuit.pointAt(lap, 0)
		for index, point in points do
			local length = point.s - previous.s
			if index < #points then
				expect(length).toBeNear(Track.STEP, 1e-9)
			else
				expect(length >= Track.STEP / 4 and length <= Track.STEP * 1.25).toBe(true)
			end
			local piece = Circuit.pieceAt(lap, (previous.s + point.s) / 2)
			local within = previous.s >= piece.from - 1e-9 and point.s <= piece.from + piece.length + 1e-9
			if within then
				expect(TrackPath.turn(previous, point)).toBeNear(math.abs(piece.curvature) * length, 1e-9)
				local chord = math.sqrt((point.x - previous.x) ^ 2 + (point.z - previous.z) ^ 2)
				local angle = math.abs(piece.curvature) * length
				local expected = if angle > 0
					then 2 * math.sin(angle / 2) / math.abs(piece.curvature)
					else length
				expect(chord).toBeNear(expected, 1e-9)
			end
			expect(point.dirX ^ 2 + point.dirZ ^ 2).toBeNear(1, 1e-9)
			previous = point
		end
		expect(previous.s).toBe(lap.length)
	end)

	it("never brings two parts of the road near each other", function()
		local lap = course()
		local samples = Circuit.points(lap, 0, lap.length, 3)
		local closest = math.huge
		for i = 1, #samples do
			for j = i + 1, #samples do
				local apart = math.abs(samples[i].s - samples[j].s)
				if math.min(apart, lap.length - apart) > Config.NEIGHBOURS then
					local a, b = samples[i], samples[j]
					closest = math.min(closest, math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2))
				end
			end
		end
		expect(closest >= Config.CLEARANCE).toBe(true)
	end)

	it("holds the whole lap inside the field, its margin all round", function()
		for _, start in { NORTH, SLANTED } do
			local lap = course(start)
			local bounds = Circuit.bounds(lap, Config.FIELD_MARGIN, Track.STEP)
			for _, point in Circuit.points(lap, 0, lap.length, 1) do
				local along, across = Circuit.placeOf(lap, point.x, point.z)
				expect(along - bounds.alongMin >= Config.FIELD_MARGIN - 1).toBe(true)
				expect(bounds.alongMax - along >= Config.FIELD_MARGIN - 1).toBe(true)
				expect(across - bounds.acrossMin >= Config.FIELD_MARGIN - 1).toBe(true)
				expect(bounds.acrossMax - across >= Config.FIELD_MARGIN - 1).toBe(true)
			end
		end
	end)

	it("finds where the road crosses a line, and how square across", function()
		local lap = course()
		local crossings = Circuit.crossings(lap, Config.RIVER.offset)
		expect(#crossings).toBe(2)
		for _, crossing in crossings do
			local point = Circuit.pointAt(lap, crossing.s)
			local _, across = Circuit.placeOf(lap, point.x, point.z)
			expect(across).toBeNear(Config.RIVER.offset, 1e-6)
			expect(crossing.sine).toBeNear(1, 1e-9)
		end
	end)
end)

describe("Circuit tiles", function()
	it("covers the field in tiles that overlap by more than a voxel and stay inside it", function()
		expect(Config.TILE_OVERLAP > VOXEL).toBe(true)
		local lap = Circuit.build(Config.SEGMENTS, NORTH)
		local bounds = Circuit.bounds(lap, Config.FIELD_MARGIN, Track.STEP)
		for _, axis in
			{ { bounds.alongMin, bounds.alongMax }, { bounds.acrossMin, bounds.acrossMax }, { 0, 150 } }
		do
			local from, to = axis[1], axis[2]
			local tiles = Circuit.tiles(from, to, Config.FIELD_TILE, Config.TILE_OVERLAP)
			expect(tiles[1].from).toBe(from)
			expect(tiles[#tiles].to).toBe(to)
			for index, tile in tiles do
				expect(tile.from >= from and tile.to <= to and tile.to > tile.from).toBe(true)
				expect(tile.to - tile.from <= Config.FIELD_TILE + 2 * Config.TILE_OVERLAP + 1e-9).toBe(true)
				if index > 1 then
					expect(tiles[index - 1].to - tile.from >= Config.TILE_OVERLAP * 2 - 1e-9).toBe(true)
				end
			end
		end
	end)
end)
