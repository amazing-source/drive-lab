--!strict
local CarLights = require("../src/shared/Rules/CarLights")
local Config = require("../src/shared/Config/CarLights")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local TUNING: CarLights.Tuning = {
	rainOn = 0.3,
	brakeOn = 0.05,
	blinkHz = 1.5,
	blinkOnShare = 0.5,
	drlWithHeadlights = 0.15,
	drlWhileIndicating = 0,
	highBeamLevel = 1.6,
}

local function state(overrides: { [string]: any }): CarLights.State
	local base: { [string]: any } = {
		running = true,
		mode = "Auto",
		highBeam = false,
		night = false,
		rain = 0,
		brake = 0,
		gear = 1,
		indicating = 0,
		cabin = false,
	}
	for key, value in overrides do
		base[key] = value
	end
	return base :: any
end

local function decide(overrides: { [string]: any }): CarLights.Lit
	return CarLights.decide(state(overrides), TUNING)
end

describe("CarLights", function()
	it("switches the headlights on automatically at night and in heavy rain only", function()
		expect(decide({}).headlights).toBe(false)
		expect(decide({ night = true }).headlights).toBe(true)
		expect(decide({ rain = 0.6 }).headlights).toBe(true)
		expect(decide({ rain = 0.1 }).headlights).toBe(false)
	end)

	it("obeys a forced mode over the automatic", function()
		expect(decide({ mode = "On" }).headlights).toBe(true)
		expect(decide({ mode = "Off", night = true }).headlights).toBe(false)
	end)

	it("cycles the modes Auto, On, Off and back", function()
		expect(CarLights.nextMode("Auto")).toBe("On")
		expect(CarLights.nextMode("On")).toBe("Off")
		expect(CarLights.nextMode("Off")).toBe("Auto")
	end)

	it("lights the brakes on the pedal and the reversing light in reverse", function()
		expect(decide({ brake = 0.02 }).brake).toBe(false)
		expect(decide({ brake = 0.4 }).brake).toBe(true)
		expect(decide({ gear = -1 }).reverse).toBe(true)
		expect(decide({ gear = 0 }).reverse).toBe(false)
	end)

	it(
		"keeps every outside lamp dark until the ignition is on, and the cabin light works without it",
		function()
			local off = decide({
				running = false,
				mode = "On",
				night = true,
				brake = 1,
				gear = -1,
				indicator = "Left",
				cabin = true,
			})
			expect(off.headlights).toBe(false)
			expect(off.drlLeft).toBe(0)
			expect(off.drlRight).toBe(0)
			expect(off.tail).toBe(false)
			expect(off.brake).toBe(false)
			expect(off.reverse).toBe(false)
			expect(off.left).toBe(false)
			expect(off.cabin).toBe(true)
		end
	)

	it("lights the indicator from the moment it is switched on, at its rate, the other side dark", function()
		local period = 1 / TUNING.blinkHz
		expect(decide({ indicator = "Left", indicating = 0 }).left).toBe(true)
		expect(decide({ indicator = "Left", indicating = 0.49 * period }).left).toBe(true)
		expect(decide({ indicator = "Left", indicating = 0.51 * period }).left).toBe(false)
		expect(decide({ indicator = "Left", indicating = 1.01 * period }).left).toBe(true)
		expect(decide({ indicator = "Left", indicating = 0 }).right).toBe(false)
	end)

	it("runs the daytime lights full, dimmed to a position lamp with the headlights", function()
		expect(decide({}).drlLeft).toBe(1)
		expect(decide({ night = true }).drlLeft).toBe(TUNING.drlWithHeadlights)
		expect(decide({ night = true }).drlRight).toBe(TUNING.drlWithHeadlights)
	end)

	it("puts out the running light on the indicator's side for the whole flash cycle", function()
		local period = 1 / TUNING.blinkHz
		for _, elapsed in { 0, 0.75 * period } do
			local lit = decide({ indicator = "Right", indicating = elapsed })
			expect(lit.drlRight).toBe(TUNING.drlWhileIndicating)
			expect(lit.drlLeft).toBe(1)
		end
	end)

	it("flashes both indicators together as hazards, from the moment they start, only running", function()
		local period = 1 / TUNING.blinkHz
		for _, case in { { 0, true }, { 0.49 * period, true }, { 0.51 * period, false } } do
			local lit = decide({ hazards = true, hazardsFor = case[1] })
			expect(lit.left).toBe(case[2])
			expect(lit.right).toBe(case[2])
			expect(lit.drlLeft).toBe(TUNING.drlWhileIndicating)
			expect(lit.drlRight).toBe(TUNING.drlWhileIndicating)
		end
		local off = decide({ hazards = true, hazardsFor = 0, running = false })
		expect(off.left or off.right).toBe(false)
		local none = decide({ hazards = false, hazardsFor = 0 })
		expect(none.left or none.right).toBe(false)
	end)

	it("lights the tail lamps with the headlights, not with the running lights alone", function()
		expect(decide({}).tail).toBe(false)
		expect(decide({ night = true }).tail).toBe(true)
	end)

	it("burns the Y lamps as tail lamps at a fifth of their brake output or less", function()
		local tail = CarLights.levels(decide({ night = true }), Config.TAIL_SHARE, TUNING.highBeamLevel)
		local braking =
			CarLights.levels(decide({ night = true, brake = 1 }), Config.TAIL_SHARE, TUNING.highBeamLevel)
		expect(braking.tail).toBe(1)
		expect(tail.tail > 0).toBe(true)
		expect(braking.tail / tail.tail >= 5).toBe(true)
		expect(braking.stop).toBe(1)
		expect(tail.stop).toBe(0)
		expect(tail.position).toBe(1)
	end)

	it("draws lamps brighter by day than at night, in proportion to their level", function()
		expect(CarLights.daylight(0.6, 0.6, 1.6)).toBe(0)
		expect(CarLights.daylight(2.4, 0.6, 1.6)).toBe(1)
		expect(CarLights.daylight(1.1, 0.6, 1.6)).toBeNear(0.5, 1e-9)
		expect(CarLights.strength(1, 2, 8, 0)).toBe(2)
		expect(CarLights.strength(1, 2, 8, 1)).toBe(8)
		expect(CarLights.strength(0.5, 2, 8, 0.5)).toBeNear(2.5, 1e-9)
	end)

	it("tells a tap from a hold on the pad's lights button", function()
		local hold = 0.5
		local press: CarLights.Press = { since = nil, spent = false }
		expect(CarLights.press(press, true, 0, hold)).toBe(nil)
		expect(CarLights.press(press, true, 0.3, hold)).toBe(nil)
		expect(CarLights.press(press, false, 0.35, hold)).toBe("Tap")
		expect(CarLights.press(press, false, 0.4, hold)).toBe(nil)

		expect(CarLights.press(press, true, 1, hold)).toBe(nil)
		expect(CarLights.press(press, true, 1.49, hold)).toBe(nil)
		expect(CarLights.press(press, true, 1.5, hold)).toBe("Hold")
		expect(CarLights.press(press, true, 2.5, hold)).toBe(nil)
		expect(CarLights.press(press, false, 2.6, hold)).toBe(nil)
	end)

	it("keeps the configured indicator rhythm and stop-to-tail ratio inside the regulations", function()
		local perMinute = Config.TUNING.blinkHz * 60
		expect(perMinute >= 60 and perMinute <= 120).toBe(true)
		expect(Config.TUNING.blinkOnShare >= 0.3 and Config.TUNING.blinkOnShare <= 0.75).toBe(true)
		expect(1 / Config.TAIL_SHARE >= 5).toBe(true)
	end)

	it("shines the high beam only while the headlights are on", function()
		expect(decide({ highBeam = true }).highBeam).toBe(false)
		expect(decide({ highBeam = true, night = true }).highBeam).toBe(true)
		expect(decide({ highBeam = true, mode = "On" }).highBeam).toBe(true)
		expect(decide({ highBeam = true, mode = "Off", night = true }).highBeam).toBe(false)
		expect(decide({ highBeam = true, mode = "On", running = false }).highBeam).toBe(false)
		expect(decide({ mode = "On" }).highBeam).toBe(false)
	end)

	it("steps the pad's lights button Auto, On, high beam, Off and round", function()
		local mode, high = CarLights.nextPadLights("Auto", false)
		expect(mode).toBe("On")
		expect(high).toBe(false)
		mode, high = CarLights.nextPadLights(mode, high)
		expect(mode).toBe("On")
		expect(high).toBe(true)
		mode, high = CarLights.nextPadLights(mode, high)
		expect(mode).toBe("Off")
		expect(high).toBe(false)
		mode, high = CarLights.nextPadLights(mode, high)
		expect(mode).toBe("Auto")
		expect(high).toBe(false)
		mode, high = CarLights.nextPadLights("Auto", true)
		expect(mode).toBe("On")
		expect(high).toBe(false)
	end)

	it("glows the projector brighter on high beam than dipped", function()
		local dipped = CarLights.levels(decide({ mode = "On" }), Config.TAIL_SHARE, TUNING.highBeamLevel)
		local high = CarLights.levels(
			decide({ mode = "On", highBeam = true }),
			Config.TAIL_SHARE,
			TUNING.highBeamLevel
		)
		local off = CarLights.levels(
			decide({ mode = "Off", highBeam = true }),
			Config.TAIL_SHARE,
			TUNING.highBeamLevel
		)
		expect(dipped.projector).toBe(1)
		expect(high.projector).toBe(TUNING.highBeamLevel)
		expect(high.projector > dipped.projector).toBe(true)
		expect(off.projector).toBe(0)
		expect(Config.TUNING.highBeamLevel > 1).toBe(true)
	end)
end)

describe("CarLights: headlight flasher", function()
	it("flashes the high beam while the flasher is held, with the headlights off by day", function()
		local flash = decide({ flash = true })
		expect(flash.headlights).toBe(false)
		expect(flash.highBeam).toBe(true)
		expect(flash.tail).toBe(false)
		expect(decide({ flash = true, mode = "Off", night = true }).highBeam).toBe(true)
		expect(decide({ flash = true, mode = "On" }).highBeam).toBe(true)
		local levels = CarLights.levels(flash, Config.TAIL_SHARE, TUNING.highBeamLevel)
		expect(levels.projector).toBe(TUNING.highBeamLevel)
	end)

	it("flashes nothing with the ignition off, and nothing once the flasher is let go", function()
		expect(decide({ flash = true, running = false }).highBeam).toBe(false)
		expect(decide({ flash = false }).highBeam).toBe(false)
		expect(decide({}).highBeam).toBe(false)
	end)
end)

describe("CarLights: rain light", function()
	local FOUR_HZ: CarLights.RainPattern = { hz = 4, onShare = 0.5 }

	it("lights the rain light with its switch and the ignition, steady without a pattern", function()
		for _, elapsed in { 0, 0.13, 0.2, 1.7, 30 } do
			local lit = decide({ rainLight = true, rainLightFor = elapsed })
			expect(lit.rainLight).toBe(true)
			expect(lit.rainLightOn).toBe(true)
		end
		expect(decide({ rainLight = false }).rainLight).toBe(false)
		expect(decide({}).rainLight).toBe(false)
		local off = decide({ rainLight = true, running = false })
		expect(off.rainLight).toBe(false)
		expect(off.rainLightOn).toBe(false)
		expect(CarLights.levels(decide({ rainLight = true }), Config.TAIL_SHARE, 1.6).rain).toBe(1)
		expect(CarLights.levels(decide({}), Config.TAIL_SHARE, 1.6).rain).toBe(0)
	end)

	it("flashes a rain light with a pattern from the moment it is switched on, at its rate", function()
		local function at(elapsed: number): boolean
			return CarLights.decide(state({ rainLight = true, rainLightFor = elapsed }), TUNING, FOUR_HZ).rainLight
		end
		expect(at(0)).toBe(true)
		expect(at(0.1)).toBe(true)
		expect(at(0.15)).toBe(false)
		expect(at(0.24)).toBe(false)
		expect(at(0.26)).toBe(true)
		expect(CarLights.rainLit(0.15, { hz = 0, onShare = 0.5 })).toBe(true)
	end)

	it("keeps each tell-tale on its switch, steady while the rain light flashes", function()
		local dark = CarLights.decide(state({ rainLight = true, rainLightFor = 0.15 }), TUNING, FOUR_HZ)
		expect(dark.rainLight).toBe(false)
		expect(CarLights.tellTale("rainLight", dark)).toBe(true)
		expect(CarLights.tellTale("rainLight", decide({}))).toBe(false)
		expect(CarLights.tellTale("headlights", decide({ mode = "On" }))).toBe(true)
		expect(CarLights.tellTale("headlights", decide({}))).toBe(false)
		expect(CarLights.tellTale("highBeam", decide({ flash = true }))).toBe(true)
		expect(CarLights.tellTale("AC", decide({ mode = "On" }))).toBe(false)
	end)
end)

describe("CarLights: tell-tale LEDs", function()
	it("shows an LED's full colour by day, a share of it at night, none when off", function()
		local day, night = 3, 1.2
		expect(CarLights.ledShare(CarLights.strength(1, night, day, 1), day)).toBe(1)
		expect(CarLights.ledShare(CarLights.strength(1, night, day, 0), day)).toBeNear(0.4, 1e-12)
		expect(CarLights.ledShare(CarLights.strength(0, night, day, 0.5), day)).toBe(0)
		expect(CarLights.ledShare(5, day)).toBe(1)
		expect(CarLights.ledShare(1, 0)).toBe(0)
	end)
end)

describe("CarLights: a sequential turn lamp", function()
	it(
		"lights one more piece every step from the start of each flash, all held to its end, none between",
		function()
			-- 1.5 flashes a second, half of each lit: on for 0.333 s of every 0.667 s.
			local function bars(elapsed: number): number
				return CarLights.sweepBars(elapsed, 1.5, 0.5, 3, 0.1)
			end
			expect(bars(0)).toBe(1)
			expect(bars(0.05)).toBe(1)
			expect(bars(0.1)).toBe(2)
			expect(bars(0.15)).toBe(2)
			expect(bars(0.2)).toBe(3)
			expect(bars(0.3)).toBe(3)
			expect(bars(0.34)).toBe(0)
			expect(bars(0.6)).toBe(0)
			-- The next flash starts again at the inner piece.
			expect(bars(0.6667)).toBe(1)
			expect(bars(0.8667)).toBe(3)
			expect(bars(-1)).toBe(1)
		end
	)

	it(
		"says which side's indicator runs, and how long its turn signal has, apart from the hazards",
		function()
			local turning = decide({ indicator = "Left", indicating = 0.4 })
			expect(turning.leftRunning).toBe(true)
			expect(turning.rightRunning).toBe(false)
			expect(turning.leftTurnFor).toBe(0.4)
			expect(turning.rightTurnFor).toBe(nil)
			-- On the hazards both run and neither sweeps: the factory car flashes them together.
			local hazards = decide({ hazards = true, hazardsFor = 0.2, indicator = "Left", indicating = 0.4 })
			expect(hazards.leftRunning and hazards.rightRunning).toBe(true)
			expect(hazards.leftTurnFor).toBe(nil)
			expect(hazards.rightTurnFor).toBe(nil)
			local off = decide({ running = false, indicator = "Right", indicating = 0.1 })
			expect(off.rightRunning).toBe(false)
			expect(off.rightTurnFor).toBe(nil)
		end
	)
end)
