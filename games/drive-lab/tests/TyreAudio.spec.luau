--!strict
local Config = require("../src/shared/Config/TyreAudio")
local DR458Audio = require("../src/shared/Config/Cars/DR458/Audio")
local EngineSound = require("../src/shared/Rules/EngineSound")
local SVJAudio = require("../src/shared/Config/Cars/SVJ/Audio")
local T = require("../../../tools/test/T")
local TyreAudio = require("../src/shared/Rules/TyreAudio")

local describe, it, expect = T.describe, T.it, T.expect

local TUNING = Config.TUNING
local DT = 1 / 60

local function axle(slip: number, slide: number): TyreAudio.Axle
	return { slips = { slip, 0 }, slides = { slide, 0 } }
end

local function input(rear: TyreAudio.Axle): TyreAudio.Input
	return { front = axle(0, 0), rear = rear, wetness = 0, engineLevel = 1, cockpit = false, driving = true }
end

-- What the engine of `pack` plays once settled at `rpm` and `throttle`, as the tyres' ceiling reads it.
local function engineLevel(pack: typeof(SVJAudio), rpm: number, throttle: number): number
	local engine = EngineSound.new(pack.engineLayers, pack.engineTuning)
	local mix = EngineSound.step(engine, rpm, throttle, DT)
	for _ = 1, 120 do
		mix = EngineSound.step(engine, rpm, throttle, DT)
	end
	return pack.engineVolume * EngineSound.level(mix)
end

-- The mix once settled on a steady input.
local function settled(given: TyreAudio.Input): TyreAudio.Mix
	local state = TyreAudio.new(TUNING)
	local mix = TyreAudio.step(state, given, DT)
	for _ = 1, 120 do
		mix = TyreAudio.step(state, given, DT)
	end
	return mix
end

describe("Tyre audio layers", function()
	it("is silent under the limit of grip", function()
		local squeal, skid = TyreAudio.shares(TUNING, 0.6, 0.8, 0)
		expect(squeal).toBe(0)
		expect(skid).toBe(0)
	end)

	it("squeals at the limit before the skid comes in", function()
		local squeal, skid = TyreAudio.shares(TUNING, 1.2, 3, 0)
		expect(squeal > 0.3).toBe(true)
		expect(skid).toBe(0)
	end)

	it("plays both in full through a drift's slip and slide", function()
		local squeal, skid = TyreAudio.shares(TUNING, 4, 12, 0)
		expect(squeal).toBeNear(1, 1e-9)
		expect(skid).toBeNear(1, 1e-9)
	end)

	it("trades most of the squeal for the skid on a lock-up", function()
		local driftSqueal, driftSkid = TyreAudio.shares(TUNING, 4, 12, 0)
		local lockSqueal, lockSkid = TyreAudio.shares(TUNING, 10, 12, 0)
		expect(lockSqueal <= 0.3 * driftSqueal + 1e-9).toBe(true)
		expect(lockSkid).toBe(driftSkid)
	end)

	it("fades out on a wet road over the smoke's range", function()
		local wetSqueal, wetSkid = TyreAudio.shares(TUNING, 4, 12, 0.3)
		expect(wetSqueal).toBe(0)
		expect(wetSkid).toBe(0)
		local dampSqueal = TyreAudio.shares(TUNING, 4, 12, 0.05)
		expect(dampSqueal).toBeNear(1, 1e-9)
	end)

	it("needs the patch to slide for the skid: a creeping wheel past its peak slip only squeals", function()
		local squeal, skid = TyreAudio.shares(TUNING, 4, 2, 0)
		expect(skid).toBe(0)
		expect(squeal > 0).toBe(true)
	end)

	it("pitches up as the patch slides faster", function()
		local slow = TyreAudio.axle(TUNING, axle(4, 4), 0)
		local fast = TyreAudio.axle(TUNING, axle(4, 18), 0)
		expect(fast.squealSpeed > slow.squealSpeed).toBe(true)
		expect(fast.skidSpeed > slow.skidSpeed).toBe(true)
	end)

	it("follows the axle's noisier tyre", function()
		local one = TyreAudio.axle(TUNING, { slips = { 4, 0.2 }, slides = { 12, 0.1 } }, 0)
		local other = TyreAudio.axle(TUNING, { slips = { 0.2, 4 }, slides = { 0.1, 12 } }, 0)
		expect(one.skid).toBe(other.skid)
		expect(one.skid > 0).toBe(true)
	end)
end)

describe("Tyre audio mix", function()
	it(
		"keeps all four loops the headroom under what the engine plays, at every rpm, throttle and slip",
		function()
			local margin = 10 ^ ((TUNING.loudnessOffsetDb - TUNING.headroomDb) / 20)
			for _, pack in { SVJAudio, DR458Audio } do
				for rpm = 800, 9000, 800 do
					for _, throttle in { 0, 1 } do
						local engine = engineLevel(pack, rpm, throttle)
						for slip = 0, 30, 3 do
							local given = input(axle(slip, 15))
							given.front = axle(slip, 15)
							given.engineLevel = engine
							local mix = settled(given)
							local level = math.sqrt(
								mix.front.squeal ^ 2
									+ mix.front.skid ^ 2
									+ mix.rear.squeal ^ 2
									+ mix.rear.skid ^ 2
							)
							expect(level <= engine * margin + 1e-6).toBe(true)
						end
					end
				end
			end
		end
	)

	it("adds the engine's loops as powers into one amplitude", function()
		expect(EngineSound.level({ volumes = { 0.3, 0.4 }, speeds = { 1, 1 } })).toBeNear(0.5, 1e-12)
	end)

	it("holds the ceiling the very next frame when the engine drops faster than the release", function()
		local state = TyreAudio.new(TUNING)
		local given = input(axle(4, 12))
		given.front = axle(4, 12)
		for _ = 1, 120 do
			TyreAudio.step(state, given, DT)
		end
		given.engineLevel = 0.25
		local mix = TyreAudio.step(state, given, DT)
		local level =
			math.sqrt(mix.front.squeal ^ 2 + mix.front.skid ^ 2 + mix.rear.squeal ^ 2 + mix.rear.skid ^ 2)
		expect(level <= TyreAudio.ceiling(TUNING, 0.25) + 1e-9).toBe(true)
	end)

	it("lowers the ceiling 6 dB when the engine plays at half its loudness", function()
		local full = { volumes = { 0.4, 0.3 }, speeds = { 1, 1 } }
		local half = { volumes = { 0.2, 0.15 }, speeds = { 1, 1 } }
		local ratio = TyreAudio.ceiling(TUNING, DR458Audio.engineVolume * EngineSound.level(half))
			/ TyreAudio.ceiling(TUNING, DR458Audio.engineVolume * EngineSound.level(full))
		expect(20 * math.log10(ratio)).toBeNear(-6.02, 0.01)
	end)

	it("is silent while nobody drives", function()
		local given = input(axle(5, 15))
		given.driving = false
		local mix = settled(given)
		expect(mix.rear.squeal).toBeNear(0, 1e-6)
		expect(mix.rear.skid).toBeNear(0, 1e-6)
	end)

	it("makes next to nothing of a one-frame spike in the slip", function()
		local state = TyreAudio.new(TUNING)
		local peak = TyreAudio.step(state, input(axle(5, 15)), DT).rear.skid
		for _ = 1, 30 do
			peak = math.max(peak, TyreAudio.step(state, input(axle(0, 0)), DT).rear.skid)
		end
		local full = settled(input(axle(5, 15))).rear.skid
		expect(peak < 0.5 * full).toBe(true)
	end)

	it("plays quieter in the cockpit", function()
		local outside = settled(input(axle(4, 12)))
		local given = input(axle(4, 12))
		given.cockpit = true
		local inside = settled(given)
		expect(inside.rear.skid < outside.rear.skid).toBe(true)
	end)
end)
