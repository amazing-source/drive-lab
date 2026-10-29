--!strict
--[[
	ABS, traction control and stability control (01 §2.4), each switchable and each reading
	physical quantities: wheel surface speed against the patch's ground speed, and yaw rate
	against a bicycle-model reference. Each decides at its own rate inside the substep loop,
	so they pulse like the real systems instead of buzzing every substep, and their thresholds
	come from the drive mode.
]]
local Geometry = require("./Geometry")
local Types = require("../Config/Cars/Types")
local World = require("../Config/World")

export type ElectronicsState = {
	absFactor: { number },
	absReleasing: { boolean },
	absClock: number,
	tcFactor: number,
	tcClock: number,
	escBrake: { number },
	escFactor: number,
	escClock: number,
	absActive: boolean,
	tcActive: boolean,
	escActive: boolean,
}

-- Chassis readings ESC works from. Speeds in m/s, angles in rad, positive yaw turns right.
export type Motion = {
	forwardSpeed: number,
	rightSpeed: number,
	yawRate: number,
	frontSteer: number,
	rearSteer: number,
	grip: number,
}

local Electronics = {}

function Electronics.newState(): ElectronicsState
	return {
		absFactor = table.create(Geometry.WHEELS, 1),
		absReleasing = table.create(Geometry.WHEELS, false),
		absClock = 0,
		tcFactor = 1,
		tcClock = 0,
		escBrake = table.create(Geometry.WHEELS, 0),
		escFactor = 1,
		escClock = 0,
		absActive = false,
		tcActive = false,
		escActive = false,
	}
end

-- Advances a system's clock; true when it is due to decide.
local function due(clock: number, rate: number): (boolean, number)
	local period = 1 / rate
	if clock >= period then
		return true, clock - period
	end
	return false, clock
end

-- `surface` is each wheel's spin times its radius and `ground` its patch's forward speed.
-- Braking slip is negative whichever way the car moves.
function Electronics.updateAbs(
	config: Types.ElectronicsConfig,
	state: ElectronicsState,
	enabled: boolean,
	braking: boolean,
	surface: { number },
	ground: { number },
	dt: number
)
	local decide
	decide, state.absClock = due(state.absClock + dt, config.absRate)
	local active = false
	for wheel = 1, Geometry.WHEELS do
		local speed = math.abs(ground[wheel])
		if not (enabled and braking) or speed < config.absMinSpeed then
			state.absReleasing[wheel] = false
			state.absFactor[wheel] = 1
			continue
		end
		if decide then
			local slip = (surface[wheel] - ground[wheel]) / ground[wheel]
			if slip < -config.absReleaseSlip then
				state.absReleasing[wheel] = true
			elseif slip > -config.absReapplySlip then
				state.absReleasing[wheel] = false
			end
		end
		local factor = state.absFactor[wheel]
		factor = if state.absReleasing[wheel]
			then factor - dt / config.absReleaseTime
			else factor + dt / config.absApplyTime
		factor = math.clamp(factor, 0, 1)
		state.absFactor[wheel] = factor
		active = active or factor < 1
	end
	state.absActive = active
end

-- Torque reduction in two stages: proportional to the slip over `threshold` (the mode's, or a
-- launch's), then a full cut past `tcCutFactor` times it. The speed floor lets a stopped car spin
-- its wheels a little, or it could never move off (01 §2.4 pitfall).
function Electronics.updateTc(
	config: Types.ElectronicsConfig,
	threshold: number,
	state: ElectronicsState,
	enabled: boolean,
	throttle: number,
	surface: { number },
	ground: { number },
	dt: number
)
	local decide
	decide, state.tcClock = due(state.tcClock + dt, config.tcRate)
	if not enabled or throttle <= 0 then
		state.tcFactor = 1
		state.tcActive = false
		return
	end
	if not decide then
		return
	end
	local worst = 0
	for wheel = 1, Geometry.WHEELS do
		local slip = (math.abs(surface[wheel]) - math.abs(ground[wheel]))
			/ math.max(math.abs(ground[wheel]), config.tcSpeedFloor)
		worst = math.max(worst, slip)
	end
	local factor = state.tcFactor
	if worst > threshold * config.tcCutFactor then
		factor = 0
	elseif worst > threshold then
		factor = math.max(0, factor - config.tcGain * (worst - threshold))
	else
		factor = math.min(1, factor + 1 / (config.tcRate * config.tcRecoveryTime))
	end
	state.tcFactor = factor
	state.tcActive = factor < 1
end

-- Yaw rate a neutral-ish car would follow for these road-wheel angles (bicycle model with a
-- characteristic speed), capped by what the tyres can hold: |r| ≤ μ·g / v.
function Electronics.referenceYawRate(car: Types.CarConfig, motion: Motion): number
	local speed = math.abs(motion.forwardSpeed)
	if speed < 1e-3 then
		return 0
	end
	local characteristic = car.electronics.characteristicSpeed
	local ratio = speed / characteristic
	local reference = speed * (motion.frontSteer - motion.rearSteer) / (car.wheelbase * (1 + ratio * ratio))
	local cap = car.front.tyre.peakMuY * motion.grip * World.GRAVITY_MPS2 / speed
	return math.clamp(reference, -cap, cap)
end

-- Oversteer brakes the outer front wheel and trims engine torque; understeer brakes the inner
-- rear. Oversteer counts yaw beyond the reference and body slip beyond the mode's limit.
function Electronics.updateEsc(
	car: Types.CarConfig,
	mode: Types.ModeConfig,
	state: ElectronicsState,
	enabled: boolean,
	motion: Motion,
	dt: number
)
	local decide
	decide, state.escClock = due(state.escClock + dt, car.electronics.escRate)
	if not decide then
		return
	end
	local config = car.electronics
	for wheel = 1, Geometry.WHEELS do
		state.escBrake[wheel] = 0
	end
	state.escFactor = 1
	state.escActive = false
	if not enabled or math.abs(motion.forwardSpeed) < config.escMinSpeed then
		return
	end
	local reference = Electronics.referenceYawRate(car, motion)
	local yaw = motion.yawRate
	local oversteer, understeer = 0, 0
	if yaw * reference >= 0 then
		local excess = math.abs(yaw) - math.abs(reference)
		oversteer = excess - mode.escOversteer
		understeer = -excess - mode.escUndersteer
	else
		oversteer = math.abs(yaw - reference) - mode.escOversteer
	end
	local sideslip = math.atan2(motion.rightSpeed, math.abs(motion.forwardSpeed))
	oversteer = math.max(oversteer, (math.abs(sideslip) - mode.escSideslip) * config.escSideslipGain)

	if oversteer > 0 then
		local turnRight = if math.abs(yaw) > 1e-3 then yaw < 0 else sideslip > 0
		local wheel = if turnRight then Geometry.FRONT_RIGHT else Geometry.FRONT_LEFT
		state.escBrake[wheel] = math.min(config.escMaxBrakeTorque, config.escBrakeGain * oversteer)
		state.escFactor = 1 - math.clamp(oversteer / config.escFullCutError, 0, 1)
		state.escActive = true
	elseif understeer > 0 then
		local wheel = if reference > 0 then Geometry.REAR_RIGHT else Geometry.REAR_LEFT
		state.escBrake[wheel] = math.min(config.escMaxBrakeTorque, config.escBrakeGain * understeer)
		state.escActive = true
	end
end

return table.freeze(Electronics)
