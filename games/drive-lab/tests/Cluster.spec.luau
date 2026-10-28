--!strict
local Cluster = require("../src/shared/Config/Cluster")
local Rules = require("../src/shared/Rules/Cluster")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

-- A UIGradient whose transparency steps from 0 to 1 at its middle, rotated `rotation` degrees
-- clockwise: a point of the square image shows if it lies on the gradient's opaque first half.
local function shows(rotation: number, angle: number): boolean
	local r, a = math.rad(rotation), math.rad(angle)
	return math.cos(a) * math.cos(r) + math.sin(a) * math.sin(r) < 0
end

describe("Cluster", function()
	it("lights cells in proportion to rpm, within the dial", function()
		expect(Rules.litCells(0)).toBe(0)
		expect(Rules.litCells(Cluster.DIAL_MAX_RPM / 2)).toBe(Cluster.CELLS / 2)
		expect(Rules.litCells(Cluster.DIAL_MAX_RPM)).toBe(Cluster.CELLS)
		expect(Rules.litCells(20000)).toBe(Cluster.CELLS)
		expect(Rules.litCells(-50)).toBe(0)
	end)

	it("lights the first red cell just past the redline", function()
		expect(Rules.isRed(Rules.litCells(Cluster.REDLINE_RPM))).toBe(false)
		expect(Rules.isRed(Rules.litCells(Cluster.REDLINE_RPM + 1))).toBe(true)
	end)

	it("paints red exactly the cells from the redline up", function()
		local firstRed = math.huge
		for index = 1, Cluster.CELLS do
			if Rules.isRed(index) then
				firstRed = math.min(firstRed, index)
			end
		end
		expect((firstRed - 1) / Cluster.CELLS * Cluster.DIAL_MAX_RPM).toBe(Cluster.REDLINE_RPM)
		expect(Rules.isRed(Cluster.CELLS)).toBe(true)
	end)

	it("wipes in exactly the lit cells, whatever the count", function()
		local cellSweep = Cluster.DIAL_SWEEP / Cluster.CELLS
		for lit = 0, Cluster.CELLS do
			local rotation = Rules.wipeRotation(lit)
			for cell = 1, Cluster.CELLS do
				-- Sample each cell near both of its edges and at its middle.
				for _, share in { 0.1, 0.5, 0.9 } do
					local angle = Cluster.DIAL_START + (cell - 1 + share) * cellSweep
					expect(shows(rotation, angle)).toBe(cell <= lit)
				end
			end
		end
	end)

	it("sweeps the dial to the top and back once on start-up", function()
		expect(Rules.startupRpm(0)).toBe(0)
		expect(Rules.startupRpm(Cluster.STARTUP_SECONDS / 2)).toBeNear(Cluster.DIAL_MAX_RPM, 1e-6)
		expect(Rules.startupRpm(Cluster.STARTUP_SECONDS)).toBe(nil)
		expect(Rules.startupRpm(-1)).toBe(nil)
	end)

	it("labels reverse, neutral and the gears", function()
		expect(Rules.gearLabel(-1)).toBe("R")
		expect(Rules.gearLabel(0)).toBe("N")
		expect(Rules.gearLabel(7)).toBe("7")
	end)

	it("flashes the cells on the limiter only", function()
		expect(Rules.cellsShown(false, 0.03)).toBe(true)
		expect(Rules.cellsShown(true, 0.01)).toBe(true)
		expect(Rules.cellsShown(true, 0.07)).toBe(false)
	end)
end)
