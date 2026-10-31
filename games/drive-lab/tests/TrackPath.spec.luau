--!strict
local T = require("../../../tools/test/T")
local Track = require("../src/shared/Config/Track")
local TrackPath = require("../src/shared/Rules/TrackPath")

local describe, it, expect = T.describe, T.it, T.expect

local START: TrackPath.Point = { x = 0, z = 0, dirX = 0, dirZ = -1, s = 0 }
local LENGTH = 30000
local COUNT = LENGTH // Track.STEP

-- The bending road, whatever the config's default.
local function road(seed: number): { TrackPath.Point }
	return TrackPath.generate(START, COUNT, Track.STEP, seed, true)
end

describe("TrackPath", function()
	it("lays the same road for the same seed and a different one otherwise", function()
		local a, b, c = road(1), road(1), road(2)
		expect(a[COUNT].x).toBe(b[COUNT].x)
		expect(a[COUNT].z).toBe(b[COUNT].z)
		expect(math.abs(a[COUNT].x - c[COUNT].x) > 1).toBe(true)
	end)

	it("starts dead straight along the start direction", function()
		for _, point in road(Track.SEED) do
			if point.s > Track.START_STRAIGHT then
				break
			end
			expect(point.x).toBeNear(0, 1e-9)
			expect(point.dirZ).toBeNear(-1, 1e-9)
		end
	end)

	it("never bends tighter than the minimum radius", function()
		for s = 0, LENGTH, 3 do
			expect(math.abs(TrackPath.curvature(s, Track.SEED, true)) <= 1 / Track.MIN_RADIUS + 1e-12).toBe(
				true
			)
		end
	end)

	it("mixes straights and real bends", function()
		local straight, tight, samples = 0, 0, 0
		for s = Track.START_STRAIGHT + Track.RAMP, LENGTH, 5 do
			local k = math.abs(TrackPath.curvature(s, Track.SEED, true))
			samples += 1
			if k < 1e-9 then
				straight += 1
			elseif k > 0.5 / Track.MIN_RADIUS then
				tight += 1
			end
		end
		expect(straight / samples > 0.2 and straight / samples < 0.8).toBe(true)
		expect(tight / samples > 0.05).toBe(true)
	end)

	it("bends right for positive curvature", function()
		-- Find a stretch of positive curvature and step across it, heading -Z (right is +X).
		local s = Track.START_STRAIGHT
		while TrackPath.curvature(s + 0.5, Track.SEED, true) <= 0 do
			s += 1
		end
		local point = TrackPath.advance({ x = 0, z = 0, dirX = 0, dirZ = -1, s = s }, 1, Track.SEED, true)
		expect(point.dirX > 0).toBe(true)
	end)

	it("is one straight line when bends are off", function()
		local straight = TrackPath.generate(START, COUNT, Track.STEP, Track.SEED, false)
		local last = straight[COUNT]
		expect(last.x).toBeNear(0, 1e-6)
		expect(last.z).toBeNear(-COUNT * Track.STEP, 1e-6)
	end)

	it("moves one step per point and keeps the direction a unit vector", function()
		local previous = START
		for _, point in road(Track.SEED) do
			local step = math.sqrt((point.x - previous.x) ^ 2 + (point.z - previous.z) ^ 2)
			-- A chord of a 6 m arc on the tightest bend is 2 mm shorter than the arc.
			expect(step).toBeNear(Track.STEP, 5e-3)
			expect(point.dirX ^ 2 + point.dirZ ^ 2).toBeNear(1, 1e-9)
			previous = point
		end
	end)
end)

describe("TrackPath: a step's block", function()
	it("measures the turn between two points, whichever way it bends", function()
		local a: TrackPath.Point = { x = 0, z = 0, dirX = 0, dirZ = -1, s = 0 }
		local right: TrackPath.Point = { x = 0, z = 0, dirX = math.sin(0.1), dirZ = -math.cos(0.1), s = 6 }
		local left: TrackPath.Point = { x = 0, z = 0, dirX = -math.sin(0.1), dirZ = -math.cos(0.1), s = 6 }
		expect(TrackPath.turn(a, right)).toBeNear(0.1, 1e-12)
		expect(TrackPath.turn(a, left)).toBeNear(0.1, 1e-12)
		expect(TrackPath.turn(a, a)).toBe(0)
	end)

	it("reaches past the step by the bend's opening at its outer edge and a metre", function()
		expect(TrackPath.blockLength(6, 11, 0)).toBe(7)
		expect(TrackPath.blockLength(6, 11, 0.05)).toBeNear(6 + 11 * 0.05 + 1, 1e-12)
	end)

	it("bends only on the Bends layout when not told", function()
		local bending = 0
		for s = Track.START_STRAIGHT, Track.START_STRAIGHT + 3000, 10 do
			if TrackPath.curvature(s, Track.SEED) ~= 0 then
				bending += 1
			end
		end
		expect(bending > 0).toBe(Track.LAYOUT == "Bends")
	end)
end)

describe("TrackPath: the road's start among several car spawns", function()
	it("starts at the first spawn by name, whatever order they are found in", function()
		expect(TrackPath.startIndex({ "Workspace.SVJ", "Workspace.ZCar" })).toBe(1)
		expect(TrackPath.startIndex({ "Workspace.ZCar", "Workspace.SVJ" })).toBe(2)
		expect(TrackPath.startIndex({ "Workspace.SVJ" })).toBe(1)
		expect(TrackPath.startIndex({})).toBe(nil)
	end)
end)
