--!strict
local Reflectors = require("../src/shared/Rules/Reflectors")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

-- Config/Reflectors' tuning (it holds Color3s and Vector3s, which Lune cannot load).
local TUNING: Reflectors.Tuning = {
	fullTo = 70,
	reach = 320,
	cone = math.cos(math.rad(18)),
	coneEdge = math.cos(math.rad(38)),
	edgeOn = 0.15,
	faceOn = 0.5,
	levels = 4,
}

local function glow(changes: { [string]: any }): number
	local sight: Reflectors.Sight = { headlights = true, distance = 50, ahead = 1, facing = 1 }
	for key, value in changes do
		(sight :: any)[key] = value
	end
	return Reflectors.glow(sight, TUNING)
end

describe("Reflectors", function()
	it("glows in full ahead of the car, facing it, in its headlights", function()
		expect(glow({})).toBe(1)
	end)

	it("stays dark with the headlights off", function()
		expect(glow({ headlights = false })).toBe(0)
	end)

	it("stays dark seen edge-on or from behind", function()
		expect(glow({ facing = 0.1 })).toBe(0)
		expect(glow({ facing = -1 })).toBe(0)
	end)

	it("stays dark outside the beams", function()
		expect(glow({ ahead = math.cos(math.rad(60)) })).toBe(0)
		expect(glow({ ahead = -1 })).toBe(0)
	end)

	it("dims with distance and is gone at reach", function()
		local previous = 1
		for distance = 0, 400, 10 do
			local value = glow({ distance = distance })
			expect(value <= previous).toBe(true)
			previous = value
		end
		expect(glow({ distance = TUNING.reach })).toBe(0)
		expect(glow({ distance = (TUNING.fullTo + TUNING.reach) / 2 }) > 0).toBe(true)
		expect(glow({ distance = 0 / 0 })).toBe(0)
	end)

	it("shows its glow in steps", function()
		expect(Reflectors.level(0, 4)).toBe(0)
		expect(Reflectors.level(0.3, 4)).toBe(0.5)
		expect(Reflectors.level(1, 4)).toBe(1)
		expect(Reflectors.level(2, 4)).toBe(1)
		expect(Reflectors.level(0 / 0, 4)).toBe(0)
	end)
end)
