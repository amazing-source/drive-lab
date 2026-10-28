--!strict
local NumberFormat = require("../src/NumberFormat")
local T = require("../../tools/test/T")
local VoxelGrid = require("../src/Voxel/VoxelGrid")

local describe, it, expect = T.describe, T.it, T.expect

describe("NumberFormat", function()
	it("abbreviates with suffixes", function()
		expect(NumberFormat.short(999)).toBe("999")
		expect(NumberFormat.short(1500)).toBe("1.5K")
		expect(NumberFormat.short(120)).toBe("120")
		expect(NumberFormat.short(2_500_000)).toBe("2.5M")
	end)

	it("rolls over instead of printing 1000K", function()
		expect(NumberFormat.short(999_999)).toBe("1M")
	end)

	it("formats clocks", function()
		expect(NumberFormat.clock(65)).toBe("1:05")
		expect(NumberFormat.clock(3725)).toBe("1:02:05")
	end)
end)

describe("VoxelGrid", function()
	it("merges a solid block into one box", function()
		local grid = VoxelGrid.new()
		grid:fill(0, 9, 0, 3, 0, 4, "body")
		expect(#grid:greedy()).toBe(1)
	end)

	it("covers every voxel exactly once across keys", function()
		local grid = VoxelGrid.new()
		grid:fill(0, 9, 0, 3, 0, 4, "body")
		grid:paint(2, 4, 3, 3, 0, 4, "stripe")
		grid:fill(5, 5, 0, 0, 0, 0, nil)
		local covered = 0
		for _, box in grid:greedy() do
			covered += (box.x2 - box.x1 + 1) * (box.y2 - box.y1 + 1) * (box.z2 - box.z1 + 1)
		end
		expect(covered).toBe(grid:count())
	end)
end)
