--!strict
--[[
	BUG-001's way out, as a guard: whatever Space, S, W, the steering and the paddles did, once
	nothing is held any drift state ends within the drift's fall and exit times, and the tyre smoke
	follows the tyres' real slip. Random sequences on the three cars, seeded so a failure repeats.
	It passes on main: it guards the bound, it does not reproduce the stuck state.
]]
local Config = require("../src/shared/Config/Drift")
local DriveSim = require("../tools/DriveSim")
local Drift = require("../src/shared/Vehicle/Drift")
local InputHelp = require("../src/shared/Config/InputHelp")
local SmokeConfig = require("../src/shared/Config/TyreSmoke")
local T = require("../../../tools/test/T")
local TyreSmoke = require("../src/shared/Rules/TyreSmoke")
local Types = require("../src/shared/Config/Cars/Types")

local describe, it, expect = T.describe, T.it, T.expect

local DT = 1 / 60
local SEQUENCES = 25
local CARS: { { string | Types.CarConfig } } = {
	{ "DR458", require("../src/shared/Config/Cars/DR458/Physics") },
	{ "SVJ", require("../src/shared/Config/Cars/SVJ/Physics") },
	{ "Boss302", require("../src/shared/Config/Cars/Boss302/Physics") },
}

-- One seeded sequence on `car`; returns the seconds from release until no drift state is left, and
-- the strongest tyre smoke share 6 s after release.
local function sequence(car: Types.CarConfig, seed: number): (number, number)
	local state = seed
	local function random(): number
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
	local mode = car.modeOrder[1]
	local sim = DriveSim.new(car, InputHelp.keyboard)
	local speed = random() * 150
	DriveSim.setSpeed(sim, speed / 3.6, if speed < 60 then 2 elseif speed < 110 then 3 else 4)
	for _ = 1, 3 + math.floor(random() * 4) do
		local space, brake, throttle = random() < 0.7, random() < 0.6, random() < 0.5
		local steer = ({ -1, 0, 1 })[1 + math.floor(random() * 3)]
		local paddle = random()
		local manual = random() < 0.3
		local untilTime, first = sim.time + 0.1 + random() * 1.4, true
		while sim.time < untilTime do
			DriveSim.frame(
				sim,
				DriveSim.input({
					throttle = if throttle then 1 else 0,
					brake = if brake then 1 else 0,
					steer = steer,
					handbrake = if space then 1 else 0,
					drift = space,
					drivingMode = mode,
					gearboxMode = if manual then "manual" else "auto",
					shiftUp = first and paddle < 0.2,
					shiftDown = first and paddle >= 0.2 and paddle < 0.4,
				}),
				DT
			)
			first = false
		end
	end
	local idle = DriveSim.input({ drivingMode = mode })
	local released, ended = sim.time, math.huge
	local readings: { TyreSmoke.Wheel } = {}
	local smoke = 0
	while sim.time < released + 6 do
		local result = DriveSim.frame(sim, idle, DT)
		if ended == math.huge and not Drift.active(sim.model.drift) then
			ended = sim.time - released
		end
		smoke = 0
		for _, wheel in TyreSmoke.measure(sim.model, result.wheels, readings) do
			smoke = math.max(smoke, TyreSmoke.share(wheel, SmokeConfig.THRESHOLDS))
		end
	end
	return ended, smoke
end

describe("Drift bound (BUG-001)", function()
	it(
		"ends every drift within its fall and exit times once nothing is held, and the smoke with the slip",
		function()
			local bound = Config.FALL_TIME + Config.EXIT_TIME + DT
			for _, case in CARS do
				local name, car = case[1] :: string, case[2] :: Types.CarConfig
				for index = 1, SEQUENCES do
					local ended, smoke = sequence(car, index * 7919 + #name)
					if not (ended <= bound) or not (smoke <= 0.01) then
						error(
							`{name} sequence {index}: drift ended after {ended} s (bound {bound}), smoke {smoke} at 6 s`
						)
					end
				end
			end
			expect(true).toBe(true)
		end
	)
end)
