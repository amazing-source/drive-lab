--!strict
--[[
	The DR458's measured behaviour, driven on tools/DriveSim at 60 FPS. Each target names its
	source in docs/research/12_dr458_challenge_evo.md and that note's confidence, or EST where the
	target is ours. The car is never told the answer: these come out of the data and the physics.
]]
local Assists = require("../src/shared/Config/Cars/DR458/Assists")
local DR458 = require("../src/shared/Config/Cars/DR458/Physics")
local DriveSim = require("../tools/DriveSim")
local DriverAssists = require("../src/shared/Rules/DriverAssists")
local T = require("../../../tools/test/T")
local Types = require("../src/shared/Config/Cars/Types")

local describe, it, expect = T.describe, T.it, T.expect

local DT = 1 / 60
local KMH = 1 / 3.6

-- The systems the car runs in `mode`, as the driving client asks for them.
local function inputFor(mode: Types.DrivingMode, options: DriveSim.InputOptions): DriveSim.InputOptions
	local assists = DriverAssists.assists(false, mode, Assists)
	options.drivingMode = mode
	options.abs, options.tc, options.esc = assists.abs, assists.tc, assists.esc
	return options
end

describe("DR458 calibration", function()
	it("runs 7th to 1st at the speeds the road ratios give at 9,000 rpm (12 §1.2, inferred)", function()
		local kmh = { 73.9, 104.5, 139.7, 176.5, 221.1, 271.1, 330.1 }
		local redline = 9000 * 2 * math.pi / 60
		for gear, expected in kmh do
			local ratio = DR458.gearbox.ratios[gear] * DR458.driveline.rearReduction
			expect(redline * DR458.rear.tyre.radius / ratio / KMH).toBeNear(expected, 0.06)
		end
	end)

	it("tops gears 1 to 6 within 1.5 % of their limiter speed (the table has no tyre slip)", function()
		local limiter = DR458.engine.limiterRpm * 2 * math.pi / 60
		for gear = 1, 6 do
			local ratio = DR458.gearbox.ratios[gear] * DR458.driveline.rearReduction
			local theory = limiter * DR458.rear.tyre.radius / ratio
			expect(DriveSim.gearTop(DR458, gear, DT) / theory).toBeNear(1 - 0.0075, 0.0075)
		end
	end)

	it("reaches 100 km/h from a standing start in under 3.4 s (12 §1.10, likely) and over 2.8 s", function()
		local launch = DriveSim.launch(DR458, DT, inputFor("1", {}))
		expect(launch.time100 < 3.4).toBe(true)
		expect(launch.time100 > 2.8).toBe(true)
	end)

	it("stops from 100 km/h in 24.5 m ± 2 with ABS (EST: about 1.6 g on slicks)", function()
		local stop = DriveSim.brake(DR458, 100 * KMH, DT, inputFor("1", {}))
		expect(stop.distance).toBeNear(24.5, 2)
	end)

	it('holds 1.5 g ± 0.05 on a 40 m skidpad (EST, below the documented "up to 1.6G", 12 §1.10)', function()
		expect(DriveSim.skidpad(DR458, 40, DT, "1")).toBeNear(1.5, 0.05)
	end)

	it("tops out drag-limited, short of its 330 km/h gearing ceiling (12 §1.10, inferred)", function()
		local speed, rpm, gear = DriveSim.topSpeed(DR458, 250 * KMH, DT)
		expect(gear).toBe(7)
		expect(speed / KMH < 330).toBe(true)
		expect(rpm < DR458.engine.limiterRpm - DR458.engine.limiterHysteresis).toBe(true)
	end)

	it("rests on flat ground for 30 s without drifting or jittering", function()
		local drift, jitter = DriveSim.rest(DR458, 30, DT)
		expect(drift < 0.002).toBe(true)
		expect(jitter < 0.001).toBe(true)
	end)
end)

describe("DR458 manettino", function()
	-- The fields a position may set (12 §1.9: traction control, the ABS and the E-Diff).
	local INTERVENTION: { [string]: boolean } = {
		tcSlipRatio = true,
		absReleaseSlip = true,
		absReapplySlip = true,
		lsdPowerRamp = true,
		lsdCoastRamp = true,
	}

	local function same(a: unknown, b: unknown): boolean
		if type(a) ~= "table" or type(b) ~= "table" then
			return a == b
		end
		local left, right = a :: { [unknown]: unknown }, b :: { [unknown]: unknown }
		for key, value in left do
			if not same(value, right[key]) then
				return false
			end
		end
		for key in right do
			if left[key] == nil then
				return false
			end
		end
		return true
	end

	-- A position's settings by name.
	local function fields(mode: unknown): { [string]: unknown }
		return mode :: { [string]: unknown }
	end

	it("changes intervention only: every other setting is the same in each position", function()
		local reference = fields(DR458.modes[DR458.modeOrder[1]])
		for _, name in DR458.modeOrder do
			local mode = fields(DR458.modes[name])
			for key, value in reference do
				if not INTERVENTION[key] then
					expect(same(mode[key], value)).toBe(true)
				end
			end
			for key in mode do
				expect(INTERVENTION[key] or reference[key] ~= nil).toBe(true)
			end
		end
	end)

	-- Mean rear slip ratio over 3 s of full throttle from rest.
	local function rearSlip(mode: Types.DrivingMode): number
		local sim = DriveSim.new(DR458)
		local go = DriveSim.input(inputFor(mode, { throttle = 1 }))
		local sum, count = 0, 0
		while sim.time < 3 do
			local result = DriveSim.frame(sim, go, DT)
			for wheel = 3, 4 do
				sum += result.wheels[wheel].slipRatio
				count += 1
			end
		end
		return sum / count
	end

	it("spins the rear tyres in OFF, holds them in 1, and holds them tighter in 2", function()
		local off, one, two = rearSlip("OFF"), rearSlip("1"), rearSlip("2")
		expect(off > 0.5).toBe(true)
		expect(one < 0.1).toBe(true)
		expect(two < one).toBe(true)
	end)

	it("never runs stability control, and has no button to switch it", function()
		expect(Assists.escButton).toBe(nil)
		for _, mode in DR458.modeOrder do
			expect(DriverAssists.assists(false, mode, Assists).esc).toBe(false)
			expect(DriverAssists.assists(true, mode, Assists)).toBe(
				DriverAssists.assists(false, mode, Assists)
			)
		end
		expect(DriverAssists.assists(false, "OFF", Assists).abs).toBe(true)
	end)

	it("has no launch control: brake and full throttle at a standstill never arm one", function()
		expect(DR458.launch).toBe(nil)
		for _, mode in DR458.modeOrder do
			local sim = DriveSim.new(DR458)
			local hold = DriveSim.input(inputFor(mode, { throttle = 1, brake = 1 }))
			local phases: { [string]: boolean } = {}
			while sim.time < 1.5 do
				phases[DriveSim.frame(sim, hold, DT).telemetry.launch] = true
			end
			expect(phases.Armed).toBe(nil)
			expect(phases.Launching).toBe(nil)
		end
	end)
end)
