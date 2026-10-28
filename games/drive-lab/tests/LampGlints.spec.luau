--!strict
local LampGlints = require("../src/shared/Rules/LampGlints")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

-- Config/LampGlints' tuning (it holds a Color3, which Lune cannot load).
local TUNING: LampGlints.Tuning = {
	flareOpacity = 0.35,
	flareFadeFrom = 30,
	flareReach = 220,
	flareRain = 0.6,
	flareLength = 1.5,
	flareLengthPerMetre = 0.08,
	flareHeight = 0.25,
	flareHeightPerMetre = 0.025,
	reflectionOpacity = 0.55,
	reflectionFadeFrom = 40,
	reflectionReach = 180,
	dryBelow = 0.08,
	nearShare = 0.4,
	nearest = 2.5,
	edgeMargin = 0.3,
	shortest = 1.5,
	streakAngle = 0.05,
}
-- The road along +z, its right edge at x = 5.5; the eye in the right lane, a lamp 2 m off the
-- edge 60 m ahead.
local EYE = { x = 1.75, z = 0 }
local LAMP = { x = 7.5, z = 60 }
local EDGE = { x = 5.5, z = 60 }
local INWARD = { x = -1, z = 0 }
local EYE_HEIGHT = 2.2
local LAMP_HEIGHT = 3.49

local function along(point: LampGlints.Point): number
	return math.sqrt((point.x - EYE.x) ^ 2 + (point.z - EYE.z) ^ 2)
end

local function streak(wetness: number, eye: LampGlints.Point?, lamp: LampGlints.Point?): LampGlints.Streak?
	return LampGlints.reflection(
		eye or EYE,
		EYE_HEIGHT,
		lamp or LAMP,
		LAMP_HEIGHT,
		EDGE,
		INWARD,
		wetness,
		TUNING
	)
end

describe("LampGlints", function()
	describe("reflection", function()
		it("lies on the asphalt, on the line from the eye to the lamp, running towards the eye", function()
			local found = streak(1)
			assert(found, "no streak on a wet road")
			for _, point in { found.near, found.far } do
				expect(point.x <= EDGE.x - TUNING.edgeMargin + 1e-9).toBe(true)
				local cross = (point.x - EYE.x) * (LAMP.z - EYE.z) - (point.z - EYE.z) * (LAMP.x - EYE.x)
				expect(cross).toBeNear(0, 1e-9)
			end
			expect(along(found.near) < along(found.far)).toBe(true)
			expect(along(found.near) >= TUNING.nearest - 1e-9).toBe(true)
		end)

		it("begins just short of where the lamp is mirrored", function()
			local found = streak(1)
			assert(found, "no streak on a wet road")
			local mirror = EYE_HEIGHT / (EYE_HEIGHT + LAMP_HEIGHT)
			local distance = along(LAMP)
			expect(along(found.near) / distance).toBeNear(mirror * TUNING.nearShare, 1e-9)
		end)

		it("keeps the same width as the eye sees it from end to end", function()
			local found = streak(1)
			assert(found, "no streak on a wet road")
			local function seen(point: LampGlints.Point, width: number): number
				return width / math.sqrt(along(point) ^ 2 + EYE_HEIGHT ^ 2)
			end
			expect(seen(found.near, found.nearWidth)).toBeNear(TUNING.streakAngle, 1e-9)
			expect(seen(found.far, found.farWidth)).toBeNear(TUNING.streakAngle, 1e-9)
			expect(found.nearWidth < found.farWidth).toBe(true)
		end)

		it("shows none on a dry road and more the wetter it is", function()
			expect(streak(0)).toBe(nil)
			expect(streak(TUNING.dryBelow * 0.9)).toBe(nil)
			local close = { x = 7.5, z = 30 }
			local damp, wet = streak(0.4, nil, close), streak(1, nil, close)
			assert(damp and wet, "no streak on a damp or wet road")
			expect(damp.opacity < wet.opacity).toBe(true)
			expect(wet.opacity).toBeNear(TUNING.reflectionOpacity, 1e-9)
		end)

		it("shows none when the eye stands off the asphalt, before or behind the lamp", function()
			expect(streak(1, { x = 6.5, z = 0 })).toBe(nil)
			expect(streak(1, { x = 9, z = 0 })).toBe(nil)
		end)

		it("fades with the lamp's distance and is gone past reach", function()
			local previous = math.huge
			for ahead = 20, 400, 20 do
				local found = streak(1, nil, { x = 7.5, z = ahead })
				local opacity = if found then found.opacity else 0
				expect(opacity <= previous + 1e-9).toBe(true)
				previous = opacity
			end
			expect(streak(1, nil, { x = 7.5, z = TUNING.reflectionReach + 5 })).toBe(nil)
		end)
	end)

	describe("flare", function()
		it("is faint, longer and dimmer with distance, gone past reach", function()
			local near = LampGlints.flare(10, 0, TUNING)
			local far = LampGlints.flare(150, 0, TUNING)
			expect(near.opacity).toBeNear(TUNING.flareOpacity, 1e-9)
			expect(near.opacity <= 0.5).toBe(true)
			expect(far.opacity < near.opacity and far.opacity > 0).toBe(true)
			expect(far.length > near.length and far.height > near.height).toBe(true)
			-- About the same size on screen past 30 m: size over distance holds within 40 %.
			local mid = LampGlints.flare(30, 0, TUNING)
			expect((far.length / 150) / (mid.length / 30) > 0.6).toBe(true)
			expect((far.height / 150) / (mid.height / 30) > 0.6).toBe(true)
			expect(LampGlints.flare(TUNING.flareReach + 1, 0, TUNING).opacity).toBe(0)
		end)

		it("grows in rain and ignores nonsense", function()
			expect(LampGlints.flare(10, 1, TUNING).opacity > LampGlints.flare(10, 0, TUNING).opacity).toBe(
				true
			)
			expect(LampGlints.flare(0 / 0, 0, TUNING).opacity).toBe(0)
			expect(LampGlints.flare(10, 0 / 0, TUNING).opacity).toBeNear(TUNING.flareOpacity, 1e-9)
		end)
	end)

	it("tapers a glint to nothing at both ends and shows it whole in the middle", function()
		expect(LampGlints.window(0)).toBeNear(0, 1e-9)
		expect(LampGlints.window(1)).toBeNear(0, 1e-9)
		expect(LampGlints.window(0.5)).toBeNear(1, 1e-9)
		expect(LampGlints.window(0.25)).toBeNear(LampGlints.window(0.75), 1e-9)
		expect(LampGlints.window(0.1) < LampGlints.window(0.25)).toBe(true)
	end)

	it("draws a glint's transparency fully clear at its ends, at its opacity in the middle", function()
		local keypoints = LampGlints.taper(0.4, 13)
		expect(#keypoints).toBe(13)
		expect(keypoints[1].time).toBe(0)
		expect(keypoints[1].value).toBeNear(1, 1e-9)
		expect(keypoints[13].time).toBe(1)
		expect(keypoints[13].value).toBeNear(1, 1e-9)
		expect(keypoints[7].value).toBeNear(0.6, 1e-9)
		for index = 2, 13 do
			expect(keypoints[index].time > keypoints[index - 1].time).toBe(true)
		end
		expect(#LampGlints.taper(0.4, 1)).toBe(3)
	end)
end)
