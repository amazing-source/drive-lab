--!strict
--[[
	Drives a car offline through a scripted run and prints, frame by frame, what the car's audio
	controller would play: each engine loop's volume and speed, the shift dip, the limiter, the
	start-up's hand-over, and every one-shot (gear clunks, pops) with its region, volume and
	speed. tools/audio/render_preview.py turns it into a listening file, so the sound can be
	judged without Studio.

	    lune run games/drive-lab/tools/audio_timeline.luau [SVJ|DR458] [Strada|Sport|Corsa] > timeline.json

	The SVJ drives DriveSim on its own physics: start-up, a moment at idle, full throttle from
	rest, a lift at speed, hard braking. The DR458 has no physics yet, so its run is scripted on
	the road 458's gearing and the 458 Challenge's mass and torque (DR458_RUN): start-up, idle,
	a free rev to the limiter, full throttle from rest through five upshifts, a lift, braking
	with downshifts to second, a stop. Mirrors Controllers/CarAudio's update with the same rules
	and config; the cockpit view, so no far loop. Random draws are seeded, so a run repeats.
]]
local CarAudio = require("../src/shared/Config/CarAudio")
local CarAudioEvents = require("../src/shared/Rules/CarAudioEvents")
local DR458Pack = require("../src/shared/Config/Cars/DR458/Audio")
local DriveSim = require("./DriveSim")
local EngineSound = require("../src/shared/Rules/EngineSound")
local ExhaustPops = require("../src/shared/Rules/ExhaustPops")
local SVJPack = require("../src/shared/Config/Cars/SVJ/Audio")
local SVJPhysics = require("../src/shared/Config/Cars/SVJ/Physics")
local Types = require("../src/shared/Config/Cars/Types")
local process = require("@lune/process")
local serde = require("@lune/serde")

local DT = 1 / 60
local STARTUP_SECONDS = 10.5
local car = process.args[1] or "SVJ"
local mode = (process.args[2] or "Corsa") :: Types.DrivingMode
assert(car == "SVJ" or car == "DR458", `unknown car {car}: SVJ or DR458`)
assert(mode == "Strada" or mode == "Sport" or mode == "Corsa", `unknown mode {mode}`)
math.randomseed(7)

type Readout = CarAudioEvents.Readout & { speedKmh: number }

-- Each layer's file in tools/audio's output for the car, in the pack's layer order.
local FILES = {
	SVJ = {
		layers = { "eng_idle.ogg", "eng_on.ogg", "eng_off.ogg" },
		limiter = "eng_limiter.ogg",
		events = "events.ogg",
	},
	DR458 = {
		layers = {
			"idle.ogg",
			"on_2100.ogg",
			"on_2900.ogg",
			"on_4900.ogg",
			"on_5900.ogg",
			"on_6900.ogg",
			"on_8100.ogg",
			"off_2000.ogg",
			"off_3800.ogg",
			"off_5000.ogg",
			"off_7000.ogg",
			"off_9000.ogg",
		},
		limiter = "limiter.ogg",
		events = "events.ogg",
	},
}

-- The DR458's scripted run until it has physics. Mass: the Challenge's race minimum with its
-- driver (1,383 kg). Torque: 540 N·m at 6,000 rpm and 445 at 9,000 (570 CV there); 300 at
-- 1,000 and the rest of the curve are guesses. Gearing: the road 458's, the Challenge's being
-- unpublished. Shift times: the F430 Challenge's 60 ms. Idle, limiter, shift points, launch rpm,
-- grip, drag and braking are our choices.
local DR458_RUN = {
	mass = 1383,
	torque = { { 1000, 300 }, { 3250, 432 }, { 6000, 540 }, { 9000, 445 }, { 9500, 420 } },
	ratios = { 3.08, 2.18, 1.63, 1.29, 1.03, 0.84, 0.69 },
	finalDrive = 5.14,
	tyreRadius = 0.345,
	efficiency = 0.9,
	dragArea = 0.75,
	rollingResistance = 0.015,
	maxAcceleration = 12.5,
	braking = 13,
	idleRpm = 1000,
	limiterRpm = 9000,
	limiterResumeRpm = 8850,
	launchRpm = 4500,
	upshiftRpm = 8800,
	downshiftRpm = 5200,
	shiftSeconds = 0.06,
	downshiftSeconds = 0.07,
	blipThrottle = 0.8,
	freeRevRate = 14000,
	freeFallRate = 7000,
}

local function torqueAt(rpm: number): number
	local points = DR458_RUN.torque
	if rpm <= points[1][1] then
		return points[1][2]
	end
	for index = 2, #points do
		local low, high = points[index - 1], points[index]
		if rpm <= high[1] then
			return low[2] + (high[2] - low[2]) * (rpm - low[1]) / (high[1] - low[1])
		end
	end
	return points[#points][2]
end

local function wheelRpm(speed: number, gear: number): number
	return speed / DR458_RUN.tyreRadius * DR458_RUN.ratios[gear] * DR458_RUN.finalDrive * 60 / (2 * math.pi)
end

type Phase = { name: string, seconds: number, throttle: number, brake: number, neutral: boolean? }

-- Telemetry of the scripted DR458 run, one readout per frame.
local function scriptedRun(): { Readout }
	local phases: { Phase } = {
		{ name = "startup", seconds = STARTUP_SECONDS, throttle = 0, brake = 0, neutral = true },
		{ name = "idle", seconds = 2.0, throttle = 0, brake = 0, neutral = true },
		{ name = "rev", seconds = 1.6, throttle = 1, brake = 0, neutral = true },
		{ name = "settle", seconds = 2.5, throttle = 0, brake = 0, neutral = true },
		{ name = "launch", seconds = 15.0, throttle = 1, brake = 0 },
		{ name = "lift", seconds = 2.5, throttle = 0, brake = 0 },
		{ name = "brake", seconds = 9.0, throttle = 0, brake = 1 },
		{ name = "stopped", seconds = 2.0, throttle = 0, brake = 1, neutral = true },
	}
	local run = DR458_RUN
	local readouts: { Readout } = {}
	local speed, rpm, gear = 0, run.idleRpm, 0
	local cutting = false
	local shift: { from: number, to: number, startRpm: number, elapsed: number, seconds: number }? = nil
	for _, phase in phases do
		for _ = 1, math.round(phase.seconds / DT) do
			local throttle = phase.throttle
			local shifting, limiter = false, false
			if phase.neutral or gear == 0 then
				gear = if phase.neutral then 0 else 1
				speed = if phase.neutral then math.max(0, speed - run.braking * DT) else speed
				if gear == 0 then
					if cutting and rpm <= run.limiterResumeRpm then
						cutting = false
					elseif rpm >= run.limiterRpm then
						cutting = true
					end
					local driven = if cutting then 0 else throttle
					limiter = cutting
					local rate = if driven > 0 then run.freeRevRate * driven else -run.freeFallRate
					rpm = math.max(run.idleRpm, rpm + rate * DT)
					throttle = driven
				end
			end
			if gear > 0 then
				local active = shift
				local floor = if throttle > 0 and gear == 1 then run.launchRpm else run.idleRpm
				if active == nil then
					if cutting and rpm <= run.limiterResumeRpm then
						cutting = false
					elseif rpm >= run.limiterRpm then
						cutting = true
					end
				end
				local driven = if active or cutting then 0 else throttle
				local drive = torqueAt(rpm)
					* driven
					* run.ratios[gear]
					* run.finalDrive
					* run.efficiency
					/ run.tyreRadius
				local resist = 0.5 * 1.2 * run.dragArea * speed * speed
					+ run.rollingResistance * run.mass * 9.81
				local acceleration = if phase.brake > 0
					then -run.braking * phase.brake
					else math.min(drive / run.mass, run.maxAcceleration) - resist / run.mass
				speed = math.max(0, speed + acceleration * DT)
				if active then
					active.elapsed += DT
					shifting = true
					local share = math.clamp(active.elapsed / active.seconds, 0, 1)
					rpm = active.startRpm
						+ (math.max(wheelRpm(speed, active.to), floor) - active.startRpm) * share
					-- An upshift cuts the torque; a downshift blips toward the lower gear's speed.
					throttle = if active.to < active.from and share < 0.8 then run.blipThrottle else 0
					if share >= 1 then
						gear = active.to
						shift = nil
					end
				else
					rpm = math.max(wheelRpm(speed, gear), floor)
					throttle = driven
					limiter = cutting
					if throttle > 0 and rpm >= run.upshiftRpm and gear < #run.ratios then
						shift = {
							from = gear,
							to = gear + 1,
							startRpm = rpm,
							elapsed = 0,
							seconds = run.shiftSeconds,
						}
					elseif phase.brake > 0 and gear > 2 and rpm < run.downshiftRpm then
						shift = {
							from = gear,
							to = gear - 1,
							startRpm = rpm,
							elapsed = 0,
							seconds = run.downshiftSeconds,
						}
					end
				end
			end
			table.insert(readouts, {
				rpm = rpm,
				throttle = throttle,
				gear = gear,
				shifting = shifting,
				limiter = limiter,
				tcActive = false,
				speedKmh = speed * 3.6,
			})
		end
	end
	return readouts
end

-- Telemetry of the SVJ on DriveSim, one readout per frame.
local function simulatedRun(): { Readout }
	local phases = {
		{ seconds = STARTUP_SECONDS, throttle = 0, brake = 0 },
		{ seconds = 1.0, throttle = 0, brake = 0 },
		{ seconds = 10.0, throttle = 1, brake = 0 },
		{ seconds = 3.0, throttle = 0, brake = 0 },
		{ seconds = 4.5, throttle = 0, brake = 1 },
	}
	local sim = DriveSim.new(SVJPhysics)
	local readouts: { Readout } = {}
	for _, phase in phases do
		for _ = 1, math.round(phase.seconds / DT) do
			local t = DriveSim.frame(
				sim,
				DriveSim.input({ throttle = phase.throttle, brake = phase.brake, drivingMode = mode }),
				DT
			).telemetry
			table.insert(readouts, {
				rpm = t.rpm,
				throttle = t.throttle,
				gear = t.gear,
				shifting = t.shifting,
				limiter = t.limiter,
				tcActive = t.tcActive,
				speedKmh = t.speedKmh,
			})
		end
	end
	return readouts
end

local pack: CarAudio.Pack = if car == "DR458" then DR458Pack else SVJPack
local readouts: { Readout } = if car == "DR458" then scriptedRun() else simulatedRun()

local function between(range: CarAudio.Region): number
	return range.from + (range.to - range.from) * math.random()
end

local mixerLayers: { EngineSound.Layer } = {}
for _, layer in pack.engineLayers do
	table.insert(
		mixerLayers,
		{ rpm = layer.rpm, load = layer.load, volume = layer.volume, crossoverRpm = layer.crossoverRpm }
	)
end
local engine = EngineSound.new(mixerLayers, pack.engineTuning)
local events = CarAudioEvents.new(pack.events)
local pops = ExhaustPops.new(pack.popTriggers)
local frames, shots = {}, {}
local dip, limiterShare = 1, 0
local startup = pack.startup
local startupLength = startup.region.to - startup.region.from
-- Level with the idle loop it hands over to, as Controllers/CarAudio sets it.
local idle = pack.engineLayers[1]
for _, layer in pack.engineLayers do
	if layer.rpm < idle.rpm then
		idle = layer
	end
end
table.insert(shots, {
	t = 0,
	kind = "startup",
	from = startup.region.from,
	to = startup.region.to,
	volume = pack.engineVolume
		* idle.volume
		* EngineSound.loudness(pack.engineTuning, idle.rpm)
		* 10 ^ (startup.boostDb / 20),
	speed = 1,
})

for index, readout in readouts do
	local time = (index - 1) * DT
	local happened = CarAudioEvents.step(events, readout, DT)
	local mix = EngineSound.step(engine, readout.rpm, if happened.limiter then 1 else readout.throttle, DT)
	local dipGoal = if readout.shifting then pack.shiftDip.gain else 1
	dip += (dipGoal - dip) * EngineSound.blend(
		DT,
		if dipGoal < dip then pack.shiftDip.downHalfLife else pack.shiftDip.upHalfLife
	)
	limiterShare += ((if happened.limiter then 1 else 0) - limiterShare) * EngineSound.blend(
		DT,
		pack.limiter.halfLife
	)
	-- The start-up's own hand-over: none until its fade-out begins, then equal power.
	local progress = math.clamp((time - startup.handOver) / (startupLength - startup.handOver), 0, 1)
	local master = pack.engineVolume * dip * math.sin(progress * math.pi / 2)
	local onDuck = 1 - (1 - pack.limiter.onDuck) * limiterShare
	local volumes, speeds = {}, {}
	for layerIndex, layer in pack.engineLayers do
		volumes[layerIndex] = mix.volumes[layerIndex] * master * (if layer.load == "On" then onDuck else 1)
		speeds[layerIndex] = mix.speeds[layerIndex]
	end
	local loud = EngineSound.loudness(pack.engineTuning, math.max(readout.rpm, 1))
	table.insert(frames, {
		t = time,
		rpm = readout.rpm,
		gear = readout.gear,
		kmh = readout.speedKmh,
		volumes = volumes,
		speeds = speeds,
		limiter = pack.limiter.volume * limiterShare * master * loud,
		limiterSpeed = math.max(readout.rpm, 1) / pack.limiter.rpm,
	})
	if happened.gear then
		local gear = pack.gear
		table.insert(shots, {
			t = time,
			kind = "gear" .. happened.gear,
			from = gear.region.from,
			to = gear.region.to,
			volume = gear.volume,
			speed = if happened.gear == "Up" then gear.upSpeed else gear.downSpeed,
		})
	end
	if ExhaustPops.step(pops, happened, readout, mode, time, math.random) then
		local region = pack.pops.regions[math.random(1, #pack.pops.regions)]
		table.insert(shots, {
			t = time,
			kind = "pop",
			from = region.from,
			to = region.to,
			volume = between(pack.pops.volume),
			speed = between(pack.pops.speed),
		})
	end
end

local files = if car == "DR458" then FILES.DR458 else FILES.SVJ
print(
	serde.encode("json", { dt = DT, car = car, mode = mode, files = files, frames = frames, shots = shots })
)
