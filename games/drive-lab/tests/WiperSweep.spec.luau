--!strict
local DR458 = require("../src/shared/Config/Cars/DR458/Physics")
local Hinge = require("../src/shared/Rules/Hinge")
local ManifestBinding = require("../tools/ManifestBinding")
local Model = require("../src/shared/Config/Cars/DR458/Model")
local T = require("../../../tools/test/T")
local WindshieldDrops = require("../src/shared/Rules/WindshieldDrops")
local WiperSweep = require("../src/shared/Rules/WiperSweep")

local describe, it, expect = T.describe, T.it, T.expect

-- The 3D artist's wiper on the DR458 (manifest frame, metres, measured on the built candidate v17).
local MANIFEST = {
	pivot = { forward = 2.715, right = -0.15, up = 0.72312 },
	axis = { forward = -0.62026, right = 0.07341, up = -0.78095 },
	range = 1.58825,
	inner = { forward = 2.5935, right = -0.05298, up = 0.77818 },
	outer = { forward = 2.38381, right = 0.44894, up = 0.83108 },
	-- Its own check of the outer end, turned by half the range.
	outerAtHalf = { forward = 2.113, right = 0.041, up = 1.008 },
}

local CENTRE = ManifestBinding.centreOfMass(DR458)
local REACH = 0.01

local function rig(point: Hinge.CarPoint): Hinge.Vector
	return Hinge.chassis(ManifestBinding.toRig(point, CENTRE))
end

-- The windscreen pane as Atmosphere/Windshield builds it from the binding.
local function pane(): WindshieldDrops.Pane
	local corners = {}
	for index, corner in Model.windshield do
		corners[index] = { x = corner.right, y = corner.up + Model.bodyRaise, z = -corner.forward }
	end
	return WindshieldDrops.pane(corners, { x = 0, y = 0, z = 1 })
end

local function geometry(): WiperSweep.Geometry
	return WiperSweep.geometry(
		pane(),
		rig(MANIFEST.pivot),
		Hinge.chassis(MANIFEST.axis),
		rig(MANIFEST.inner),
		rig(MANIFEST.outer),
		MANIFEST.range,
		REACH
	)
end

local function distance(a: Hinge.Vector, b: Hinge.Vector): number
	return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
end

describe("WiperSweep", function()
	it("turns the blade the way the 3D artist measured: its outer end at half the range", function()
		local pivot = Hinge.chassis(MANIFEST.pivot)
		local turned = Hinge.rotate(
			Hinge.chassis(MANIFEST.outer),
			pivot,
			Hinge.chassis(MANIFEST.axis),
			MANIFEST.range / 2
		)
		expect(distance(turned, Hinge.chassis(MANIFEST.outerAtHalf)) < 0.003).toBe(true)
	end)

	it(
		"sweeps each point of the blade at the turn that carries the blade over it, not before or after",
		function()
			local g = geometry()
			for _, at in { 0.2, 0.5, 0.8 } do
				local x, y = WiperSweep.bladeOnPane(g, 0.6, at)
				expect(WiperSweep.swept(g, at - 0.02, at + 0.02, x, y)).toBe(true)
				expect(WiperSweep.swept(g, at + 0.02, at - 0.02, x, y)).toBe(true)
				expect(WiperSweep.swept(g, 0, math.max(at - 0.15, 0), x, y)).toBe(false)
				expect(WiperSweep.swept(g, math.min(at + 0.15, 1), 1, x, y)).toBe(false)
			end
		end
	)

	it("never sweeps past the blade's outer end, nor anything while the blade stands still", function()
		local g = geometry()
		local x, y = WiperSweep.bladeOnPane(g, 1.4, 0.5)
		expect(WiperSweep.swept(g, 0, 1, x, y)).toBe(false)
		local mx, my = WiperSweep.bladeOnPane(g, 0.6, 0.5)
		expect(WiperSweep.swept(g, 0.9, 0.9, mx, my)).toBe(false)
	end)

	it("over a whole wipe, clears the driver's view of the road ahead, more on the driver's side", function()
		local g = geometry()
		local p = pane()
		-- The driver's eye (the manifest's Driver_Eye) looking ahead and down at the road: 3 to 10
		-- degrees below level is the road from about 20 m to 6 m ahead.
		local eye = rig({ forward = 1.3731, right = -0.3443, up = 0.9416 })
		for _, degrees in { -3, -6, -10 } do
			local down = math.rad(degrees)
			local ray = { x = 0, y = math.sin(down), z = -math.cos(down) }
			local n = p.normal
			local along = (
				(p.centre.x - eye.x) * n.x
				+ (p.centre.y - eye.y) * n.y
				+ (p.centre.z - eye.z) * n.z
			) / (ray.x * n.x + ray.y * n.y + ray.z * n.z)
			local offset = {
				x = eye.x + ray.x * along - p.centre.x,
				y = eye.y + ray.y * along - p.centre.y,
				z = eye.z + ray.z * along - p.centre.z,
			}
			local x = offset.x * p.right.x + offset.y * p.right.y + offset.z * p.right.z + p.width / 2
			local y = offset.x * p.down.x + offset.y * p.down.y + offset.z * p.down.z + p.height / 2
			expect(WindshieldDrops.inside(p.polygon, x, y, 0)).toBe(true)
			expect(WiperSweep.swept(g, 0, 1, x, y)).toBe(true)
		end
		local driver, driverSwept, passenger, passengerSwept = 0, 0, 0, 0
		local steps = 60
		for i = 1, steps do
			for j = 1, steps do
				local x, y = (i - 0.5) / steps * p.width, (j - 0.5) / steps * p.height
				if WindshieldDrops.inside(p.polygon, x, y, 0) then
					local swept = if WiperSweep.swept(g, 0, 1, x, y) then 1 else 0
					-- The driver sits on the car's left (left-hand drive): the pane's left half.
					if x < p.width / 2 then
						driver, driverSwept = driver + 1, driverSwept + swept
					else
						passenger, passengerSwept = passenger + 1, passengerSwept + swept
					end
				end
			end
		end
		expect(driverSwept / driver > passengerSwept / passenger).toBe(true)
	end)
end)
