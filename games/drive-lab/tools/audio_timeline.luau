--!strict
--[[
	Drives the SVJ offline through a scripted run and prints, frame by frame, what the car's audio
	controller would play: each engine loop's volume and speed, the shift dip, the limiter, the
	start-up's hand-over, and every one-shot (gear clunks, pops) with its region, volume and
	speed. tools/audio/render_preview.py turns it into a listening file, so the sound can be
	judged without Studio.

	    lune run games/drive-lab/tools/audio_timeline.luau [Strada|Sport|Corsa] > timeline.json

	The run: start-up, a moment at idle, full throttle from rest, a lift at speed, hard braking.
	Mirrors Controllers/CarAudio's update (same rules, same config); the cockpit view, so no far
	loop. Pops use a seeded random, so a run repeats.
]]
local CarAudio = require("../src/shared/Config/CarAudio")
local Pack = require("../src/shared/Config/Cars/SVJ/Audio")
local CarAudioEvents = require("../src/shared/Rules/CarAudioEvents")
local DriveSim = require("./DriveSim")
local EngineSound = require("../src/shared/Rules/EngineSound")
local SVJ = require("../src/shared/Config/Cars/SVJ/Physics")
local process = require("@lune/process")
local serde = require("@lune/serde")

local DT = 1 / 60
local mode = process.args[1] or "Corsa"
math.randomseed(7)

local function between(range: CarAudio.Region): number
	return range.from + (range.to - range.from) * math.random()
end

-- Seconds of each phase and its input.
local PHASES = {
	{ name = "startup", seconds = 10.5, throttle = 0, brake = 0 },
	{ name = "idle", seconds = 1.0, throttle = 0, brake = 0 },
	{ name = "launch", seconds = 10.0, throttle = 1, brake = 0 },
	{ name = "lift", seconds = 3.0, throttle = 0, brake = 0 },
	{ name = "brake", seconds = 4.5, throttle = 0, brake = 1 },
}

local sim = DriveSim.new(SVJ)
local engine = EngineSound.new(Pack.engineLayers, Pack.engineTuning)
local events = CarAudioEvents.new(Pack.events)
local frames, shots = {}, {}
local dip, limiterShare = 1, 0
local popsUntil, nextPop = 0, 0
local time = 0
local startup = Pack.startup
local startupLength = startup.region.to - startup.region.from
local pops = Pack.pops
-- Level with the idle loop it hands over to, as Controllers/CarAudio sets it.
local idle = Pack.engineLayers[1]
for _, layer in Pack.engineLayers do
	if layer.rpm < idle.rpm then
		idle = layer
	end
end
table.insert(shots, {
	t = 0,
	kind = "startup",
	from = startup.region.from,
	to = startup.region.to,
	volume = Pack.engineVolume
		* idle.volume
		* EngineSound.loudness(Pack.engineTuning, idle.rpm)
		* 10 ^ (startup.boostDb / 20),
	speed = 1,
})

for _, phase in PHASES do
	for _ = 1, math.round(phase.seconds / DT) do
		local result = DriveSim.frame(
			sim,
			DriveSim.input({ throttle = phase.throttle, brake = phase.brake, drivingMode = mode :: any }),
			DT
		)
		local t = result.telemetry
		local car = {
			rpm = t.rpm,
			throttle = t.throttle,
			gear = t.gear,
			shifting = t.shifting,
			limiter = t.limiter,
			tcActive = t.tcActive,
		}
		local happened = CarAudioEvents.step(events, car, DT)
		local mix = EngineSound.step(engine, car.rpm, if happened.limiter then 1 else car.throttle, DT)
		local dipGoal = if car.shifting then Pack.shiftDip.gain else 1
		dip += (dipGoal - dip) * EngineSound.blend(
			DT,
			if dipGoal < dip then Pack.shiftDip.downHalfLife else Pack.shiftDip.upHalfLife
		)
		limiterShare += ((if happened.limiter then 1 else 0) - limiterShare) * EngineSound.blend(
			DT,
			Pack.limiter.halfLife
		)
		-- The start-up's own hand-over: none until its fade-out begins, then equal power.
		local progress = math.clamp((time - startup.handOver) / (startupLength - startup.handOver), 0, 1)
		local master = Pack.engineVolume * dip * math.sin(progress * math.pi / 2)
		local onDuck = 1 - (1 - Pack.limiter.onDuck) * limiterShare
		local volumes, speeds = {}, {}
		for index, layer in Pack.engineLayers do
			volumes[index] = mix.volumes[index] * master * (if layer.load == "On" then onDuck else 1)
			speeds[index] = mix.speeds[index]
		end
		local loud = EngineSound.loudness(Pack.engineTuning, math.max(car.rpm, 1))
		table.insert(frames, {
			t = time,
			rpm = car.rpm,
			gear = car.gear,
			kmh = t.speedKmh,
			volumes = volumes,
			speeds = speeds,
			limiter = Pack.limiter.volume * limiterShare * master * loud,
			limiterSpeed = math.max(car.rpm, 1) / Pack.limiter.rpm,
		})
		if happened.gear then
			local gear = Pack.gear
			table.insert(shots, {
				t = time,
				kind = "gear" .. happened.gear,
				from = gear.region.from,
				to = gear.region.to,
				volume = gear.volume,
				speed = if happened.gear == "Up" then gear.upSpeed else gear.downSpeed,
			})
		end
		local function pop()
			local region = pops.regions[math.random(1, #pops.regions)]
			table.insert(shots, {
				t = time,
				kind = "pop",
				from = region.from,
				to = region.to,
				volume = between(pops.volume),
				speed = between(pops.speed),
			})
		end
		if
			happened.cut
			and car.rpm >= Pack.events.liftMinRpm
			and math.random() < (pops.upshiftChance :: any)[mode]
		then
			pop()
		end
		if happened.lift and math.random() < (pops.chance :: any)[mode] then
			popsUntil, nextPop = time + between(pops.trainSeconds), time
		end
		if car.throttle > Pack.events.liftTo or car.rpm < pops.minRpm then
			popsUntil = 0
		elseif time < popsUntil and time >= nextPop then
			pop()
			nextPop = time + between(pops.gapSeconds)
		end
		time += DT
	end
end

print(serde.encode("json", { dt = DT, mode = mode, frames = frames, shots = shots }))
