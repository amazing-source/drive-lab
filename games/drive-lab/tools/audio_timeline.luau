--!strict
--[[
	Drives a car offline through a scripted run and prints, frame by frame, what the car's audio
	controller would play: each engine loop's volume and speed, the shift dip, the limiter, the
	start-up's hand-over, and every one-shot (gear clunks, pops) with its region, volume and
	speed (and its file, when not the events file), and each loop's region when the pack's loops
	share files. tools/audio/render_preview.py turns it into a listening file, so the sound can be
	judged without Studio. A start-up played from the car's own sound is named in `startupSound`,
	not among the one-shots.

	    lune run games/drive-lab/tools/audio_timeline.luau [SVJ|DR458] [mode] [fallback] [pack=<json>] > timeline.json

	The mode is one of the car's (SVJ: Strada, Sport, Corsa, default Corsa; DR458: 1, 2, OFF,
	default 1). `fallback` plays a car's start-up from the events file's region, as it does when
	its own start-up sound fails to load (taken here as failing at the press). `pack=<json>` renders a
	bank before it is uploaded: the file's `pack` fields replace the car's, and its `files` name the
	files to play (as FILES below).

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
local StartupHandOver = require("../src/shared/Rules/StartupHandOver")
local Types = require("../src/shared/Config/Cars/Types")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local DT = 1 / 60
local STARTUP_SECONDS = 10.5
local car = process.args[1] or "SVJ"
assert(car == "SVJ" or car == "DR458", `unknown car {car}: SVJ or DR458`)
local pack: CarAudio.Pack = if car == "DR458" then DR458Pack else SVJPack
local mode: Types.DrivingMode = process.args[2] or if car == "DR458" then "1" else "Corsa"
assert(pack.popTriggers.liftChance[mode] ~= nil, `the {car} has no {mode} mode`)
local fallback = false
-- A candidate pack (pack=<json>): fields that replace the car's pack, and the files to render.
local candidate: any = nil
for index = 3, #process.args do
	local option = process.args[index]
	if option == "fallback" then
		fallback = true
	elseif string.sub(option, 1, 5) == "pack=" then
		candidate = serde.decode("json", fs.readFile(string.sub(option, 6)))
	else
		error(`unknown option {option}: fallback or pack=<candidate.json>`)
	end
end
if candidate then
	local merged = table.clone(pack) :: any
	for key, value in candidate.pack do
		merged[key] = value
	end
	pack = merged
end
math.randomseed(7)

type Readout = CarAudioEvents.Readout & { speedKmh: number }

-- Each layer's file in tools/audio's output for the car, in the pack's layer order.
local FILES = {
	SVJ = {
		layers = { "eng_idle.ogg", "eng_on.ogg", "eng_off.ogg" },
		limiter = "eng_limiter.ogg",
		events = "events.ogg",
	},
	-- tools/audio/cut_dr458_gdc.py's packed bank: every loop a region of one file.
	DR458 = {
		layers = table.create(#DR458Pack.engineLayers, "bank.ogg"),
		limiter = "bank.ogg",
		events = "events.ogg",
		-- The SVJ's events.ogg, which its pops are cut from.
		pops = "svj_events.ogg",
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
-- A pack whose pops are cut from another file than its events file names that file.
local popsFile = if car == "DR458" then FILES.DR458.pops else nil
assert(pack.pops.soundId == nil or popsFile, `the {car}'s pops come from a file the timeline does not name`)
local frames, shots = {}, {}
local dip, limiterShare = 1, 0
local startup = pack.startup
local own = if fallback then nil else startup.sound
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

local handOver = StartupHandOver.new(startup, own, 0, 0)
local played: CarAudio.Region = if own then { from = own.from, to = own.to } else startup.region

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
	-- Offline the start-up is loaded from the press; as in the engine, it is removed as it ends,
	-- and a removed Sound no longer reads as loaded.
	local position = played.from + time
	local playing = position < played.to
	local share = StartupHandOver.step(
		handOver,
		{ playing = playing, loaded = playing, position = position },
		readout.rpm,
		time,
		DT
	)
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
			volume = gear.volume * CarAudio.carGain(pack),
			speed = if happened.gear == "Up" then gear.upSpeed else gear.downSpeed,
		})
	end
	if ExhaustPops.step(pops, happened, readout, mode, time, math.random) then
		local region = pack.pops.regions[math.random(1, #pack.pops.regions)]
		table.insert(shots, {
			t = time,
			kind = "pop",
			file = if pack.pops.soundId then popsFile else nil,
			from = region.from,
			to = region.to,
			volume = between(pack.pops.volume) * CarAudio.carGain(pack),
			speed = between(pack.pops.speed),
		})
	end
end

local files: any = if candidate then candidate.files elseif car == "DR458" then FILES.DR458 else FILES.SVJ
-- Each loop's region of its file, for a pack whose loops share files; absent when none does.
local layerRegions: { CarAudio.Region | false } = {}
local anyRegion = pack.limiter.region ~= nil
for index, layer in pack.engineLayers do
	layerRegions[index] = layer.region or false
	anyRegion = anyRegion or layer.region ~= nil
end
local regions = if anyRegion then { layers = layerRegions, limiter = pack.limiter.region or false } else nil
print(serde.encode("json", {
	dt = DT,
	car = car,
	mode = mode,
	files = files,
	frames = frames,
	shots = shots,
	startupSound = startupSound,
	regions = regions,
}))
