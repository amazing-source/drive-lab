--!strict
--[[
	A scripted engine run for a candidate sound set, for a car with no physics in Drive Lab yet. Prints,
	frame by frame, what Controllers/CarAudio's engine mix would play (Rules/EngineSound with the set's
	layers and tuning, the shift dip, the limiter and its duck), in tools/audio/render_preview.py's
	format, and the moments one-shots belong to (`events`: each upshift, downshift and the lift after the
	limiter), for the caller to place. The candidate's `profile` is a list of segments
	{ seconds, rpm at the start, rpm at the end, throttle, "limiter" | "shiftUp" | "shiftDown" | "" };
	its `files` name the files. With no argument it runs the Boss 302's packed set
	(tests/fixtures/boss302_sweep.json, written from tools/audio/pack_boss302.py's candidate.json).

	    lune run games/drive-lab/tools/audio_sweep.luau [candidate.json] > sweep.json
]]
local EngineSound = require("../src/shared/Rules/EngineSound")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local DT = 1 / 60
local DIP = { gain = 0.5, downHalfLife = 0.012, upHalfLife = 0.05 }
local DEFAULT = "games/drive-lab/tests/fixtures/boss302_sweep.json"
local candidate = serde.decode("json", fs.readFile(process.args[1] or DEFAULT))
local pack = candidate.pack
local limiterRpm: number = pack.limiter.rpm

local layers: { EngineSound.Layer } = {}
for _, layer in pack.engineLayers do
	table.insert(
		layers,
		{ rpm = layer.rpm, load = layer.load, volume = layer.volume, crossoverRpm = layer.crossoverRpm }
	)
end
local engine = EngineSound.new(layers, pack.engineTuning)
local frames, events = {}, {}
local time, limiterShare, dip = 0, 0, 1
local wasLimiter = false
for _, segment in candidate.profile do
	local seconds, from, to, throttle, flag = segment[1], segment[2], segment[3], segment[4], segment[5]
	local steps = math.max(1, math.round(seconds / DT))
	local shifting = flag == "shiftUp" or flag == "shiftDown"
	if shifting then
		table.insert(events, { t = time, kind = flag })
	end
	if wasLimiter and flag ~= "limiter" then
		table.insert(events, { t = time, kind = "lift" })
	end
	wasLimiter = flag == "limiter"
	for step = 1, steps do
		local rpm = from + (to - from) * step / steps
		if flag == "limiter" then
			rpm = limiterRpm - (step % 4 < 2 and 0 or 180)
		end
		local mix = EngineSound.step(engine, rpm, throttle, DT)
		local dipGoal = if shifting then DIP.gain else 1
		dip += (dipGoal - dip) * EngineSound.blend(
			DT,
			if dipGoal < dip then DIP.downHalfLife else DIP.upHalfLife
		)
		limiterShare += ((if flag == "limiter" then 1 else 0) - limiterShare) * EngineSound.blend(
			DT,
			pack.limiter.halfLife
		)
		local onDuck = 1 - (1 - pack.limiter.onDuck) * limiterShare
		local volumes, speeds = {}, {}
		for index, layer in pack.engineLayers do
			volumes[index] = mix.volumes[index] * dip * (if layer.load == "On" then onDuck else 1)
			speeds[index] = mix.speeds[index]
		end
		local loud = EngineSound.loudness(pack.engineTuning, math.max(rpm, 1))
		table.insert(frames, {
			t = time,
			rpm = rpm,
			volumes = volumes,
			speeds = speeds,
			limiter = pack.limiter.volume * limiterShare * loud * dip,
			limiterSpeed = math.max(rpm, 1) / limiterRpm,
		})
		time += DT
	end
end
print(serde.encode("json", { dt = DT, files = candidate.files, frames = frames, events = events }))
