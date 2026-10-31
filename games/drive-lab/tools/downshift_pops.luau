--!strict
--[[
	Counts the exhaust pops each car makes per downshift while braking hard from 250 km/h to 30 km/h
	in sixth, on its own physics (DriveSim) and its own pop rules (Rules/CarAudioEvents,
	Rules/ExhaustPops), as Controllers/CarAudio runs them: in every drive mode, with the automatic
	gearbox and in manual with a downshift asked for every MANUAL_EVERY seconds. Each case is the mean
	of [trials] seeded runs (default 5). Prints JSON.

	    lune run games/drive-lab/tools/downshift_pops.luau [trials]
]]
local CarAudioEvents = require("../src/shared/Rules/CarAudioEvents")
local DR458Pack = require("../src/shared/Config/Cars/DR458/Audio")
local DR458Physics = require("../src/shared/Config/Cars/DR458/Physics")
local DriveSim = require("./DriveSim")
local ExhaustPops = require("../src/shared/Rules/ExhaustPops")
local SVJPack = require("../src/shared/Config/Cars/SVJ/Audio")
local SVJPhysics = require("../src/shared/Config/Cars/SVJ/Physics")
local process = require("@lune/process")
local serde = require("@lune/serde")

local DT = 1 / 60
local FROM_KMH, TO_KMH = 250, 30
local START_GEAR = 6
local TRIALS = tonumber(process.args[1]) or 5
local MANUAL_EVERY = 0.6

type Case = {
	car: string,
	mode: string,
	gearbox: string,
	downshifts: number,
	pops: number,
	perDownshift: number,
}

local function run(
	physics: any,
	pack: any,
	mode: string,
	gearbox: "auto" | "manual",
	seed: number
): (number, number)
	math.randomseed(seed)
	local sim = DriveSim.new(physics)
	DriveSim.setSpeed(sim, FROM_KMH / 3.6, START_GEAR)
	local events = CarAudioEvents.new(pack.events)
	local pops = ExhaustPops.new(pack.popTriggers)
	local downshifts, count, time, nextAsk = 0, 0, 0, MANUAL_EVERY
	for _ = 1, math.round(30 / DT) do
		local ask = gearbox == "manual" and time >= nextAsk
		if ask then
			nextAsk = time + MANUAL_EVERY
		end
		local t = DriveSim.frame(
			sim,
			DriveSim.input({
				throttle = 0,
				brake = 1,
				drivingMode = mode,
				gearboxMode = gearbox,
				shiftDown = ask,
			}),
			DT
		).telemetry
		local readout = {
			rpm = t.rpm,
			throttle = t.throttle,
			gear = t.gear,
			shifting = t.shifting,
			limiter = t.limiter,
			tcActive = t.tcActive,
		}
		local happened = CarAudioEvents.step(events, readout, DT)
		if happened.gear == "Down" then
			downshifts += 1
		end
		if
			ExhaustPops.step(pops, happened, readout, mode, time, math.random)
			and pops.kind == "Downshift"
		then
			count += 1
		end
		time += DT
		if t.speedKmh <= TO_KMH then
			break
		end
	end
	return downshifts, count
end

local cases: { Case } = {}
for _, car in { { "SVJ", SVJPhysics, SVJPack }, { "DR458", DR458Physics, DR458Pack } } do
	local name, physics, pack = car[1], car[2], car[3]
	for _, mode in physics.modeOrder do
		for _, gearbox in { "auto", "manual" } do
			local downshifts, count = 0, 0
			for trial = 1, TRIALS do
				local d, c = run(physics, pack, mode, gearbox :: any, trial)
				downshifts += d
				count += c
			end
			table.insert(cases, {
				car = name,
				mode = mode,
				gearbox = gearbox,
				downshifts = downshifts / TRIALS,
				pops = count / TRIALS,
				perDownshift = if downshifts > 0 then count / downshifts else 0,
			})
		end
	end
end
print(serde.encode("json", cases))
