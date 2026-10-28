--!strict
--[[
	Drives the SVJ offline through a scripted run and prints, frame by frame, what
	Controllers/RoadAudio would set (each loop's volume and speed, the wind's cutoff, both
	equalisers) and what Controllers/CarAudio would set on the engine loops, so
	tools/audio/render_road_preview.py can render the speed sounds alone and under the engine,
	without Studio.

	    lune run games/drive-lab/tools/road_timeline.luau [Strada|Sport|Corsa] > road_timeline.json

	The run, in the chase view: a moment at a standstill, full throttle to near the top speed, the
	cockpit for the last stretch of it, back outside, a lift, hard braking to a stop. Same rules,
	same config. The engine part mirrors CarAudio's update for the loops, the limiter, the shift
	dip and the view's shaping; it leaves out the start-up, the gear clunks and the pops. The road
	is asphalt throughout.
]]
local CarAudio = require("../src/shared/Config/CarAudio")
local CarAudioEvents = require("../src/shared/Rules/CarAudioEvents")
local Config = require("../src/shared/Config/RoadAudio")
local DriveSim = require("./DriveSim")
local EngineSound = require("../src/shared/Rules/EngineSound")
local RoadAudio = require("../src/shared/Rules/RoadAudio")
local SVJ = require("../src/shared/Config/Cars/SVJ")
local process = require("@lune/process")
local serde = require("@lune/serde")

local DT = 1 / 60
local mode = process.args[1] or "Corsa"

-- Seconds of each phase, its input, and whether the camera is in the cockpit.
local PHASES = {
	{ seconds = 1.5, throttle = 0, brake = 0, cockpit = false },
	{ seconds = 20, throttle = 1, brake = 0, cockpit = false },
	{ seconds = 12, throttle = 1, brake = 0, cockpit = true },
	{ seconds = 6, throttle = 1, brake = 0, cockpit = false },
	{ seconds = 4, throttle = 0, brake = 0, cockpit = false },
	{ seconds = 9, throttle = 0, brake = 1, cockpit = false },
	{ seconds = 1.5, throttle = 0, brake = 1, cockpit = false },
}

local function copy(shaping: RoadAudio.Shaping): RoadAudio.Shaping
	return { gain = shaping.gain, low = shaping.low, mid = shaping.mid, high = shaping.high }
end

local sim = DriveSim.new(SVJ)
local road = RoadAudio.new(Config.TUNING)
local engine = EngineSound.new(CarAudio.ENGINE_LAYERS, CarAudio.ENGINE_TUNING)
local events = CarAudioEvents.new(CarAudio.EVENTS)
local dip, limiterShare, outside = 1, 0, 1
local frames = {}
local time = 0
for _, phase in PHASES do
	for _ = 1, math.round(phase.seconds / DT) do
		local result = DriveSim.frame(
			sim,
			DriveSim.input({ throttle = phase.throttle, brake = phase.brake, drivingMode = mode :: any }),
			DT
		)
		local t = result.telemetry
		local mix = RoadAudio.step(
			road,
			{ speedKmh = t.speedKmh, cockpit = phase.cockpit, driving = true, surface = "Asphalt" },
			DT
		)

		local car = {
			rpm = t.rpm,
			throttle = t.throttle,
			gear = t.gear,
			shifting = t.shifting,
			limiter = t.limiter,
			tcActive = t.tcActive,
		}
		local happened = CarAudioEvents.step(events, car, DT)
		local engineMix = EngineSound.step(engine, car.rpm, if happened.limiter then 1 else car.throttle, DT)
		local dipGoal = if car.shifting then CarAudio.SHIFT_DIP.gain else 1
		dip += (dipGoal - dip) * EngineSound.blend(
			DT,
			if dipGoal < dip then CarAudio.SHIFT_DIP.downHalfLife else CarAudio.SHIFT_DIP.upHalfLife
		)
		limiterShare += ((if happened.limiter then 1 else 0) - limiterShare) * EngineSound.blend(
			DT,
			CarAudio.LIMITER.halfLife
		)
		outside += ((if phase.cockpit then 0 else 1) - outside) * EngineSound.blend(
			DT,
			CarAudio.VIEW_HALF_LIFE
		)
		local master = CarAudio.ENGINE_VOLUME * dip
		local onDuck = 1 - (1 - CarAudio.LIMITER.onDuck) * limiterShare
		local volumes, speeds = {}, {}
		for index, layer in CarAudio.ENGINE_LAYERS do
			volumes[index] = engineMix.volumes[index] * master * (if layer.load == "On" then onDuck else 1)
			speeds[index] = engineMix.speeds[index]
		end
		local loud = EngineSound.loudness(CarAudio.ENGINE_TUNING, math.max(car.rpm, 1))

		table.insert(frames, {
			t = time,
			kmh = t.speedKmh,
			rpm = t.rpm,
			gear = t.gear,
			cockpit = phase.cockpit,
			wind = mix.wind,
			windSpeed = mix.windSpeed,
			windCutoff = mix.windCutoff,
			road = mix.road,
			roadSpeed = mix.roadSpeed,
			windEq = copy(mix.windEq),
			roadEq = copy(mix.roadEq),
			engineVolumes = volumes,
			engineSpeeds = speeds,
			limiter = CarAudio.LIMITER.volume * limiterShare * master * loud,
			limiterSpeed = math.max(car.rpm, 1) / CarAudio.LIMITER.rpm,
			engineOutside = outside,
		})
		time += DT
	end
end

print(serde.encode("json", {
	dt = DT,
	mode = mode,
	loops = Config.LOOPS,
	cutoffQ = Config.CUTOFF_Q,
	midBand = Config.MID_BAND,
	engineEqualiser = { cockpit = CarAudio.COCKPIT.engine, outside = CarAudio.OUTSIDE.engine },
	frames = frames,
}))
