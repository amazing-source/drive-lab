--!strict
--[[
	The start-up's torso lean (Rules/StartupLean): how far forward at a time after the start key,
	and the turn about the hips in the seat frame, on a synthetic lean shaped like the Boss's.
]]
local Catalog = require("../src/shared/Config/Cars/Catalog")
local DriverStartup = require("../src/shared/Config/DriverStartup")
local StartupLean = require("../src/shared/Rules/StartupLean")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local LEAN: DriverStartup.Lean = {
	pivot = { x = 0, y = -0.003, z = 0.01 },
	keys = { { 0.1, 0 }, { 0.7, 7 }, { 2.1, 7 }, { 2.7, 0 } },
}

type Vector = { x: number, y: number, z: number }

-- v turned by the unit quaternion q (v + 2w(q x v) + 2 q x (q x v)).
local function rotate(q: { w: number, x: number, y: number, z: number }, v: Vector): Vector
	local tx = 2 * (q.y * v.z - q.z * v.y)
	local ty = 2 * (q.z * v.x - q.x * v.z)
	local tz = 2 * (q.x * v.y - q.y * v.x)
	return {
		x = v.x + q.w * tx + (q.y * tz - q.z * ty),
		y = v.y + q.w * ty + (q.z * tx - q.x * tz),
		z = v.z + q.w * tz + (q.x * ty - q.y * tx),
	}
end

local function moved(degrees: number, point: Vector): Vector
	local turn, offset = StartupLean.turn(LEAN.pivot, degrees)
	local turned = rotate(turn, point)
	return { x = turned.x + offset.x, y = turned.y + offset.y, z = turned.z + offset.z }
end

describe("Startup lean: how far forward", function()
	it("is 0 with no lean, no start key, or outside the keys' span", function()
		expect(StartupLean.degrees(nil, 1)).toBe(0)
		expect(StartupLean.degrees(LEAN, nil)).toBe(0)
		expect(StartupLean.degrees(LEAN, 0)).toBe(0)
		expect(StartupLean.degrees(LEAN, 0.05)).toBe(0)
		expect(StartupLean.degrees(LEAN, 2.8)).toBe(0)
		expect(StartupLean.degrees(LEAN, 60)).toBe(0)
		-- Keys that do not end upright still give way to 0 outside them: no lean is left behind.
		local held: DriverStartup.Lean = { pivot = LEAN.pivot, keys = { { 1, 5 }, { 2, 5 } } }
		expect(StartupLean.degrees(held, 0.5)).toBe(0)
		expect(StartupLean.degrees(held, 1.5)).toBe(5)
		expect(StartupLean.degrees(held, 3)).toBe(0)
	end)

	it("passes through each key and smoothsteps between them", function()
		for _, key in LEAN.keys do
			expect(StartupLean.degrees(LEAN, key[1])).toBeNear(key[2], 1e-12)
		end
		expect(StartupLean.degrees(LEAN, 0.4)).toBeNear(3.5, 1e-12)
		-- A quarter of the way in: 7 * (0.25^2 * (3 - 0.5)).
		expect(StartupLean.degrees(LEAN, 0.25)).toBeNear(7 * 0.15625, 1e-12)
		expect(StartupLean.degrees(LEAN, 1.4)).toBeNear(7, 1e-12)
		expect(StartupLean.degrees(LEAN, 2.4)).toBeNear(3.5, 1e-12)
	end)

	it("starts and settles with no jump: zero speed at each key", function()
		for _, key in LEAN.keys do
			local before = StartupLean.degrees(LEAN, key[1] - 1e-6)
			local after = StartupLean.degrees(LEAN, key[1] + 1e-6)
			expect(math.abs(after - before) < 1e-6).toBe(true)
		end
	end)
end)

describe("Startup lean: the turn about the hips", function()
	it("keeps the hips where they are", function()
		local hips = moved(7, LEAN.pivot)
		expect(hips.x).toBeNear(LEAN.pivot.x, 1e-12)
		expect(hips.y).toBeNear(LEAN.pivot.y, 1e-12)
		expect(hips.z).toBeNear(LEAN.pivot.z, 1e-12)
	end)

	it("tips the torso's top toward the nose by the angle, in the seat's upright plane", function()
		local height = 0.6
		local top = { x = 0.2, y = LEAN.pivot.y + height, z = LEAN.pivot.z }
		local leaned = moved(7, top)
		expect(leaned.x).toBeNear(0.2, 1e-12)
		expect(leaned.y).toBeNear(LEAN.pivot.y + height * math.cos(math.rad(7)), 1e-12)
		expect(leaned.z).toBeNear(LEAN.pivot.z - height * math.sin(math.rad(7)), 1e-12)
	end)

	it("is no turn at 0 degrees", function()
		local turn, offset = StartupLean.turn(LEAN.pivot, 0)
		expect(turn.w).toBe(1)
		expect(math.abs(offset.x) + math.abs(offset.y) + math.abs(offset.z)).toBe(0)
	end)

	it("leaves the cars without a lean as they were", function()
		for name, entry in Catalog.cars do
			expect(if entry.driver.startupPaths.LEAN == nil then name else `{name} has a lean`).toBe(name)
		end
	end)
end)
