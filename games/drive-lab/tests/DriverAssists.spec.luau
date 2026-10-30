--!strict
local Config = require("../src/shared/Config/Cars/SVJ/Assists")
local DriveSim = require("../tools/DriveSim")
local DriverAssists = require("../src/shared/Rules/DriverAssists")
local Electronics = require("../src/shared/Vehicle/Electronics")
local Interface = require("../src/shared/Vehicle/Interface")
local SVJ = require("../src/shared/Config/Cars/SVJ/Physics")
local T = require("../../../tools/test/T")
local TyreSmoke = require("../src/shared/Rules/TyreSmoke")
local TyreSmokeConfig = require("../src/shared/Config/TyreSmoke")
local Types = require("../src/shared/Config/Cars/Types")

local describe, it, expect = T.describe, T.it, T.expect

local DT = 1 / 60
local KMH = 1 / 3.6
local TUNING: DriverAssists.Tuning = {
	offHoldSeconds = 3,
	on = { abs = true, tc = true, esc = true },
	off = { abs = true, tc = false, esc = false },
	lampFlashHz = 2,
}
local MODES: { Types.DrivingMode } = { "Strada", "Sport", "Corsa" }

local function input(options: DriveSim.InputOptions, assists: Interface.Assists): DriveSim.InputOptions
	options.abs, options.tc, options.esc = assists.abs, assists.tc, assists.esc
	return options
end

-- The most smoke either rear tyre makes in 3 s of full throttle from rest, with the game's own
-- thresholds; with `launchControl`, after 1.5 s held on the brake at full throttle first.
local function launchSmoke(mode: Types.DrivingMode, escOff: boolean, launchControl: boolean): number
	local assists = DriverAssists.assists(escOff, Config)
	local sim = DriveSim.new(SVJ)
	if launchControl then
		local hold = DriveSim.input(input({ throttle = 1, brake = 1, drivingMode = mode }, assists))
		while sim.time < 1.5 do
			DriveSim.frame(sim, hold, DT)
		end
	end
	local go = DriveSim.input(input({ throttle = 1, drivingMode = mode }, assists))
	local readings: { TyreSmoke.Wheel } = {}
	local peak = 0
	local stop = sim.time + 3
	while sim.time < stop do
		local result = DriveSim.frame(sim, go, DT)
		TyreSmoke.measure(sim.model, result.wheels, readings)
		for wheel = 3, 4 do
			peak = math.max(peak, TyreSmoke.share(readings[wheel], TyreSmokeConfig.THRESHOLDS))
		end
	end
	return peak
end

export type Stop = { distance: number, absActed: boolean, leastRolling: number }

-- Full brake from 100 km/h in Strada. `leastRolling` is the lowest share of its ground speed any
-- wheel's tread kept above 5 m/s: 0 is a locked wheel.
local function brakeFrom100(escOff: boolean): Stop
	local assists = DriverAssists.assists(escOff, Config)
	local sim = DriveSim.new(SVJ)
	DriveSim.setSpeed(sim, 100 * KMH, 3)
	local coast = DriveSim.input(input({ drivingMode = "Strada" }, assists))
	while sim.time < 0.5 do
		DriveSim.frame(sim, coast, DT)
	end
	local brake = DriveSim.input(input({ brake = 1, drivingMode = "Strada" }, assists))
	local startX = sim.body.x
	local result: Stop = { distance = 0, absActed = false, leastRolling = 1 }
	while DriveSim.forwardSpeed(sim) > 0.05 and sim.time < 10 do
		local step = DriveSim.frame(sim, brake, DT)
		result.absActed = result.absActed or step.telemetry.absActive
		local model = sim.model
		for wheel = 1, 4 do
			local ground = model.ground[wheel]
			if ground > 5 then
				local rolling = model.spins[wheel] * model.tyres[wheel].radius / ground
				result.leastRolling = math.min(result.leastRolling, rolling)
			end
		end
	end
	result.distance = sim.body.x - startX
	return result
end

describe("The ESC control", function()
	it("switches ESC off only once held for the hold time", function()
		local switch = DriverAssists.newSwitch()
		expect(DriverAssists.updateSwitch(switch, true, 10, TUNING)).toBe(false)
		expect(DriverAssists.updateSwitch(switch, true, 12.9, TUNING)).toBe(false)
		expect(switch.off).toBe(false)
		expect(DriverAssists.updateSwitch(switch, true, 13, TUNING)).toBe(true)
		expect(switch.off).toBe(true)
	end)

	it("never switches ESC off on taps, however many", function()
		local switch = DriverAssists.newSwitch()
		for tap = 0, 20 do
			DriverAssists.updateSwitch(switch, true, tap, TUNING)
			DriverAssists.updateSwitch(switch, true, tap + 0.5, TUNING)
			DriverAssists.updateSwitch(switch, false, tap + 0.6, TUNING)
		end
		expect(switch.off).toBe(false)
	end)

	it("switches once per hold, and back on at once with the next press", function()
		local switch = DriverAssists.newSwitch()
		DriverAssists.updateSwitch(switch, true, 0, TUNING)
		DriverAssists.updateSwitch(switch, true, 3, TUNING)
		expect(DriverAssists.updateSwitch(switch, true, 9, TUNING)).toBe(false)
		expect(switch.off).toBe(true)
		DriverAssists.updateSwitch(switch, false, 9.5, TUNING)
		expect(DriverAssists.updateSwitch(switch, true, 10, TUNING)).toBe(true)
		expect(switch.off).toBe(false)
		-- The press that switched it back on, held on, does not switch it off again.
		expect(DriverAssists.updateSwitch(switch, true, 20, TUNING)).toBe(false)
		expect(switch.off).toBe(false)
		DriverAssists.updateSwitch(switch, false, 21, TUNING)
		DriverAssists.updateSwitch(switch, true, 22, TUNING)
		DriverAssists.updateSwitch(switch, true, 25, TUNING)
		expect(switch.off).toBe(true)
	end)

	it("takes traction and stability control when off, and leaves ABS", function()
		local on = DriverAssists.assists(false, Config)
		expect(on.abs).toBe(true)
		expect(on.tc).toBe(true)
		expect(on.esc).toBe(true)
		local off = DriverAssists.assists(true, Config)
		expect(off.abs).toBe(true)
		expect(off.tc).toBe(false)
		expect(off.esc).toBe(false)
	end)
end)

describe("The assist tell-tales", function()
	it("read ready, acting, or off when switched off whatever the system reports", function()
		expect(DriverAssists.telltale(true, false)).toBe("Ready")
		expect(DriverAssists.telltale(true, true)).toBe("Acting")
		expect(DriverAssists.telltale(false, false)).toBe("Off")
		expect(DriverAssists.telltale(false, true)).toBe("Off")
	end)

	it("light the cluster's ESC OFF steadily, and flash its ESC light only while ESC acts", function()
		for _, now in { 0, 0.3, 0.26, 0.9 } do
			expect(DriverAssists.escLamp(true, false, now, TUNING)).toBe("EscOff")
			expect(DriverAssists.escLamp(true, true, now, TUNING)).toBe("EscOff")
			expect(DriverAssists.escLamp(false, false, now, TUNING)).toBe("Hidden")
		end
		-- 2 Hz: lit for the first quarter second of each half second.
		expect(DriverAssists.escLamp(false, true, 0.1, TUNING)).toBe("Esc")
		expect(DriverAssists.escLamp(false, true, 0.3, TUNING)).toBe("Hidden")
		expect(DriverAssists.escLamp(false, true, 0.6, TUNING)).toBe("Esc")
	end)
end)

describe("The drive modes' assists", function()
	local function escActs(mode: Types.DrivingMode, yawExcess: number, sideslipDegrees: number): boolean
		local steer = 0.02
		local motion: Electronics.Motion = {
			forwardSpeed = 25,
			rightSpeed = 0,
			yawRate = 0,
			frontSteer = steer,
			rearSteer = 0,
			grip = 1,
		}
		motion.yawRate = Electronics.referenceYawRate(SVJ, motion) + yawExcess
		motion.rightSpeed = -25 * math.tan(math.rad(sideslipDegrees))
		local state = Electronics.newState()
		Electronics.updateEsc(SVJ, SVJ.modes[mode], state, true, motion, 1 / SVJ.electronics.escRate)
		return state.escActive
	end

	it("let Sport carry a slide Corsa corrects, and Corsa one Strada corrects", function()
		expect(escActs("Sport", 0.2, 10)).toBe(false)
		expect(escActs("Corsa", 0.2, 10)).toBe(true)
		expect(escActs("Corsa", 0.1, 6)).toBe(false)
		expect(escActs("Strada", 0.1, 6)).toBe(true)
	end)

	it("give Sport the slackest traction control, then Corsa, then Strada", function()
		local modes = SVJ.modes
		expect(modes.Sport.tcSlipRatio > modes.Corsa.tcSlipRatio).toBe(true)
		expect(modes.Corsa.tcSlipRatio > modes.Strada.tcSlipRatio).toBe(true)
	end)
end)

describe("ESC off on the SVJ's physics", function()
	it("smokes the rear tyres on a full-throttle launch in every mode, bar Corsa's launch control", function()
		for _, mode: Types.DrivingMode in MODES do
			expect(launchSmoke(mode, true, false) > 0.9).toBe(true)
		end
		-- Held on the brake in Corsa with ESC off, the start is launch control (#74), whose traction
		-- control holds the slip: tests/Launch.spec.luau.
		expect(launchSmoke("Strada", true, true) > 0.9).toBe(true)
		expect(launchSmoke("Sport", true, true) > 0.9).toBe(true)
	end)

	it("makes no smoke launching in Strada with ESC on", function()
		expect(launchSmoke("Strada", false, false) < 0.01).toBe(true)
		expect(launchSmoke("Strada", false, true) < 0.01).toBe(true)
	end)

	it("keeps ABS: the stop from 100 km/h is as short and no wheel locks", function()
		local on, off = brakeFrom100(false), brakeFrom100(true)
		expect(off.absActed).toBe(true)
		expect(off.distance).toBeNear(on.distance, 0.3)
		expect(off.leastRolling > 0.5).toBe(true)
	end)
end)
