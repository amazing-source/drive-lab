--!strict
local T = require("../../../tools/test/T")
local Driveline = require("../src/shared/Vehicle/Driveline")
local Engine = require("../src/shared/Vehicle/Engine")
local SVJ = require("../src/shared/Config/Cars/SVJ/Physics")
local Tyre = require("../src/shared/Vehicle/Tyre")

local describe, it, expect = T.describe, T.it, T.expect

local drive = Driveline.prepare(SVJ, SVJ.engine.inertia)
local RPM = Engine.RAD_PER_RPM
local FRONT_TYRE = Tyre.prepare(SVJ.front.tyre, 400)
local REAR_TYRE = Tyre.prepare(SVJ.rear.tyre, 470)

local function tyreStates(): { Tyre.TyreState }
	local list = table.create(4)
	for wheel = 1, 4 do
		list[wheel] = Tyre.newState()
	end
	return list
end

-- Steps the driveline with the car held still (every patch's ground speed is zero), so the
-- tyres alone resist the wheels. Returns rear-left spin after each step.
local function heldLaunch(engineTorque: number, dt: number, steps: number, sweeps: number): { number }
	local wheels = tyreStates()
	local state = Driveline.newState(0)
	local loads = Driveline.newLoads()
	loads.ratio = SVJ.gearbox.ratios[1]
	loads.clutchCapacity = 1e4
	loads.engineTorque = engineTorque
	local spins = table.create(steps, 0)
	for step = 1, steps do
		for wheel = 1, 4 do
			local tyre = if wheel <= 2 then FRONT_TYRE else REAR_TYRE
			Tyre.setLoad(tyre, wheels[wheel], if wheel <= 2 then 3900 else 5150, 1)
			Tyre.prepareSubstep(
				tyre,
				wheels[wheel],
				0,
				0,
				Driveline.wheelSpeed(drive, state, wheel),
				SVJ.simulation,
				dt
			)
		end
		Driveline.solve(drive, state, loads, wheels, sweeps, dt)
		for wheel = 1, 4 do
			local tyre = if wheel <= 2 then FRONT_TYRE else REAR_TYRE
			Tyre.finishSubstep(
				tyre,
				wheels[wheel],
				0,
				Driveline.wheelSpeed(drive, state, wheel),
				SVJ.simulation,
				dt
			)
		end
		spins[step] = Driveline.wheelSpeed(drive, state, 3)
	end
	return spins
end

describe("Driveline wheel spin", function()
	it("is implicit: whole 33 ms steps from standstill settle monotonically on a gripping tyre", function()
		-- 250 N·m through first gear is within the rear tyres' grip, so the wheels wind the
		-- patch up and stop. Over one 1/30 s step the tyre's stiffness is ~50 times the wheel's
		-- inertia: an explicit update rings or diverges, a backward-Euler one decays without
		-- overshoot. The model itself never steps more than 1 ms; this isolates the method,
		-- with enough sweeps for Gauss-Seidel to converge inside one long step.
		local spins = heldLaunch(250, 1 / 30, 30, 64)
		for step = 2, #spins do
			expect(spins[step] >= 0).toBeTruthy()
			expect(spins[step] <= spins[step - 1] + 1e-12).toBeTruthy()
		end
		expect(spins[#spins] < 1e-3).toBeTruthy()
	end)

	it("settles the same at 1 ms with the model's four sweeps, carrying the drive torque", function()
		local spins = heldLaunch(250, 0.001, 300, SVJ.simulation.solverIterations)
		expect(math.abs(spins[#spins]) < 1e-4).toBeTruthy()
	end)

	it("spins the wheels up when the torque beats the grip", function()
		local spins = heldLaunch(720, 0.001, 300, SVJ.simulation.solverIterations)
		expect(spins[300] > spins[100] and spins[100] > 1).toBeTruthy()
	end)

	it("lets a brake stop a wheel but never reverse it in one step", function()
		local state = Driveline.newState(0)
		state.speeds[2] = 0.5 * SVJ.driveline.rearReduction / SVJ.rear.tyre.radius
		state.speeds[4] = 0.5 * SVJ.driveline.frontReduction / SVJ.front.tyre.radius
		local loads = Driveline.newLoads()
		for wheel = 1, 4 do
			loads.brakeCapacity[wheel] = 1e6
		end
		Driveline.solve(drive, state, loads, tyreStates(), 4, 1 / 30)
		for wheel = 1, 4 do
			local spin = Driveline.wheelSpeed(drive, state, wheel)
			expect(spin >= 0 and spin < 1e-6).toBeTruthy()
		end
	end)

	it("lets a weak brake slow a wheel by exactly its torque", function()
		local state = Driveline.newState(0)
		state.speeds[5] = 10
		local loads = Driveline.newLoads()
		loads.brakeCapacity[1] = 30
		Driveline.solve(drive, state, loads, tyreStates(), 4, 0.001)
		local mobility = drive.gains[1] ^ 2 / drive.frontInertia + 1 / drive.frontDiffInertia
		expect(Driveline.wheelSpeed(drive, state, 1)).toBeNear(10 - 0.001 * 30 * mobility, 1e-9)
	end)

	it("lets engine drag stop the crank but never spin it backwards", function()
		local state = Driveline.newState(50)
		local loads = Driveline.newLoads()
		loads.engineDrag = 1e5
		Driveline.solve(drive, state, loads, tyreStates(), 4, 0.001)
		expect(state.speeds[1]).toBeNear(0, 1e-9)
	end)
end)

describe("Driveline friction elements", function()
	it("locks a clutch that can carry the torque: engine speed = ratio × output speed", function()
		local state = Driveline.newState(3000 * RPM)
		state.speeds[2] = 3000 * RPM / SVJ.gearbox.ratios[2]
		local loads = Driveline.newLoads()
		loads.ratio = SVJ.gearbox.ratios[2]
		loads.clutchCapacity = 1000
		loads.engineTorque = 400
		for _ = 1, 50 do
			Driveline.solve(drive, state, loads, tyreStates(), 4, 0.001)
		end
		expect(state.speeds[1]).toBeNear(loads.ratio * state.speeds[2], 1e-6)
		expect(state.clutchTorque > 0 and state.clutchTorque < 400).toBeTruthy()
	end)

	it("slips a clutch that cannot carry the torque, passing exactly its capacity", function()
		local state = Driveline.newState(5000 * RPM)
		local loads = Driveline.newLoads()
		loads.ratio = SVJ.gearbox.ratios[1]
		loads.clutchCapacity = 300
		Driveline.solve(drive, state, loads, tyreStates(), 4, 0.001)
		expect(state.clutchTorque).toBeNear(300, 1e-6)
		expect(state.speeds[1] > loads.ratio * state.speeds[2]).toBeTruthy()
	end)

	it("slips the LSD at exactly its capacity when the rear wheels differ", function()
		local state = Driveline.newState(0)
		state.speeds[3] = 2
		local loads = Driveline.newLoads()
		loads.lsdCapacity = Driveline.lsdCapacity(SVJ.driveline, SVJ.modes.Strada, 0)
		Driveline.solve(drive, state, loads, tyreStates(), 4, 0.001)
		local expected = 2 - 0.001 * SVJ.driveline.lsdPreload / drive.rearDiffInertia
		expect(state.speeds[3]).toBeNear(expected, 1e-9)
	end)

	it("locks the LSD when the difference is within what it can hold", function()
		local state = Driveline.newState(0)
		state.speeds[3] = 0.01
		local loads = Driveline.newLoads()
		loads.lsdCapacity = Driveline.lsdCapacity(SVJ.driveline, SVJ.modes.Strada, 0)
		Driveline.solve(drive, state, loads, tyreStates(), 4, 0.001)
		expect(state.speeds[3]).toBeNear(0, 1e-12)
	end)

	it("ramps the LSD's locking with power and coast torque (02 §2.5: 25 % / 45 %)", function()
		local config = SVJ.driveline
		local mode = SVJ.modes.Strada
		expect(Driveline.lsdCapacity(config, mode, 1000)).toBeNear(config.lsdPreload + 250, 1e-9)
		expect(Driveline.lsdCapacity(config, mode, -1000)).toBeNear(config.lsdPreload + 450, 1e-9)
	end)

	it("ramps the LSD with the mode's own ramps where the mode sets them, as an E-Diff map", function()
		local config = SVJ.driveline
		local locked = table.clone(SVJ.modes.Strada)
		locked.lsdPowerRamp = 0.6
		locked.lsdCoastRamp = 0.8
		expect(Driveline.lsdCapacity(config, locked, 1000)).toBeNear(config.lsdPreload + 600, 1e-9)
		expect(Driveline.lsdCapacity(config, locked, -1000)).toBeNear(config.lsdPreload + 800, 1e-9)
	end)

	it("sends forward at most the mode's share of the gearbox output", function()
		expect(Driveline.couplingCapacity(SVJ.modes.Sport, 2000, true)).toBeNear(140, 1e-9)
		expect(Driveline.couplingCapacity(SVJ.modes.Sport, -2000, false)).toBe(0)
		expect(Driveline.couplingCapacity(SVJ.modes.Strada, 2000, true)).toBeNear(800, 1e-9)
	end)

	it("lets the open front differential split speed freely", function()
		local state = Driveline.newState(0)
		state.speeds[5] = 3
		Driveline.solve(drive, state, Driveline.newLoads(), tyreStates(), 4, 0.001)
		expect(Driveline.wheelSpeed(drive, state, 1)).toBeNear(3, 1e-12)
		expect(Driveline.wheelSpeed(drive, state, 2)).toBeNear(-3, 1e-12)
	end)
end)
