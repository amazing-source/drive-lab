--!strict
local DR458 = require("../src/shared/Config/Cars/DR458/Physics")
local Hinge = require("../src/shared/Rules/Hinge")
local ManifestBinding = require("../tools/ManifestBinding")
local Model = require("../src/shared/Config/Cars/DR458/Model")
local T = require("../../../tools/test/T")
local WindshieldDrops = require("../src/shared/Rules/WindshieldDrops")
local WiperSweep = require("../src/shared/Rules/WiperSweep")

local describe, it, expect = T.describe, T.it, T.expect

-- The 3D artist's wiper on the DR458 (manifest frame, metres, measured on the built candidate v17
-- after its refit from the camera solve of photo exterior/002), and its own check of both blade
-- ends turned by half the range and by all of it.
local MANIFEST = {
	pivot = { forward = 2.715, right = -0.15, up = 0.72312 },
	axis = { forward = -0.64048, right = 0.07345, up = -0.76446 },
	range = 1.97222,
	inner = { forward = 2.6037, right = 0.04719, up = 0.76242 },
	outer = { forward = 2.34768, right = 0.53392, up = 0.82393 },
	turned = {
		{
			share = 0.5,
			inner = { forward = 2.5095, right = -0.1313, up = 0.8242 },
			outer = { forward = 2.0103, right = -0.0537, up = 1.0501 },
		},
		{
			share = 1,
			inner = { forward = 2.5674, right = -0.3228, up = 0.7573 },
			outer = { forward = 2.1848, right = -0.7139, up = 0.8405 },
		},
	},
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

-- The wiper as the DR458's binding ships it, in the windscreen's frame, as Atmosphere/Windshield
-- builds it.
local function geometry(): WiperSweep.Geometry
	local wiper = Model.wiper
	assert(wiper, "the DR458's binding has its wiper")
	local function chassis(point: Hinge.CarPoint): Hinge.Vector
		return { x = point.right, y = point.up + Model.bodyRaise, z = -point.forward }
	end
	return WiperSweep.geometry(
		pane(),
		chassis(wiper.hinge.pivot),
		Hinge.chassis(wiper.hinge.axis),
		chassis(wiper.blade.inner),
		chassis(wiper.blade.outer),
		wiper.hinge.travel or 0,
		REACH
	)
end

local function distance(a: Hinge.Vector, b: Hinge.Vector): number
	return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
end

describe("WiperSweep", function()
	it("ships the 3D artist's wiper in the DR458's binding", function()
		local wiper = Model.wiper
		assert(wiper, "the DR458's binding has its wiper")
		local function near(a: Hinge.Vector, b: Hinge.Vector): boolean
			return distance(a, b) < 1e-4
		end
		local function chassis(point: Hinge.CarPoint): Hinge.Vector
			return { x = point.right, y = point.up + Model.bodyRaise, z = -point.forward }
		end
		expect(near(chassis(wiper.hinge.pivot), rig(MANIFEST.pivot))).toBe(true)
		expect(near(Hinge.chassis(wiper.hinge.axis), Hinge.chassis(MANIFEST.axis))).toBe(true)
		expect(near(chassis(wiper.blade.inner), rig(MANIFEST.inner))).toBe(true)
		expect(near(chassis(wiper.blade.outer), rig(MANIFEST.outer))).toBe(true)
		expect(wiper.hinge.travel).toBe(MANIFEST.range)
	end)

	it("turns the blade the way the 3D artist measured, at half its range and at the far end", function()
		local pivot, axis = Hinge.chassis(MANIFEST.pivot), Hinge.chassis(MANIFEST.axis)
		for _, check in MANIFEST.turned do
			for _, name in { "inner", "outer" } do
				local from = Hinge.chassis((MANIFEST :: any)[name])
				local turned = Hinge.rotate(from, pivot, axis, MANIFEST.range * check.share)
				expect(distance(turned, Hinge.chassis((check :: any)[name])) < 0.001).toBe(true)
			end
		end
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

	it(
		"over a whole wipe, clears the driver's level view and the road ahead, more on the driver's side",
		function()
			local g = geometry()
			local p = pane()
			-- The driver's eye (the manifest's Driver_Eye) looking level ahead, and down at the road: 3
			-- to 10 degrees below level is the road from about 20 m to 6 m ahead.
			local eye = rig({ forward = 1.3731, right = -0.3443, up = 0.9416 })
			for _, degrees in { 0, -3, -6, -10 } do
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
		end
	)
end)
