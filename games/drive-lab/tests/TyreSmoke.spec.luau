--!strict
local Config = require("../src/shared/Config/TyreSmoke")
local DR458 = require("../src/shared/Config/Cars/DR458/Physics")
local DriveSim = require("../tools/DriveSim")
local SVJ = require("../src/shared/Config/Cars/SVJ/Physics")
local T = require("../../../tools/test/T")
local TyreSmoke = require("../src/shared/Rules/TyreSmoke")

local describe, it, expect = T.describe, T.it, T.expect

local DT = 1 / 60
local KMH = 1 / 3.6
local THRESHOLDS: TyreSmoke.Thresholds = {
	slip = { from = 2, to = 4 },
	slide = { from = 2, to = 10 },
	wet = { from = 0.1, to = 0.3 },
	rate = 20,
	totalRate = 50,
	rise = 0.1,
	fall = 0.4,
}
-- Long enough for any wheel's smoke to settle at its target.
local SETTLE = 10

local function wheel(slip: number, slide: number): TyreSmoke.Wheel
	return { slip = slip, slide = slide }
end

-- The highest smoke share any wheel reaches over a run, with the game's own thresholds.
local function peakShares(sim: DriveSim.Sim, input, seconds: number): { number }
	local readings: { TyreSmoke.Wheel } = {}
	local peaks = table.create(4, 0)
	local stop = sim.time + seconds
	while sim.time < stop do
		local result = DriveSim.frame(sim, input, DT)
		TyreSmoke.measure(sim.model, result.wheels, readings)
		for index, reading in readings do
			peaks[index] = math.max(peaks[index], TyreSmoke.share(reading, Config.THRESHOLDS))
		end
	end
	return peaks
end

describe("TyreSmoke", function()
	it("needs the patch both past peak grip and sliding fast", function()
		expect(TyreSmoke.share(wheel(0, 0), THRESHOLDS)).toBe(0)
		expect(TyreSmoke.share(wheel(2, 20), THRESHOLDS)).toBe(0)
		expect(TyreSmoke.share(wheel(10, 2), THRESHOLDS)).toBe(0)
		expect(TyreSmoke.share(wheel(4, 10), THRESHOLDS)).toBe(1)
		expect(TyreSmoke.share(wheel(30, 40), THRESHOLDS)).toBe(1)
		-- Halfway along each ramp is half its ease, and the two multiply.
		expect(TyreSmoke.share(wheel(3, 10), THRESHOLDS)).toBeNear(0.5, 1e-12)
		expect(TyreSmoke.share(wheel(3, 6), THRESHOLDS)).toBeNear(0.25, 1e-12)
	end)

	it("grows with slip and with slide, never falling as either rises", function()
		local previous = -1
		for slip = 0, 6, 0.1 do
			local share = TyreSmoke.share(wheel(slip, 8), THRESHOLDS)
			expect(share >= previous).toBe(true)
			previous = share
		end
		previous = -1
		for slide = 0, 15, 0.25 do
			local share = TyreSmoke.share(wheel(5, slide), THRESHOLDS)
			expect(share >= previous).toBe(true)
			previous = share
		end
	end)

	it("makes none on a wet road, all of it on a dry one", function()
		expect(TyreSmoke.dryShare(0, THRESHOLDS)).toBe(1)
		expect(TyreSmoke.dryShare(0.1, THRESHOLDS)).toBe(1)
		expect(TyreSmoke.dryShare(0.2, THRESHOLDS)).toBeNear(0.5, 1e-12)
		expect(TyreSmoke.dryShare(0.3, THRESHOLDS)).toBe(0)
		expect(TyreSmoke.dryShare(1, THRESHOLDS)).toBe(0)
		local rates = TyreSmoke.rates({ wheel(10, 20), wheel(10, 20) }, 0.8, THRESHOLDS, {}, SETTLE, {})
		expect(rates[1]).toBe(0)
		expect(rates[2]).toBe(0)
	end)

	it("gives each wheel its own rate and caps them together", function()
		local rates = TyreSmoke.rates(
			{ wheel(0, 0), wheel(3, 10), wheel(10, 20), wheel(10, 20) },
			0,
			THRESHOLDS,
			{},
			SETTLE,
			{}
		)
		expect(rates[1]).toBe(0)
		expect(rates[2]).toBeNear(10, 1e-9)
		expect(rates[3]).toBeNear(20, 1e-9)
		local capped = TyreSmoke.rates(table.create(4, wheel(10, 20)), 0, THRESHOLDS, {}, SETTLE, {})
		local total = 0
		for _, rate in capped do
			expect(rate).toBeNear(12.5, 1e-9)
			total += rate
		end
		expect(total).toBeNear(50, 1e-9)
	end)

	it("builds with the tread's heat and dies as it cools, at any frame rate", function()
		expect(TyreSmoke.follow(0, 1, 0.1, THRESHOLDS)).toBeNear(0.5, 1e-12)
		expect(TyreSmoke.follow(1, 0, 0.4, THRESHOLDS)).toBeNear(0.5, 1e-12)
		local stepped = 0
		for _ = 1, 6 do
			stepped = TyreSmoke.follow(stepped, 1, 0.1 / 6, THRESHOLDS)
		end
		expect(stepped).toBeNear(0.5, 1e-12)
		-- A one-frame spike in the slip barely smokes; a held slide reaches full smoke.
		local heats = {}
		local spike = TyreSmoke.rates({ wheel(10, 20) }, 0, THRESHOLDS, heats, 1 / 60, {})
		expect(spike[1] < 0.15 * THRESHOLDS.rate).toBe(true)
		local held = TyreSmoke.rates({ wheel(10, 20) }, 0, THRESHOLDS, heats, SETTLE, {})
		expect(held[1]).toBe(THRESHOLDS.rate)
		-- Cooled, it rests at exactly nothing.
		local cooled = TyreSmoke.rates({ wheel(0, 0) }, 0, THRESHOLDS, heats, SETTLE, {})
		expect(cooled[1]).toBe(0)
		expect(TyreSmoke.follow(0.3, 1, 0, THRESHOLDS)).toBe(0.3)
		expect(TyreSmoke.follow(0.3, 1, 0 / 0, THRESHOLDS)).toBe(0.3)
	end)

	it("measures how fast the patch slides, along and across the wheel", function()
		expect(TyreSmoke.slideSpeed(30, 30, 0)).toBe(0)
		expect(TyreSmoke.slideSpeed(30, 0, 0)).toBe(30)
		expect(TyreSmoke.slideSpeed(0, 27, 0)).toBe(27)
		expect(TyreSmoke.slideSpeed(20, 20, -5)).toBe(5)
		expect(TyreSmoke.slideSpeed(13, 10, 4)).toBeNear(5, 1e-12)
		expect(TyreSmoke.throwSpeed(10, { share = 0.2, min = 0.3, max = 3 })).toBeNear(2, 1e-12)
		expect(TyreSmoke.throwSpeed(0, { share = 0.2, min = 0.3, max = 3 })).toBe(0.3)
		expect(TyreSmoke.throwSpeed(50, { share = 0.2, min = 0.3, max = 3 })).toBe(3)
	end)

	it("reads nonsense as no smoke, never as an error", function()
		for _, odd in { 0 / 0, math.huge, -math.huge } do
			expect(TyreSmoke.share(wheel(odd, 10), THRESHOLDS)).toBe(0)
			expect(TyreSmoke.share(wheel(5, odd), THRESHOLDS)).toBe(0)
			expect(TyreSmoke.dryShare(odd, THRESHOLDS)).toBe(1)
			expect(TyreSmoke.slideSpeed(odd, odd, odd)).toBe(0)
		end
	end)
end)

-- The highest total particles a second the emitters are set to over a run, the tread's heat
-- included, with the game's own thresholds on a dry road.
local function peakRate(sim: DriveSim.Sim, input, seconds: number): number
	local readings: { TyreSmoke.Wheel } = {}
	local heats, rates = {}, {}
	local peak = 0
	local stop = sim.time + seconds
	while sim.time < stop do
		local result = DriveSim.frame(sim, input, DT)
		TyreSmoke.measure(sim.model, result.wheels, readings)
		local total = 0
		for _, rate in TyreSmoke.rates(readings, 0, Config.THRESHOLDS, heats, DT, rates) do
			total += rate
		end
		peak = math.max(peak, total)
	end
	return peak
end

describe("TyreSmoke on the SVJ's physics", function()
	it("makes none cruising at 100 km/h", function()
		local sim = DriveSim.new(SVJ)
		DriveSim.setSpeed(sim, 100 * KMH, 4)
		for _, share in peakShares(sim, DriveSim.input({ throttle = 0.25 }), 3) do
			expect(share).toBe(0)
		end
	end)

	it("makes almost none in an ABS stop from 150 km/h", function()
		local sim = DriveSim.new(SVJ)
		DriveSim.setSpeed(sim, 150 * KMH, 5)
		for _, share in peakShares(sim, DriveSim.input({ brake = 1 }), 4) do
			expect(share < 0.1).toBe(true)
		end
	end)

	it("makes almost none launching on traction control", function()
		for _, mode in { "Strada", "Corsa" } do
			local sim = DriveSim.new(SVJ)
			local hold = DriveSim.input({ throttle = 1, brake = 1, drivingMode = mode })
			while sim.time < 1.5 do
				DriveSim.frame(sim, hold, DT)
			end
			for _, share in peakShares(sim, DriveSim.input({ throttle = 1, drivingMode = mode }), 3) do
				expect(share < 0.1).toBe(true)
			end
		end
	end)

	it("smokes the rear tyres in full when the handbrake locks them at 80 km/h", function()
		local sim = DriveSim.new(SVJ)
		DriveSim.setSpeed(sim, 80 * KMH, 3)
		local peaks = peakShares(sim, DriveSim.input({ handbrake = 1 }), 1)
		expect(peaks[1]).toBe(0)
		expect(peaks[2]).toBe(0)
		expect(peaks[3] > 0.95).toBe(true)
		expect(peaks[4] > 0.95).toBe(true)
	end)

	it("smokes the rear tyres spinning up from a standstill without traction control", function()
		local sim = DriveSim.new(SVJ)
		local peaks = peakShares(sim, DriveSim.input({ throttle = 1, tc = false }), 1)
		expect(peaks[3] > 0.9).toBe(true)
		expect(peaks[4] > 0.9).toBe(true)
	end)

	it("reads no slide from a wheel off the ground, however fast it spins", function()
		local sim = DriveSim.new(SVJ)
		local spin = DriveSim.input({ throttle = 1, tc = false })
		local result = DriveSim.frame(sim, spin, DT)
		for _ = 1, 20 do
			result = DriveSim.frame(sim, spin, DT)
		end
		sim.model.grounded[3] = false
		local readings = TyreSmoke.measure(sim.model, result.wheels, {})
		expect(readings[3].slide).toBe(0)
		expect(readings[4].slide > Config.THRESHOLDS.slide.from).toBe(true)
	end)
end)

-- The DR458's slicks peak at a smaller slip than the SVJ's road tyres (Config/Cars/DR458/Physics),
-- so the same thresholds are checked on its own physics: its manettino's 2 and 1 keep traction
-- control, OFF drops it.
describe("TyreSmoke on the DR458's physics", function()
	it("makes none cruising at 100 km/h", function()
		local sim = DriveSim.new(DR458)
		DriveSim.setSpeed(sim, 100 * KMH, 4)
		for _, share in peakShares(sim, DriveSim.input({ throttle = 0.25, drivingMode = "1" }), 3) do
			expect(share).toBe(0)
		end
	end)

	-- Its fronts reach a share of 0.13 for an instant as the brakes bite in positions 1 and OFF (the
	-- car's own ABS calibration; position 2's tighter one stays near 0.01), so this is judged on what
	-- the emitters are set to after the tread's heat: what the player sees.
	it(
		"emits under one puff a second at any moment of an ABS stop from 150 km/h, in every position",
		function()
			for _, mode in { "1", "2", "OFF" } do
				local sim = DriveSim.new(DR458)
				DriveSim.setSpeed(sim, 150 * KMH, 5)
				expect(peakRate(sim, DriveSim.input({ brake = 1, drivingMode = mode }), 4) < 1).toBe(true)
			end
		end
	)

	it("makes almost none launching on traction control in positions 2 and 1", function()
		for _, mode in { "2", "1" } do
			local sim = DriveSim.new(DR458)
			local hold = DriveSim.input({ throttle = 1, brake = 1, drivingMode = mode })
			while sim.time < 1.5 do
				DriveSim.frame(sim, hold, DT)
			end
			for _, share in peakShares(sim, DriveSim.input({ throttle = 1, drivingMode = mode }), 3) do
				expect(share < 0.1).toBe(true)
			end
		end
	end)

	it("smokes all four slicks in full locked at 150 km/h without ABS", function()
		local sim = DriveSim.new(DR458)
		DriveSim.setSpeed(sim, 150 * KMH, 5)
		for _, share in peakShares(sim, DriveSim.input({ brake = 1, abs = false, drivingMode = "OFF" }), 2) do
			expect(share > 0.95).toBe(true)
		end
	end)

	it("smokes the rear slicks spinning up in OFF without traction control, the fronts not at all", function()
		local sim = DriveSim.new(DR458)
		local peaks = peakShares(sim, DriveSim.input({ throttle = 1, tc = false, drivingMode = "OFF" }), 1)
		expect(peaks[1]).toBe(0)
		expect(peaks[2]).toBe(0)
		expect(peaks[3] > 0.9).toBe(true)
		expect(peaks[4] > 0.9).toBe(true)
	end)
end)
