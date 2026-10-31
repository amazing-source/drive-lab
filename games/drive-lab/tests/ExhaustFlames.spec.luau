--!strict
local Catalog = require("../src/shared/Config/Cars/Catalog")
local DR458Model = require("../src/shared/Config/Cars/DR458/Model")
local DR458Physics = require("../src/shared/Config/Cars/DR458/Physics")
local ExhaustFlames = require("../src/shared/Rules/ExhaustFlames")
local ExhaustPops = require("../src/shared/Rules/ExhaustPops")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local FLAMES: ExhaustFlames.CarFlames = {
	chance = {
		["1"] = { Lift = 0, Downshift = 0.5, Upshift = 1 },
		OFF = { Lift = 1, Downshift = 1, Upshift = 1 },
	},
	minStrength = 0.25,
	fireballFrom = 0.75,
	rise = 0,
	dayShare = 0.35,
}

-- Config/ExhaustFlames.RISE, the rise a car without flames of its own throws at (that module holds
-- Color3s, which Lune cannot load).
local SHARED_RISE = 0.175

local function always(value: number): () -> number
	return function()
		return value
	end
end

local function never(): number
	error("drew a number")
end

local function angleBetween(a: ExhaustFlames.Vector, b: ExhaustFlames.Vector): number
	local dot = a.x * b.x + a.y * b.y + a.z * b.z
	return math.deg(math.acos(math.clamp(dot, -1, 1)))
end

describe("ExhaustFlames", function()
	it("throws a flame with every pop, as strong as the pop, on a car without its own flames", function()
		for _, strength in { 0, 0.2, 0.5, 1 } do
			expect(ExhaustFlames.share(nil, "Corsa", "Lift", strength, never)).toBe(strength)
		end
		expect(ExhaustFlames.share(nil, "Corsa", "Upshift", 1.4, never)).toBe(1)
	end)

	it("throws flame only from the pops its drive mode's chances let through", function()
		expect(ExhaustFlames.share(FLAMES, "1", "Lift", 0.8, always(0))).toBe(nil)
		expect(ExhaustFlames.share(FLAMES, "1", "Downshift", 0.8, always(0.4))).toBe(0.8)
		expect(ExhaustFlames.share(FLAMES, "1", "Downshift", 0.8, always(0.6))).toBe(nil)
		expect(ExhaustFlames.share(FLAMES, "1", "Upshift", 0.8, always(0.99))).toBe(0.8)
		expect(ExhaustFlames.share(FLAMES, "OFF", "Lift", 0.8, always(0.99))).toBe(0.8)
		expect(ExhaustFlames.share(FLAMES, "2", "Lift", 0.8, always(0))).toBe(nil)
	end)

	it("throws none from a pop quieter than the car's floor", function()
		expect(ExhaustFlames.share(FLAMES, "OFF", "Downshift", 0.2, always(0))).toBe(nil)
		expect(ExhaustFlames.share(FLAMES, "OFF", "Downshift", 0.25, always(0))).toBe(0.25)
	end)

	it("adds the orange fireballs only from the car's threshold, two on the loudest", function()
		-- Without a threshold: one, then two over half, as every pop did before per-car flames.
		expect(ExhaustFlames.fireballs(0, 0)).toBe(1)
		expect(ExhaustFlames.fireballs(0.5, 0)).toBe(1)
		expect(ExhaustFlames.fireballs(0.51, 0)).toBe(2)
		expect(ExhaustFlames.fireballs(0.7, 0.75)).toBe(0)
		expect(ExhaustFlames.fireballs(0.8, 0.75)).toBe(1)
		expect(ExhaustFlames.fireballs(0.9, 0.75)).toBe(2)
	end)

	it("sends the flame along the outlet's own axis, tilted up only by the car's rise", function()
		local back = ExhaustFlames.direction({ forward = -1, right = 0, up = 0 }, 0)
		expect(back.x).toBeNear(0, 1e-12)
		expect(back.y).toBeNear(0, 1e-12)
		expect(back.z).toBeNear(1, 1e-12)
		local skew = { forward = -2, right = 0.5, up = 0.3 }
		local length = math.sqrt(4 + 0.25 + 0.09)
		local along = ExhaustFlames.direction(skew, 0)
		expect(along.x).toBeNear(0.5 / length, 1e-12)
		expect(along.y).toBeNear(0.3 / length, 1e-12)
		expect(along.z).toBeNear(2 / length, 1e-12)
		local raised = ExhaustFlames.direction({ forward = -1, right = 0, up = 0 }, 0.175)
		expect(angleBetween(back, raised)).toBeNear(math.deg(math.atan(0.175)), 1e-9)
		expect(raised.y > 0).toBe(true)
	end)

	it("draws flames fainter by day, in full at night", function()
		expect(ExhaustFlames.visibility(0, 0.35)).toBe(1)
		expect(ExhaustFlames.visibility(1, 0.35)).toBe(0.35)
		expect(ExhaustFlames.visibility(0.5, 0.35)).toBeNear(0.675, 1e-12)
		expect(ExhaustFlames.visibility(3, 0.35)).toBe(0.35)
	end)
end)

describe("ExhaustFlames on the DR458", function()
	it("throws them as the SVJ does: a jet and a fireball with every pop, in every position", function()
		local flames = Catalog.cars.DR458.flames
		expect(flames).toBe(Catalog.cars.SVJ.flames)
		expect(flames).toBe(nil)
		local kinds: { ExhaustPops.Kind } = { "Lift", "Downshift", "Upshift" }
		for _, mode in DR458Physics.modeOrder do
			for _, kind in kinds do
				expect(ExhaustFlames.share(flames, mode, kind, 0.3, never)).toBe(0.3)
			end
		end
		expect(ExhaustFlames.fireballs(0, 0)).toBe(1)
	end)

	it("throws them out of each outlet in its binding, back and a little up as the SVJ's", function()
		local outlets = DR458Model.exhaustOutlets
		assert(outlets and #outlets == 2, "the DR458 has its two outlets")
		local length = math.sqrt(1 + SHARED_RISE ^ 2)
		local svj = { x = 0, y = SHARED_RISE / length, z = 1 / length }
		for _, outlet in outlets do
			expect(angleBetween(ExhaustFlames.direction(outlet.axis, SHARED_RISE), svj) < 1).toBe(true)
		end
	end)
end)
