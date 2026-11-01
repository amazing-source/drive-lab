--!strict
local HandShapes = require("../src/shared/Rules/HandShapes")
local SVJ = require("../src/shared/Config/Cars/SVJ")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

-- Rig/StartupHands' choice before gestures (main at e0c50de), for a car without any: the mesh
-- drawn for each shape and which of the grip, its cuff and the wrist cuff show.
local function before(shape: string, startupShapes: boolean, pinch: boolean): HandShapes.Shown
	local drawn = if shape == "Pinch" and not pinch then "Point" else shape
	local posed = startupShapes and drawn ~= "Grip"
	return {
		shape = drawn,
		grip = not posed,
		gripCuff = not posed,
		wristCuff = posed,
		mesh = if posed then drawn else nil,
	}
end

local function same(a: HandShapes.Shown, b: HandShapes.Shown): boolean
	return a.shape == b.shape
		and a.grip == b.grip
		and a.gripCuff == b.gripCuff
		and a.wristCuff == b.wristCuff
		and a.mesh == b.mesh
end

describe("Hand shapes: which hand mesh and cuff show", function()
	it("draws a car without gestures exactly as before, in every place (the SVJ's arms unchanged)", function()
		expect(SVJ.driver.gestures).toBe(nil)
		for _, startupShapes in { true, false } do
			for _, pinch in { true, false } do
				local have = { startupShapes = startupShapes, pinch = pinch and startupShapes, gestures = {} }
				for _, shape in { "Grip", "Rest", "Point", "Pinch" } do
					local now = HandShapes.shown(shape, have)
					local was = before(shape, startupShapes, pinch and startupShapes)
					if not same(now, was) then
						error(`{shape} with startupShapes={startupShapes} pinch={pinch} changed`)
					end
				end
			end
		end
	end)

	it(
		"draws a thumb mesh with the grip's cuff and hides the grip, and a posed one with the wrist cuff",
		function()
			local have = {
				startupShapes = true,
				pinch = false,
				gestures = { HandThumbPit_L = "Grip", HandManettino_R = "Wrist" },
			}
			local thumb = HandShapes.shown("HandThumbPit_L", have)
			expect(thumb.mesh).toBe("HandThumbPit_L")
			expect(thumb.grip).toBe(false)
			expect(thumb.gripCuff).toBe(true)
			expect(thumb.wristCuff).toBe(false)
			local finger = HandShapes.shown("HandManettino_R", have)
			expect(finger.gripCuff).toBe(false)
			expect(finger.wristCuff).toBe(true)
		end
	)

	it("stands the grip in for a thumb mesh the place lacks, and the Point hand for any other", function()
		local have = { startupShapes = true, pinch = false, gestures = {} }
		local thumb = HandShapes.shown("HandThumbWater_L", have)
		expect(thumb.shape).toBe("Grip")
		expect(thumb.grip).toBe(true)
		local finger = HandShapes.shown("HandManettino_R", have)
		expect(finger.shape).toBe("Point")
		expect(finger.mesh).toBe("Point")
	end)
end)

describe("Hand shapes: the shift hand's knob", function()
	it(
		"draws the open Rest hand on the knob, with the wrist cuff, while the place has no knob mesh",
		function()
			local have: HandShapes.Have = { startupShapes = true, pinch = true, gestures = {} }
			local shown = HandShapes.shown("Knob", have)
			expect(shown.shape).toBe("Rest")
			expect(shown.mesh).toBe("Rest")
			expect(shown.wristCuff).toBe(true)
			expect(shown.grip).toBe(false)
			-- A place without the posed meshes draws the grip, as for any posed shape.
			local bare = HandShapes.shown("Knob", { startupShapes = false, pinch = false, gestures = {} })
			expect(bare.shape).toBe("Rest")
			expect(bare.grip).toBe(true)
		end
	)
end)
