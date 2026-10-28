--!strict
--[[
	The drivetrain as rotating inertias joined by gears and friction elements (01 §2.3): engine,
	clutch, gearbox, the gearbox output driving the rear differential directly and the front
	axle through a Haldex coupling, a rear limited-slip differential and an open front one.

	Speeds live in five coordinates chosen so the inertia matrix is diagonal: engine, gearbox
	output, rear differential (half the left-right difference), front shaft after the coupling,
	front differential. A wheel's speed is its axle's shaft speed over the reduction plus or
	minus its differential coordinate.

	Each substep is solved at the velocity level, so friction is implicit and can stop a shaft
	but never reverse it (01 §5.3 point 6). The clutch, coupling, LSD, driveline loss and engine
	drag are friction rows whose impulse is bounded by their capacity. Each wheel is one block
	holding its tyre and its brake: the tyre's longitudinal force is linearised in the wheel's
	end speed (implicit in the linear region, 01 §5.3 point 2) and bounded by friction, and the
	brake holds the wheel or slips. Rows are swept with projected Gauss-Seidel, warm-started
	from the previous substep.
]]
local Geometry = require("./Geometry")
local Tyre = require("./Tyre")
local Types = require("../Config/Cars/Types")

local ENGINE, OUTPUT, REAR_DIFF, FRONT, FRONT_DIFF = 1, 2, 3, 4, 5
local SHAFT = { FRONT, FRONT, OUTPUT, OUTPUT }
local DIFFERENTIAL = { FRONT_DIFF, FRONT_DIFF, REAR_DIFF, REAR_DIFF }
local SIDE = { 1, -1, 1, -1 }

export type Driveline = {
	engineInertia: number,
	inputInertia: number,
	outputInertia: number,
	rearDiffInertia: number,
	frontInertia: number,
	frontDiffInertia: number,
	-- Wheel speed per unit of shaft speed, per wheel.
	gains: { number },
	radii: { number },
	rearReduction: number,
	config: Types.DrivelineConfig,
}

export type DrivelineState = {
	speeds: { number },
	inverseMass: { number },
	references: { number },
	tyreImpulse: { number },
	brakeImpulse: { number },
	clutchImpulse: number,
	couplingImpulse: number,
	lsdImpulse: number,
	lossImpulse: number,
	dragImpulse: number,
	-- Torques carried in the last substep (N·m): engine into the gearbox, gearbox output, and
	-- output sent forward through the coupling.
	clutchTorque: number,
	outputTorque: number,
	couplingTorque: number,
}

-- What one substep asks of the driveline. Capacities in N·m; the engine torque drives, the
-- drag capacity resists.
export type Loads = {
	ratio: number,
	engineTorque: number,
	engineDrag: number,
	clutchCapacity: number,
	couplingCapacity: number,
	lsdCapacity: number,
	lossCapacity: number,
	brakeCapacity: { number },
}

local Driveline = {}

function Driveline.prepare(car: Types.CarConfig, engineInertia: number): Driveline
	local config = car.driveline
	local frontWheel, rearWheel = car.front.wheelInertia, car.rear.wheelInertia
	local frontGain, rearGain = 1 / config.frontReduction, 1 / config.rearReduction
	return table.freeze({
		engineInertia = engineInertia,
		inputInertia = car.gearbox.inputInertia,
		outputInertia = config.propshaftInertia + 2 * rearWheel * rearGain * rearGain,
		rearDiffInertia = 2 * rearWheel,
		frontInertia = config.frontShaftInertia + 2 * frontWheel * frontGain * frontGain,
		frontDiffInertia = 2 * frontWheel,
		gains = table.freeze({ frontGain, frontGain, rearGain, rearGain }),
		radii = table.freeze({
			car.front.tyre.radius,
			car.front.tyre.radius,
			car.rear.tyre.radius,
			car.rear.tyre.radius,
		}),
		rearReduction = config.rearReduction,
		config = config,
	})
end

function Driveline.newState(engineSpeed: number): DrivelineState
	return {
		speeds = { engineSpeed, 0, 0, 0, 0 },
		inverseMass = table.create(5, 0),
		references = table.create(Geometry.WHEELS, 0),
		tyreImpulse = table.create(Geometry.WHEELS, 0),
		brakeImpulse = table.create(Geometry.WHEELS, 0),
		clutchImpulse = 0,
		couplingImpulse = 0,
		lsdImpulse = 0,
		lossImpulse = 0,
		dragImpulse = 0,
		clutchTorque = 0,
		outputTorque = 0,
		couplingTorque = 0,
	}
end

function Driveline.newLoads(): Loads
	return {
		ratio = 0,
		engineTorque = 0,
		engineDrag = 0,
		clutchCapacity = 0,
		couplingCapacity = 0,
		lsdCapacity = 0,
		lossCapacity = 0,
		brakeCapacity = table.create(Geometry.WHEELS, 0),
	}
end

function Driveline.wheelSpeed(drive: Driveline, state: DrivelineState, wheel: number): number
	local speeds = state.speeds
	return speeds[SHAFT[wheel]] * drive.gains[wheel] + speeds[DIFFERENTIAL[wheel]] * SIDE[wheel]
end

-- Rear LSD locking torque (the difference it can hold between the half-shafts) from the torque
-- entering the rear differential: preload plus a power or coast ramp.
function Driveline.lsdCapacity(config: Types.DrivelineConfig, inputTorque: number): number
	local ramp = if inputTorque >= 0 then config.lsdPowerRamp else config.lsdCoastRamp
	return config.lsdPreload + ramp * math.abs(inputTorque)
end

-- Haldex controller: the coupling may send forward at most the mode's share of the gearbox
-- output, a drive share while the engine pulls and a coast share while it brakes.
function Driveline.couplingCapacity(mode: Types.ModeConfig, outputTorque: number, driving: boolean): number
	local share = if driving then mode.frontShareDrive else mode.frontShareCoast
	return share * math.abs(outputTorque)
end

local function applyToWheel(state: DrivelineState, drive: Driveline, wheel: number, impulse: number)
	local speeds, inverse = state.speeds, state.inverseMass
	local shaft, differential = SHAFT[wheel], DIFFERENTIAL[wheel]
	speeds[shaft] += drive.gains[wheel] * impulse * inverse[shaft]
	speeds[differential] += SIDE[wheel] * impulse * inverse[differential]
end

-- One wheel's tyre and brake together, exactly: the brake holds the wheel if it can, else it
-- slips at full capacity and the tyre's linearised force settles the speed.
local function solveWheel(
	drive: Driveline,
	state: DrivelineState,
	tyre: Tyre.TyreState,
	wheel: number,
	brakeCapacity: number,
	dt: number
)
	local inverse = state.inverseMass
	local gain = drive.gains[wheel]
	local mobility = gain * gain * inverse[SHAFT[wheel]] + inverse[DIFFERENTIAL[wheel]]
	local radius = drive.radii[wheel]
	local oldTyre, oldBrake = state.tyreImpulse[wheel], state.brakeImpulse[wheel]
	local free = Driveline.wheelSpeed(drive, state, wheel) - mobility * (oldTyre + oldBrake)
	local damping = dt * radius * tyre.stiffness
	local base = -dt * radius * tyre.forceX + damping * state.references[wheel]
	local limit = dt * radius * tyre.limitX
	local brake = dt * brakeCapacity

	local newTyre = math.clamp(base, -limit, limit)
	local newBrake = -free / mobility - newTyre
	if newBrake > brake or newBrake < -brake then
		newBrake = if newBrake > 0 then brake else -brake
		local speed = (free + mobility * (base + newBrake)) / (1 + mobility * damping)
		newTyre = math.clamp(base - damping * speed, -limit, limit)
	end
	applyToWheel(state, drive, wheel, newTyre + newBrake - oldTyre - oldBrake)
	state.tyreImpulse[wheel], state.brakeImpulse[wheel] = newTyre, newBrake
end

-- A friction row between coordinates `a` and `b` (b = 0 means the ground), with `factor`
-- scaling b's speed: drives a·1 − b·factor toward zero with an impulse within ±bound.
local function solveFriction(
	state: DrivelineState,
	a: number,
	b: number,
	factor: number,
	impulse: number,
	bound: number
): number
	local speeds, inverse = state.speeds, state.inverseMass
	local relative = speeds[a]
	local mobility = inverse[a]
	if b > 0 then
		relative -= factor * speeds[b]
		mobility += factor * factor * inverse[b]
	end
	local updated = math.clamp(impulse - relative / mobility, -bound, bound)
	local delta = updated - impulse
	speeds[a] += delta * inverse[a]
	if b > 0 then
		speeds[b] -= factor * delta * inverse[b]
	end
	return updated
end

local function applyFriction(state: DrivelineState, a: number, b: number, factor: number, impulse: number)
	local speeds, inverse = state.speeds, state.inverseMass
	speeds[a] += impulse * inverse[a]
	if b > 0 then
		speeds[b] -= factor * impulse * inverse[b]
	end
end

local function warmStart(
	state: DrivelineState,
	drive: Driveline,
	loads: Loads,
	tyres: { Tyre.TyreState },
	dt: number
)
	local ratio = loads.ratio
	for wheel = 1, Geometry.WHEELS do
		local limit = dt * drive.radii[wheel] * tyres[wheel].limitX
		local brake = dt * loads.brakeCapacity[wheel]
		state.tyreImpulse[wheel] = math.clamp(state.tyreImpulse[wheel], -limit, limit)
		state.brakeImpulse[wheel] = math.clamp(state.brakeImpulse[wheel], -brake, brake)
		applyToWheel(state, drive, wheel, state.tyreImpulse[wheel] + state.brakeImpulse[wheel])
	end
	local clutch = if ratio ~= 0 then dt * loads.clutchCapacity else 0
	state.clutchImpulse = math.clamp(state.clutchImpulse, -clutch, clutch)
	state.couplingImpulse =
		math.clamp(state.couplingImpulse, -dt * loads.couplingCapacity, dt * loads.couplingCapacity)
	state.lsdImpulse = math.clamp(state.lsdImpulse, -dt * loads.lsdCapacity, dt * loads.lsdCapacity)
	state.lossImpulse = math.clamp(state.lossImpulse, -dt * loads.lossCapacity, dt * loads.lossCapacity)
	state.dragImpulse = math.clamp(state.dragImpulse, -dt * loads.engineDrag, dt * loads.engineDrag)
	applyFriction(state, ENGINE, OUTPUT, ratio, state.clutchImpulse)
	applyFriction(state, OUTPUT, FRONT, 1, state.couplingImpulse)
	applyFriction(state, REAR_DIFF, 0, 0, state.lsdImpulse)
	applyFriction(state, OUTPUT, 0, 0, state.lossImpulse)
	applyFriction(state, ENGINE, 0, 0, state.dragImpulse)
end

-- Advances every shaft by `dt` under `loads` and the tyres' prepared forces. Afterwards each
-- wheel's tyre force is −tyreImpulse / (dt · radius).
function Driveline.solve(
	drive: Driveline,
	state: DrivelineState,
	loads: Loads,
	tyres: { Tyre.TyreState },
	iterations: number,
	dt: number
)
	local ratio = loads.ratio
	local inverse = state.inverseMass
	inverse[ENGINE] = 1 / drive.engineInertia
	inverse[OUTPUT] = 1 / (drive.outputInertia + drive.inputInertia * ratio * ratio)
	inverse[REAR_DIFF] = 1 / drive.rearDiffInertia
	inverse[FRONT] = 1 / drive.frontInertia
	inverse[FRONT_DIFF] = 1 / drive.frontDiffInertia
	for wheel = 1, Geometry.WHEELS do
		state.references[wheel] = Driveline.wheelSpeed(drive, state, wheel)
	end
	state.speeds[ENGINE] += dt * loads.engineTorque * inverse[ENGINE]
	warmStart(state, drive, loads, tyres, dt)

	local clutch = if ratio ~= 0 then dt * loads.clutchCapacity else 0
	local coupling, lsd = dt * loads.couplingCapacity, dt * loads.lsdCapacity
	local loss, drag = dt * loads.lossCapacity, dt * loads.engineDrag
	for _ = 1, iterations do
		for wheel = 1, Geometry.WHEELS do
			solveWheel(drive, state, tyres[wheel], wheel, loads.brakeCapacity[wheel], dt)
		end
		state.lsdImpulse = solveFriction(state, REAR_DIFF, 0, 0, state.lsdImpulse, lsd)
		state.couplingImpulse = solveFriction(state, OUTPUT, FRONT, 1, state.couplingImpulse, coupling)
		state.lossImpulse = solveFriction(state, OUTPUT, 0, 0, state.lossImpulse, loss)
		state.clutchImpulse = solveFriction(state, ENGINE, OUTPUT, ratio, state.clutchImpulse, clutch)
		state.dragImpulse = solveFriction(state, ENGINE, 0, 0, state.dragImpulse, drag)
	end

	state.clutchTorque = -state.clutchImpulse / dt
	state.outputTorque = ratio * state.clutchTorque
	state.couplingTorque = -state.couplingImpulse / dt
end

-- Torque entering the rear differential's carrier in the last substep.
function Driveline.rearInputTorque(drive: Driveline, state: DrivelineState): number
	return (state.outputTorque - state.couplingTorque) * drive.rearReduction
end

function Driveline.tyreForce(drive: Driveline, state: DrivelineState, wheel: number, dt: number): number
	return -state.tyreImpulse[wheel] / (dt * drive.radii[wheel])
end

return table.freeze(Driveline)
