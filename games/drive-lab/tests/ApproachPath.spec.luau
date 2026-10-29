--!strict
local ApproachPath = require("../src/shared/Rules/ApproachPath")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

-- The SVJ's collision box grown by half a body and a margin (studs, its own frame), and the
-- approach point beside the driver's door.
local HX, HZ = 6.6, 13.7
local GOAL: ApproachPath.Point = { x = -8, z = -1 }

local function crossesAny(start: ApproachPath.Point, path: { ApproachPath.Point }): boolean
	local from = start
	for _, point in path do
		if ApproachPath.crosses(from, point, HX, HZ) then
			return true
		end
		from = point
	end
	return false
end

local function last(path: { ApproachPath.Point }): ApproachPath.Point
	return path[#path]
end

describe("Approach path", function()
	it("tells a segment through the box from one beside or along it", function()
		expect(ApproachPath.crosses({ x = -10, z = 0 }, { x = 10, z = 0 }, HX, HZ)).toBe(true)
		expect(ApproachPath.crosses({ x = -10, z = 20 }, { x = 10, z = 20 }, HX, HZ)).toBe(false)
		expect(ApproachPath.crosses({ x = -HX, z = -20 }, { x = -HX, z = 20 }, HX, HZ)).toBe(false)
		expect(ApproachPath.crosses({ x = -10, z = 0 }, { x = -7, z = 0 }, HX, HZ)).toBe(false)
		expect(ApproachPath.crosses({ x = 0, z = -20 }, { x = 1, z = 0 }, HX, HZ)).toBe(true)
	end)

	it("walks straight to the goal when nothing is in the way", function()
		local path = ApproachPath.find({ x = -14, z = 3 }, GOAL, HX, HZ)
		expect(#path).toBe(1)
		expect(last(path).x).toBe(GOAL.x)
	end)

	it("goes round the near corner from in front of or behind the car", function()
		local front = ApproachPath.find({ x = 0, z = -18 }, GOAL, HX, HZ)
		expect(#front).toBe(2)
		expect(front[1].x < -HX and front[1].z < -HZ).toBe(true)
		local behind = ApproachPath.find({ x = 2, z = 18 }, GOAL, HX, HZ)
		expect(#behind).toBe(2)
		expect(behind[1].x < -HX and behind[1].z > HZ).toBe(true)
	end)

	it("goes round two corners, the shorter way, from the far side", function()
		local nearFront = ApproachPath.find({ x = 9, z = -8 }, GOAL, HX, HZ)
		expect(#nearFront).toBe(3)
		expect(nearFront[1].z < -HZ and nearFront[2].z < -HZ).toBe(true)
		local nearRear = ApproachPath.find({ x = 9, z = 8 }, GOAL, HX, HZ)
		expect(nearRear[1].z > HZ and nearRear[2].z > HZ).toBe(true)
	end)

	it("never crosses the box, from anywhere around the car", function()
		local tried = 0
		for x = -20, 20, 2 do
			for z = -26, 26, 2 do
				-- A root cannot stand inside the car; starts inside the margin are the next spec's.
				if math.abs(x) >= HX or math.abs(z) >= HZ then
					local start = { x = x, z = z }
					local path = ApproachPath.find(start, GOAL, HX, HZ)
					expect(last(path).x == GOAL.x and last(path).z == GOAL.z).toBe(true)
					expect(crossesAny(start, path)).toBe(false)
					tried += 1
				end
			end
		end
		expect(tried > 300).toBe(true)
	end)

	it("steps out through the nearest side first when starting inside the margin", function()
		local start = { x = -HX + 0.05, z = 4 }
		local path = ApproachPath.find(start, GOAL, HX, HZ)
		expect(path[1].x < -HX).toBe(true)
		expect(path[1].z).toBe(4)
		expect(last(path).x).toBe(GOAL.x)
	end)
end)
