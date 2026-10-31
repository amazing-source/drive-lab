--!strict
local RainOptics = require("../src/shared/Rules/RainOptics")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local BLUR: RainOptics.Blur = { max = 0.35, perDrop = 0.12, halfLife = 0.15 }
local FOCUS: RainOptics.Focus =
	{ far = 0.12, radius = 40, hood = 60, onFoot = 30, margin = 10, nearMargin = 2, body = 6 }
local VIEWS: { RainOptics.View } = { "OnFoot", "Chase", "Hood" }

describe("RainOptics", function()
	it("never blurs the cockpit, and never past a third of a pixel elsewhere", function()
		local pulse = RainOptics.contact(0, 50, BLUR)
		expect(pulse).toBe(0.35)
		expect(RainOptics.blurSize("Cockpit", pulse, BLUR)).toBe(0)
		for _, view in VIEWS do
			expect(RainOptics.blurSize(view, pulse, BLUR)).toBe(0.35)
			expect(RainOptics.blurSize(view, 5, BLUR)).toBe(0.35)
			expect(RainOptics.blurSize(view, 0 / 0, BLUR)).toBe(0)
		end
	end)

	it("adds a little per drop and fades by half each half-life", function()
		expect(RainOptics.contact(0, 1, BLUR)).toBeNear(0.12, 1e-12)
		expect(RainOptics.contact(0.1, 2, BLUR)).toBeNear(0.34, 1e-12)
		expect(RainOptics.contact(0.1, -3, BLUR)).toBeNear(0.1, 1e-12)
		expect(RainOptics.decay(0.3, 0.15, BLUR)).toBeNear(0.15, 1e-12)
		expect(RainOptics.decay(0.3, 0.45, BLUR)).toBeNear(0.0375, 1e-12)
		expect(RainOptics.decay(0.3, -1, BLUR)).toBe(0.3)
		expect(RainOptics.decay(0 / 0, 0.1, BLUR)).toBe(0)
	end)

	it("has no depth of field in the cockpit or in dry weather while nothing moves", function()
		expect(RainOptics.depthOfField("Cockpit", 1, 0, 0, 20, 30, FOCUS).enabled).toBe(false)
		expect(RainOptics.depthOfField("Cockpit", 1, 0.4, 0, 20, 30, FOCUS).enabled).toBe(false)
		for _, view in VIEWS do
			expect(RainOptics.depthOfField(view, 0, 0, 0, 20, 30, FOCUS).enabled).toBe(false)
		end
	end)

	it("focuses on the car in the chase view and keeps all of it sharp", function()
		local chase = RainOptics.depthOfField("Chase", 1, 0, 0, 22, 30, FOCUS)
		expect(chase.enabled).toBe(true)
		expect(chase.distance).toBe(22)
		expect(chase.radius >= 30 / 2).toBe(true)
		expect(chase.far).toBeNear(0.12, 1e-12)
		expect(chase.near).toBe(0)
		local long = RainOptics.depthOfField("Chase", 1, 0, 0, 22, 100, FOCUS)
		expect(long.radius).toBe(60)
		local half = RainOptics.depthOfField("Hood", 0.5, 0, 0, nil, 30, FOCUS)
		expect(half.distance).toBe(60)
		expect(half.far).toBeNear(0.06, 1e-12)
		expect(RainOptics.depthOfField("Chase", 1, 0, 0, nil, 30, FOCUS).distance).toBe(30)
	end)

	it("blurs the road before the car in the chase view only, the car kept sharp", function()
		local dry = RainOptics.depthOfField("Chase", 0, 0.3, 0, 32, 26, FOCUS)
		expect(dry.enabled).toBe(true)
		expect(dry.near).toBe(0.3)
		expect(dry.far).toBe(0)
		-- Sharp from just before the car's tail to past its nose; the road nearer than that blurs.
		expect(dry.radius).toBe(26 / 2 + 2)
		expect(dry.distance - dry.radius).toBe(17)
		for _, view in { "OnFoot", "Hood" } :: { RainOptics.View } do
			expect(RainOptics.depthOfField(view, 0, 0.3, 0, 32, 26, FOCUS).enabled).toBe(false)
			expect(RainOptics.depthOfField(view, 1, 0.3, 0, 32, 26, FOCUS).near).toBe(0)
		end
		expect(RainOptics.depthOfField("Chase", 0, 0.3, 0, nil, 26, FOCUS).enabled).toBe(false)
	end)

	it("blurs the world past the car in the chase view, the car kept sharp", function()
		local dry = RainOptics.depthOfField("Chase", 0, 0, 0.3, 32, 26, FOCUS)
		expect(dry.enabled).toBe(true)
		expect(dry.far).toBe(0.3)
		expect(dry.near).toBe(0)
		expect(dry.distance).toBe(32)
		expect(dry.radius).toBe(26 / 2 + 2)
		expect(RainOptics.depthOfField("Chase", 1, 0, 0.05, 32, 26, FOCUS).far).toBeNear(0.12, 1e-12)
		expect(RainOptics.depthOfField("Chase", 1, 0, 0.5, 32, 26, FOCUS).far).toBe(0.5)
	end)

	it("blurs the world past the car's own body in the cockpit and hood views, never the body", function()
		for _, view in { "Cockpit", "Hood" } :: { RainOptics.View } do
			local depth = RainOptics.depthOfField(view, 0, 0.6, 0.3, 32, 26, FOCUS)
			expect(depth.enabled).toBe(true)
			expect(depth.near).toBe(0)
			expect(depth.far).toBe(0.3)
			expect(depth.distance).toBe(FOCUS.body)
			expect(depth.radius).toBe(FOCUS.body)
		end
		local wetHood = RainOptics.depthOfField("Hood", 1, 0, 0.05, nil, 26, FOCUS)
		expect(wetHood.far).toBeNear(0.12, 1e-12)
		expect(wetHood.distance).toBe(FOCUS.body)
	end)

	it("fades the cockpit's motion blur out with the rain on the windscreen", function()
		expect(RainOptics.depthOfField("Cockpit", 0.5, 0, 0.4, nil, 26, FOCUS).far).toBeNear(0.2, 1e-12)
		expect(RainOptics.depthOfField("Cockpit", 1, 0, 0.4, nil, 26, FOCUS).enabled).toBe(false)
	end)

	it("never blurs on foot for motion", function()
		expect(RainOptics.depthOfField("OnFoot", 0, 0.3, 0.3, 32, 26, FOCUS).enabled).toBe(false)
		expect(RainOptics.depthOfField("OnFoot", 1, 0.3, 0.6, 32, 26, FOCUS).far).toBeNear(0.12, 1e-12)
	end)
end)
