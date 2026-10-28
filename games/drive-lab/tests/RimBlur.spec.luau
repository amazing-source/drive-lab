--!strict
local Config = require("../src/shared/Config/RimBlur")
local RimBlur = require("../src/shared/Rules/RimBlur")
local SVJ = require("../src/shared/Config/Cars/SVJ")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local TUNING: RimBlur.Tuning = { from = 15, to = 40 }

describe("RimBlur", function()
	it("reads the spin of a rolling wheel from its speed and radius, either way", function()
		expect(RimBlur.spin(10, 0.25)).toBeNear(40, 1e-12)
		expect(RimBlur.spin(-10, 0.25)).toBeNear(40, 1e-12)
		expect(RimBlur.spin(0, 0.3)).toBe(0)
		expect(RimBlur.spin(0 / 0, 0.3)).toBe(0)
		expect(RimBlur.spin(math.huge, 0.3)).toBe(0)
		expect(function()
			RimBlur.spin(10, 0)
		end).toThrow()
	end)

	it("stays sharp below the blur, is fully blurred above it and halfway at its middle", function()
		expect(RimBlur.share(TUNING, 0)).toBe(0)
		expect(RimBlur.share(TUNING, 15)).toBe(0)
		expect(RimBlur.share(TUNING, 27.5)).toBeNear(0.5, 1e-12)
		expect(RimBlur.share(TUNING, 40)).toBe(1)
		expect(RimBlur.share(TUNING, 400)).toBe(1)
		expect(RimBlur.share(TUNING, 0 / 0)).toBe(0)
	end)

	it("fades without a step at either end and never backs off as the spin rises", function()
		local previous = 0
		for spin = 15, 40, 0.05 do
			local share = RimBlur.share(TUNING, spin)
			expect(share >= previous).toBeTruthy()
			previous = share
		end
		-- Eased: a twentieth of the way in, the share is under a hundredth.
		expect(RimBlur.share(TUNING, 15 + 25 / 20) < 0.01).toBeTruthy()
		expect(RimBlur.share(TUNING, 40 - 25 / 20) > 0.99).toBeTruthy()
	end)

	it("shows only the car's wheel when sharp, and cross-fades face and disc once swapped", function()
		local sharp = RimBlur.layers(0)
		expect(sharp.swapped).toBe(false)
		local blurred = RimBlur.layers(1)
		expect(blurred.swapped).toBe(true)
		expect(blurred.face).toBe(1)
		expect(blurred.disc).toBe(0)
		local between = RimBlur.layers(0.3)
		expect(between.swapped).toBe(true)
		expect(between.face).toBeNear(0.3, 1e-12)
		expect(between.disc).toBeNear(0.7, 1e-12)
		expect(RimBlur.layers(0 / 0).swapped).toBe(false)
		expect(RimBlur.layers(2).face).toBe(1)
	end)

	it("writes only changes of a step or more, and always the swap and the ends", function()
		local shown = RimBlur.layers(0.5)
		expect(RimBlur.changed(shown, RimBlur.layers(0.51), 0.02)).toBe(false)
		expect(RimBlur.changed(shown, RimBlur.layers(0.53), 0.02)).toBe(true)
		expect(RimBlur.changed(RimBlur.layers(0), RimBlur.layers(0.001), 0.02)).toBe(true)
		expect(RimBlur.changed(RimBlur.layers(0.995), RimBlur.layers(1), 0.02)).toBe(true)
		expect(RimBlur.changed(RimBlur.layers(0.005), RimBlur.layers(0), 0.02)).toBe(true)
		expect(RimBlur.changed(RimBlur.layers(1), RimBlur.layers(1), 0.02)).toBe(false)
	end)

	it("knows when a rim looks still: one repeat a frame", function()
		-- A five-spoke rim at 60 FPS: 75.4 rad/s, about 96 km/h on a 0.354 m tyre.
		expect(RimBlur.frozenSpin(5, 60)).toBeNear(2 * math.pi / 5 * 60, 1e-12)
		expect(RimBlur.frozenSpin(5, 60) * 0.354 * 3.6).toBeNear(96, 0.1)
		expect(RimBlur.frozenSpin(10, 30)).toBeNear(RimBlur.frozenSpin(5, 60) / 4, 1e-12)
	end)
end)

describe("RimBlur config", function()
	it("is fully blurred before the SVJ's rim looks still at the frame rate", function()
		local frozen = RimBlur.frozenSpin(Config.RIM_REPEATS, Config.FRAME_RATE)
		expect(Config.SPIN.from > 0).toBeTruthy()
		expect(Config.SPIN.to > Config.SPIN.from).toBeTruthy()
		expect(Config.SPIN.to < frozen).toBeTruthy()
	end)

	it("starts to blur above a walking pace on either axle", function()
		for _, axle in { SVJ.front, SVJ.rear } do
			local kmh = Config.SPIN.from * axle.tyre.radius * 3.6
			expect(kmh > 10).toBeTruthy()
		end
	end)
end)
