--!strict
local AirDebris = require("../src/shared/Rules/AirDebris")
local CameraRules = require("../src/shared/Rules/CarCamera")
local CarCamera = require("../src/shared/Config/CarCamera")
local Config = require("../src/shared/Config/AirDebris")
local SVJ = require("../src/shared/Config/Cars/SVJ/Physics")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local SPEEDS: AirDebris.Speeds = { from = 80, to = 280, exponent = 1 }
local STREAK: AirDebris.Streak =
	{ maxLength = 2.5, width = 0.006, exposure = 1 / 30, along = 0.6, across = 0.03 }
local RainStreaks = require("../src/shared/Rules/RainStreaks")

-- The streak a Fit draws: its length along the motion and its width, metres.
local function drawn(fit: RainStreaks.Fit, streak: AirDebris.Streak): (number, number)
	local stretch = RainStreaks.stretch(fit.squash)
	return 2 * fit.size * stretch * streak.along, 2 * fit.size / stretch * streak.across
end

describe("AirDebris", function()
	it("shows none below its speed, all of it from full speed, either way", function()
		expect(AirDebris.speedShare(0, SPEEDS)).toBe(0)
		expect(AirDebris.speedShare(79, SPEEDS)).toBe(0)
		expect(AirDebris.speedShare(80, SPEEDS)).toBe(0)
		expect(AirDebris.speedShare(180, SPEEDS)).toBeNear(0.5, 1e-12)
		expect(AirDebris.speedShare(-180, SPEEDS)).toBeNear(0.5, 1e-12)
		expect(AirDebris.speedShare(280, SPEEDS)).toBe(1)
		expect(AirDebris.speedShare(400, SPEEDS)).toBe(1)
		expect(AirDebris.speedShare(180, { from = 80, to = 280, exponent = 2 })).toBeNear(0.25, 1e-12)
	end)

	it("turns the debris to water with the road's wetness", function()
		expect(AirDebris.waterShare(0, 0.2, 0.4)).toBe(0)
		expect(AirDebris.waterShare(0.2, 0.2, 0.4)).toBe(0)
		expect(AirDebris.waterShare(0.3, 0.2, 0.4)).toBeNear(0.5, 1e-12)
		expect(AirDebris.waterShare(0.9, 0.2, 0.4)).toBe(1)
	end)

	it("emits what the car sweeps through: density times cross-section times speed", function()
		expect(AirDebris.rate(0.01, 8, 50, 1, math.huge)).toBeNear(4, 1e-12)
		expect(AirDebris.rate(0.01, 8, 50, 0.5, math.huge)).toBeNear(2, 1e-12)
		expect(AirDebris.rate(0.01, 8, -50, 1, math.huge)).toBeNear(4, 1e-12)
		expect(AirDebris.rate(0.01, 8, 500, 1, 30)).toBe(30)
		expect(AirDebris.rate(0.01, -8, 50, 1, math.huge)).toBe(0)
	end)

	it("caps all the rates together, keeping their proportions", function()
		local rates = { 10, 30, 60 }
		expect(AirDebris.cap(rates, 50)).toBeNear(0.5, 1e-12)
		expect(rates[1]).toBeNear(5, 1e-12)
		expect(rates[2]).toBeNear(15, 1e-12)
		expect(rates[3]).toBeNear(30, 1e-12)
		local under = { 1, 2 }
		expect(AirDebris.cap(under, 50)).toBe(1)
		expect(under[2]).toBe(2)
	end)

	it("follows the car's arc ahead: straight, a quarter turn right, and left", function()
		local forward, right, heading = AirDebris.ahead(20, 0, 0.5)
		expect(forward).toBe(10)
		expect(right).toBe(0)
		expect(heading).toBe(0)
		forward, right, heading = AirDebris.ahead(10, math.pi / 2, 1)
		expect(forward).toBeNear(20 / math.pi, 1e-12)
		expect(right).toBeNear(20 / math.pi, 1e-12)
		expect(heading).toBeNear(math.pi / 2, 1e-12)
		forward, right = AirDebris.ahead(10, -math.pi / 2, 1)
		expect(forward).toBeNear(20 / math.pi, 1e-12)
		expect(right).toBeNear(-20 / math.pi, 1e-12)
		-- A barely turning path is continuous with the straight one.
		local nearly = AirDebris.ahead(30, 1e-9, 0.4)
		expect(nearly).toBeNear(12, 1e-9)
	end)

	it("draws a streak as the car's travel over the exposure, its width kept, up to its cap", function()
		local length, width = drawn(AirDebris.streak(60, STREAK), STREAK)
		expect(length).toBeNear(2, 1e-9)
		expect(width).toBeNear(0.006, 1e-9)
		length, width = drawn(AirDebris.streak(-30, STREAK), STREAK)
		expect(length).toBeNear(1, 1e-9)
		expect(width).toBeNear(0.006, 1e-9)
		length = drawn(AirDebris.streak(200, STREAK), STREAK)
		expect(length).toBeNear(2.5, 1e-9)
		expect(AirDebris.streak(0, STREAK).size).toBe(0)
		expect(AirDebris.streak(0 / 0, STREAK).size).toBe(0)
	end)

	it("reads nonsense as no debris, never as an error", function()
		for _, odd in { 0 / 0, math.huge, -math.huge } do
			expect(AirDebris.speedShare(odd, SPEEDS)).toBe(0)
			expect(AirDebris.rate(odd, 8, 50, 1, 30)).toBe(0)
			local forward, right = AirDebris.ahead(odd, odd, odd)
			expect(forward).toBe(0)
			expect(right).toBe(0)
		end
	end)
end)

describe("AirDebris settings", function()
	it("keeps the slabs clear of the car's path in a bend at the SVJ's grip limit", function()
		-- A straight slab along the arc's tangent strays inward by its sagitta, length² / 8R, at
		-- each end. At the limit v² = aR, so whatever the bend that is a · window² / 8.
		local lead = Config.REGION.lead
		local window = lead[2] - lead[1]
		local limit = 1.3 * 9.81
		expect(limit * window * window / 8 < Config.REGION.margin).toBe(true)
	end)

	it("draws its streaks only at speed, all of them by the cars' top speeds, never opaque", function()
		local streaks = Config.STREAKS
		expect(streaks.speeds.from >= 120).toBe(true)
		expect(AirDebris.speedShare(streaks.speeds.from, streaks.speeds)).toBe(0)
		expect(streaks.speeds.to <= 300).toBe(true)
		expect(streaks.transparency >= 0.5).toBe(true)
		expect(streaks.speeds.from >= Config.SPEEDS.from).toBe(true)
	end)

	it("keeps its longest streak within the Squash range Studio offers (-3 to 3)", function()
		local shape = Config.STREAKS.shape
		local longest = AirDebris.streak(shape.maxLength / shape.exposure * 2, shape)
		expect(longest.squash <= 3).toBe(true)
	end)

	it("lives until the chase camera has passed it, at the slowest speed it shows", function()
		-- The slabs are laid from the car's middle; the chase camera hangs behind the rear axle,
		-- itself behind the middle, and leans back a little more under acceleration.
		local chase = CarCamera.CHASE
		local behind = chase.distance + chase.lean.max - (CameraRules.rearAxle(SVJ))
		local slowest = Config.SPEEDS.from / 3.6
		local passed = Config.REGION.lead[2] + behind / slowest
		expect(Config.LIFETIME[1] * (1 - Config.FADE[2]) > passed).toBe(true)
	end)
end)
