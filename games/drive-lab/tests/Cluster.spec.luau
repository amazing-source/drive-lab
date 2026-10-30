--!strict
local Cluster = require("../src/shared/Config/Cluster")
local Rules = require("../src/shared/Rules/Cluster")
local SVJ = require("../src/shared/Config/Cars/SVJ")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local FACE = SVJ.cluster

-- A UIGradient whose transparency steps from 0 to 1 at its middle, rotated `rotation` degrees
-- clockwise: a point of the square image shows if it lies on the gradient's opaque first half.
local function shows(rotation: number, angle: number): boolean
	local r, a = math.rad(rotation), math.rad(angle)
	return math.cos(a) * math.cos(r) + math.sin(a) * math.sin(r) < 0
end

describe("Cluster", function()
	it("lights cells in proportion to rpm, within the dial", function()
		expect(Rules.litCells(FACE, 0)).toBe(0)
		expect(Rules.litCells(FACE, FACE.dialMaxRpm / 2)).toBe(FACE.cells / 2)
		expect(Rules.litCells(FACE, FACE.dialMaxRpm)).toBe(FACE.cells)
		expect(Rules.litCells(FACE, 20000)).toBe(FACE.cells)
		expect(Rules.litCells(FACE, -50)).toBe(0)
	end)

	it("lights the first red cell just past the redline", function()
		expect(Rules.isRed(FACE, Rules.litCells(FACE, FACE.redlineRpm))).toBe(false)
		expect(Rules.isRed(FACE, Rules.litCells(FACE, FACE.redlineRpm + 1))).toBe(true)
	end)

	it("paints red exactly the cells from the redline up", function()
		local firstRed = math.huge
		for index = 1, FACE.cells do
			if Rules.isRed(FACE, index) then
				firstRed = math.min(firstRed, index)
			end
		end
		expect((firstRed - 1) / FACE.cells * FACE.dialMaxRpm).toBe(FACE.redlineRpm)
		expect(Rules.isRed(FACE, FACE.cells)).toBe(true)
	end)

	it("wipes in exactly the lit cells, whatever the count", function()
		local cellSweep = FACE.dialSweep / FACE.cells
		for lit = 0, FACE.cells do
			local rotation = Rules.wipeRotation(FACE, lit)
			for cell = 1, FACE.cells do
				-- Sample each cell near both of its edges and at its middle.
				for _, share in { 0.1, 0.5, 0.9 } do
					local angle = FACE.dialStart + (cell - 1 + share) * cellSweep
					expect(shows(rotation, angle)).toBe(cell <= lit)
				end
			end
		end
	end)

	it("sweeps the dial to the top and back once on start-up", function()
		expect(Rules.startupRpm(FACE, 0)).toBe(0)
		expect(Rules.startupRpm(FACE, FACE.startupSeconds / 2)).toBeNear(FACE.dialMaxRpm, 1e-6)
		expect(Rules.startupRpm(FACE, FACE.startupSeconds)).toBe(nil)
		expect(Rules.startupRpm(FACE, -1)).toBe(nil)
	end)

	it("labels reverse, neutral and the gears", function()
		expect(Rules.gearLabel(-1)).toBe("R")
		expect(Rules.gearLabel(0)).toBe("N")
		expect(Rules.gearLabel(7)).toBe("7")
	end)

	it("flashes the cells on the limiter only", function()
		expect(Rules.cellsShown(FACE, false, 0.03)).toBe(true)
		expect(Rules.cellsShown(FACE, true, 0.01)).toBe(true)
		expect(Rules.cellsShown(FACE, true, 0.07)).toBe(false)
	end)

	it("shows LAUNCH under the gear over the ESC light while launch control is on", function()
		expect(Rules.lampText("EscOff", true)).toBe(Cluster.LAUNCH_TEXT)
		expect(Rules.lampText("EscOff", false)).toBe("ESC OFF")
		expect(Rules.lampText("Esc", false)).toBe("ESC")
		expect(Rules.lampText("Hidden", false)).toBe("")
	end)
end)

describe("Cluster, per car", function()
	-- Another car's face: ten cells over a 9,000 rpm dial that sweeps a half turn from 170 degrees,
	-- red from 8,000, a two-second start-up sweep and a slower limiter flash.
	local other = table.clone(FACE)
	other.cells = 10
	other.dialMaxRpm = 9000
	other.redlineRpm = 8000
	other.dialStart = 170
	other.dialSweep = 180
	other.startupSeconds = 2
	other.limiterFlashHz = 4

	it("lights and reddens the car's own cells", function()
		expect(Rules.litCells(other, 4500)).toBe(5)
		expect(Rules.litCells(FACE, 4500)).toBe(9)
		expect(Rules.isRed(other, 9)).toBe(false)
		expect(Rules.isRed(other, 10)).toBe(true)
		expect(Rules.isRed(FACE, 10)).toBe(false)
	end)

	it("turns the wipe over the car's own dial", function()
		expect(Rules.wipeRotation(other, 5)).toBeNear(170 + 90 + 90, 1e-9)
	end)

	it("sweeps and flashes at the car's own pace", function()
		expect(Rules.startupRpm(other, 1)).toBeNear(9000, 1e-6)
		expect(Rules.startupRpm(other, 1.5)).toBeNear(9000 * math.sin(math.pi * 0.75), 1e-6)
		expect(Rules.startupRpm(FACE, 1.5)).toBe(nil)
		expect(Rules.cellsShown(other, true, 0.2)).toBe(false)
		expect(Rules.cellsShown(FACE, true, 0.2)).toBe(true)
	end)
end)
