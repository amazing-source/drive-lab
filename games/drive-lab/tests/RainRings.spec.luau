--!strict
local RainRings = require("../src/shared/Rules/RainRings")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

type Rect = RainRings.Rect

local seed = 4242
local function between(low: number, high: number): number
	seed = (seed * 1103515245 + 12345) % 2147483648
	return low + (high - low) * seed / 2147483648
end

local function overlap(a: Rect, b: Rect): number
	local width = math.min(a.x1, b.x1) - math.max(a.x0, b.x0)
	local depth = math.min(a.z1, b.z1) - math.max(a.z0, b.z0)
	return if width > 0 and depth > 0 then width * depth else 0
end

local function randomRect(): Rect
	return { x0 = between(-5, -0.5), x1 = between(0.5, 5), z0 = between(-30, -0.5), z1 = between(0.5, 5) }
end

describe("RainRings", function()
	it("tiles a ring with four blocks, none overlapping another or the hole", function()
		for _ = 1, 200 do
			local hole, depth, ahead = randomRect(), between(0.5, 10), between(0, 12)
			local blocks = RainRings.blocks(hole, depth, ahead)
			local outer = RainRings.outer(hole, depth, ahead)
			expect(#blocks).toBe(4)
			local total = 0
			for index, block in blocks do
				total += RainRings.area(block)
				expect(overlap(block, hole)).toBe(0)
				for other = index + 1, 4 do
					expect(overlap(block, blocks[other])).toBe(0)
				end
				expect(overlap(block, outer)).toBeNear(RainRings.area(block), 1e-6)
			end
			expect(total).toBeNear(RainRings.area(outer) - RainRings.area(hole), 1e-6)
			-- The third block is the one behind the hole; the reach ahead deepens only the front.
			expect(blocks[3].z0).toBe(hole.z1)
			expect(outer.z0).toBeNear(hole.z0 - depth - ahead, 1e-9)
			expect(outer.z1).toBeNear(hole.z1 + depth, 1e-9)
			expect(outer.x1).toBeNear(hole.x1 + depth, 1e-9)
		end
	end)

	it("never lets a streak emitted outside the hole reach the base within its life", function()
		local crossed = 0
		for _ = 1, 200 do
			local base, margin = randomRect(), between(0, 1)
			local vx, vz, life = between(-20, 20), between(-90, 30), between(0.2, 1.5)
			local hole = RainRings.hole(base, margin, vx, vz, life)
			for _, block in RainRings.blocks(hole, between(1, 8), between(0, 10)) do
				for _ = 1, 6 do
					local x, z = between(block.x0, block.x1), between(block.z0, block.z1)
					for step = 0, 40 do
						-- A streak stays put in the world: from the camera it moves at minus its velocity.
						local t = life * step / 40
						local rx, rz = x - vx * t, z - vz * t
						if
							rx > base.x0 - margin
							and rx < base.x1 + margin
							and rz > base.z0 - margin
							and rz < base.z1 + margin
						then
							crossed += 1
						end
					end
				end
			end
		end
		expect(crossed).toBe(0)
	end)

	it("keeps the hole round the base when still and stretches it only along the motion", function()
		local base = { x0 = -1, x1 = 1, z0 = -2, z1 = 2 }
		local still = RainRings.hole(base, 0.5, 0, 0, 1)
		expect(still.x0).toBe(-1.5)
		expect(still.x1).toBe(1.5)
		expect(still.z0).toBe(-2.5)
		expect(still.z1).toBe(2.5)
		local ahead = RainRings.hole(base, 0.5, 0, -10, 0.5)
		expect(ahead.z0).toBe(-7.5)
		expect(ahead.z1).toBe(2.5)
		expect(ahead.x0).toBe(-1.5)
		local reversing = RainRings.hole(base, 0.5, 4, 10, 0.5)
		expect(reversing.z1).toBe(7.5)
		expect(reversing.z0).toBe(-2.5)
		expect(reversing.x1).toBe(3.5)
		local odd = RainRings.hole(base, 0 / 0, 0 / 0, math.huge, 1)
		expect(odd.x0).toBe(-1)
		expect(odd.z1).toBe(2)
	end)

	it("fills a column so its lowest streaks just reach the ground and none goes under", function()
		local fall = 7
		local column = RainRings.column(10, 6, 0.3, 0.5, fall)
		expect(column.bottom).toBe(10.3)
		expect(column.top).toBe(16)
		-- Born at the inlet's lowest point: at the end of its life its lower end meets the ground.
		expect(column.top - column.inlet - fall * column.lifetime).toBeNear(column.bottom, 1e-9)
		-- Born at the very top: it dies an inlet above that.
		expect(column.top - fall * column.lifetime).toBeNear(column.bottom + column.inlet, 1e-9)
		local short = RainRings.column(0, 0.2, 0.3, 0.5, fall)
		expect(short.lifetime).toBe(0)
		expect(short.top).toBe(short.bottom)
	end)

	it("fades what falls behind the camera with forward speed in the car views", function()
		expect(RainRings.behind(0, 15)).toBe(1)
		expect(RainRings.behind(7.5, 15)).toBe(0.5)
		expect(RainRings.behind(30, 15)).toBe(0)
		expect(RainRings.behind(-10, 15)).toBe(1)
		expect(RainRings.behind(0 / 0, 15)).toBe(1)
		expect(RainRings.behind(10, 0)).toBe(1)
	end)

	it("joins holes into the smallest rect holding both", function()
		local joined = RainRings.union(
			{ x0 = -1, x1 = 1, z0 = -5, z1 = 1 },
			{ x0 = -2, x1 = 0.5, z0 = -3, z1 = 4 }
		)
		expect(joined.x0).toBe(-2)
		expect(joined.x1).toBe(1)
		expect(joined.z0).toBe(-5)
		expect(joined.z1).toBe(4)
	end)
end)
