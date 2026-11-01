--!strict
--[[
	The readings an analog cluster shows that the car does not publish, simulated from what it does
	(Config/Gauges Engine): the fuel burned for the engine's power, a lumped coolant mass heated by
	a share of that fuel and cooled through the thermostat, the radiator and the fan, the oil
	following the coolant with the load on top, the oil pressure from the revs and the oil's
	temperature, and the distance covered. Litres, °C, kPa, watts, kilometres.
]]
local Gauges = require("../Config/Gauges")

export type State = {
	fuel: number,
	coolant: number,
	oil: number,
	-- This drive's distance and the odometer's, km.
	trip: number,
	odometer: number,
}

-- What the engine does this frame: whether it runs, the brake power it makes (W) and the speed.
export type Running = { running: boolean, power: number, speedKmh: number }

local KM_PER_MILE = 1.609344

local EngineGauges = {}

-- A car's first drive on this client: the start's fuel, the engine at the air's temperature.
function EngineGauges.new(engine: Gauges.Engine, odometerMiles: number): State
	local air = engine.ambient
	return {
		fuel = engine.tankLitres * engine.startFuel,
		coolant = air,
		oil = air,
		trip = 0,
		odometer = odometerMiles * KM_PER_MILE,
	}
end

-- Fuel the engine burns (kg/s): its brake work at its specific consumption, never under idle.
function EngineGauges.fuelFlow(engine: Gauges.Engine, running: boolean, power: number): number
	if not running then
		return 0
	end
	return math.max(engine.idleFlow, engine.bsfc * math.max(power, 0))
end

-- How far the thermostat is open at `temperature`, 0 to 1.
function EngineGauges.thermostat(engine: Gauges.Engine, temperature: number): number
	local valve = engine.thermostat
	return math.clamp((temperature - valve.opens) / (valve.open - valve.opens), 0, 1)
end

-- W/K from the coolant to the air at `temperature` and `speedKmh`.
function EngineGauges.conductance(engine: Gauges.Engine, temperature: number, speedKmh: number): number
	local airflow = engine.radiator + engine.radiatorPerSpeed * math.max(speedKmh, 0) / 3.6
	local fan = math.clamp(temperature - engine.fan.on + 0.5, 0, 1) * engine.fan.conductance
	return engine.shellLoss + EngineGauges.thermostat(engine, temperature) * airflow + fan
end

local function relax(value: number, toward: number, seconds: number, timeConstant: number): number
	return toward + (value - toward) * math.exp(-seconds / timeConstant)
end

-- An engine left off for `seconds`: coolant and oil drift toward the air.
function EngineGauges.coolOff(state: State, engine: Gauges.Engine, seconds: number)
	if seconds <= 0 then
		return
	end
	state.coolant = relax(state.coolant, engine.ambient, seconds, engine.coolDown)
	state.oil = relax(state.oil, engine.ambient, seconds, engine.coolDown)
end

local function advance(state: State, engine: Gauges.Engine, now: Running, dt: number)
	local flow = EngineGauges.fuelFlow(engine, now.running, now.power)
	state.fuel = math.max(engine.reserveLitres, state.fuel - flow / engine.fuelDensity * dt)
	local distance = math.max(now.speedKmh, 0) / 3600 * dt
	state.trip += distance
	state.odometer += distance
	if not now.running then
		EngineGauges.coolOff(state, engine, dt)
		return
	end
	local heat = engine.heatShare * flow * engine.fuelEnergy
	local loss = EngineGauges.conductance(engine, state.coolant, now.speedKmh)
		* (state.coolant - engine.ambient)
	state.coolant += (heat - loss) / engine.heatCapacity * dt
	local load = math.clamp(now.power / engine.fullPower, 0, 1)
	state.oil = relax(state.oil, state.coolant + engine.oil.loadRise * load, dt, engine.oil.lag)
end

-- Advances the simulation `dt` seconds, in steps no longer than Config/Gauges.MAX_STEP.
function EngineGauges.step(state: State, engine: Gauges.Engine, now: Running, dt: number)
	local steps = math.max(1, math.ceil(dt / Gauges.MAX_STEP))
	for _ = 1, steps do
		advance(state, engine, now, dt / steps)
	end
end

-- The oil pressure (kPa) at `rpm` with the oil at `oil` °C: thicker oil pushes harder and its
-- relief valve lets more through; none while the crank is still.
function EngineGauges.oilPressure(engine: Gauges.Engine, rpm: number, oil: number): number
	if rpm <= 0 then
		return 0
	end
	local cold, hot = engine.oilPressure.cold, engine.oilPressure.hot
	local warmth = math.clamp((oil - cold.temperature) / (hot.temperature - cold.temperature), 0, 1)
	local relief = cold.relief + (hot.relief - cold.relief) * warmth
	local rpmScale = cold.rpmScale + (hot.rpmScale - cold.rpmScale) * warmth
	return relief * (1 - math.exp(-rpm / rpmScale))
end

function EngineGauges.fuelShare(state: State, engine: Gauges.Engine): number
	return math.clamp(state.fuel / engine.tankLitres, 0, 1)
end

function EngineGauges.miles(kilometres: number): number
	return kilometres / KM_PER_MILE
end

return table.freeze(EngineGauges)
