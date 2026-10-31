--!strict
--[[
	Drives a car offline through a scripted run and prints, frame by frame, what the car's audio
	controller would play: each engine loop's volume and speed, the shift dip, the limiter, the
	start-up's hand-over, and every one-shot (gear clunks, pops) with its region, volume and
	speed. tools/audio/render_preview.py turns it into a listening file, so the sound can be
	judged without Studio. A start-up played from the car's own sound is named in `startupSound`,
	not among the one-shots.

	    lune run games/drive-lab/tools/audio_timeline.luau [SVJ|DR458] [mode] > timeline.json

	The mode is one of the car's (SVJ: Strada, Sport, Corsa, default Corsa; DR458: 1, 2, OFF,
	default 1).

	The car drives DriveSim on its own physics: start-up, a moment at idle, full throttle from
	rest, a lift at speed, hard braking to a stop (the DR458's run is longer, to reach sixth).
	Mirrors Controllers/CarAudio's update with the same rules and config; the cockpit view, so no
	far loop. Random draws are seeded, so a run repeats.
]]
local CarAudio = require("../src/shared/Config/CarAudio")
local CarAudioEvents = require("../src/shared/Rules/CarAudioEvents")
local DR458Pack = require("../src/shared/Config/Cars/DR458/Audio")
local DR458Physics = require("../src/shared/Config/Cars/DR458/Physics")
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
assert(car == "SVJ" or car == "DR458", `unknown car {car}: SVJ or DR458`)
local pack: CarAudio.Pack = if car == "DR458" then DR458Pack else SVJPack
local mode: Types.DrivingMode = process.args[2] or if car == "DR458" then "1" else "Corsa"
assert(pack.popTriggers.liftChance[mode] ~= nil, `the {car} has no {mode} mode`)
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

-- Telemetry of the car on DriveSim, one readout per frame.
local function simulatedRun(): { Readout }
	local phases = {
		{ seconds = STARTUP_SECONDS, throttle = 0, brake = 0 },
		{ seconds = 1.0, throttle = 0, brake = 0 },
		{ seconds = if car == "DR458" then 19.0 else 10.0, throttle = 1, brake = 0 },
		{ seconds = 3.0, throttle = 0, brake = 0 },
		{ seconds = if car == "DR458" then 6.0 else 4.5, throttle = 0, brake = 1 },
	}
	local sim = DriveSim.new(if car == "DR458" then DR458Physics else SVJPhysics)
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

local readouts = simulatedRun()

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
local own = startup.sound
local startupLength = startup.region.to - startup.region.from
-- Level with the idle loop it hands over to, as Controllers/CarAudio sets it.
local idle = pack.engineLayers[1]
for _, layer in pack.engineLayers do
	if layer.rpm < idle.rpm then
		idle = layer
	end
end
local idleLevel = pack.engineVolume * idle.volume * EngineSound.loudness(pack.engineTuning, idle.rpm)
-- The car's own start-up sound cannot be downloaded, so the preview does not render it.
local startupSound = if own
	then {
		id = own.id,
		from = own.from,
		handOver = own.handOver,
		to = own.to,
		volume = idleLevel * own.volume,
	}
	else nil
if own == nil then
	table.insert(shots, {
		t = 0,
		kind = "startup",
		from = startup.region.from,
		to = startup.region.to,
		volume = idleLevel * 10 ^ (startup.boostDb / 20),
		speed = 1,
	})
end

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
	local share
	if own then
		share = EngineSound.handOver(own.handOver, own.to, own.from + time)
	else
		local progress = math.clamp((time - startup.handOver) / (startupLength - startup.handOver), 0, 1)
		share = math.sin(progress * math.pi / 2)
	end
	local master = pack.engineVolume * dip * share
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
print(serde.encode("json", {
	dt = DT,
	car = car,
	mode = mode,
	files = files,
	frames = frames,
	shots = shots,
	startupSound = startupSound,
}))
