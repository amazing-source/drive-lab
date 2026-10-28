--!strict
--[[
	The engine's loops as a mixer: from rpm and throttle, how loud each loop plays and how fast.

	A loop recorded at R rpm plays at rpm / R, so its firing order follows the engine. The loops
	of one load (on or off throttle) hand over to their neighbour in rpm by an equal-power
	crossfade inside a band around their crossover; on and off are blended by throttle the
	same way, and a loop both loads share (the idle) adds its two shares by power, so the
	total power stays constant through every hand-over. Volume and speed then ease toward
	those targets with half-lives, so nothing steps between frames at any frame rate.
]]

export type Load = "On" | "Off" | "Both"

export type Layer = {
	-- Rpm the loop was recorded at.
	rpm: number,
	load: Load,
	-- Linear gain at a full share.
	volume: number,
	-- Centre of the hand-over to the next loop up in the same load, rpm. Without it the centre
	-- is the geometric mean of the two loops' rpm, where both are stretched equally.
	crossoverRpm: number?,
}

export type Tuning = {
	-- Width of a hand-over band, octaves of rpm; a band never reaches past either loop.
	crossfadeOctaves: number,
	-- PlaybackSpeed bounds.
	minSpeed: number,
	maxSpeed: number,
	-- The engine gets louder with rpm: quietDb at quietRpm and below, loudDb at loudRpm and
	-- above, interpolated over log rpm.
	quietRpm: number,
	quietDb: number,
	loudRpm: number,
	loudDb: number,
	-- Seconds for the throttle blend to cover half the gap: a lift is faster than a press.
	liftHalfLife: number,
	pressHalfLife: number,
	volumeHalfLife: number,
	speedHalfLife: number,
}

export type Mix = {
	volumes: { number },
	speeds: { number },
}

export type State = {
	layers: { Layer },
	tuning: Tuning,
	throttle: number,
	mix: Mix,
	primed: boolean,
}

local EngineSound = {}

-- The share of the remaining gap to close this frame, so the gap halves every `halfLife` s.
function EngineSound.blend(dt: number, halfLife: number): number
	return 1 - 0.5 ^ (dt / halfLife)
end

function EngineSound.loudness(tuning: Tuning, rpm: number): number
	local share = math.log(rpm / tuning.quietRpm) / math.log(tuning.loudRpm / tuning.quietRpm)
	local db = tuning.quietDb + (tuning.loudDb - tuning.quietDb) * math.clamp(share, 0, 1)
	return 10 ^ (db / 20)
end

-- Where `rpm` sits in the hand-over from `lower` to `upper`: 0 is all lower, 1 all upper.
local function handover(lower: Layer, upper: Layer, tuning: Tuning, rpm: number): number
	local centre = lower.crossoverRpm or math.sqrt(lower.rpm * upper.rpm)
	local half = 2 ^ (tuning.crossfadeOctaves / 2)
	local from = math.max(centre / half, lower.rpm)
	local to = math.min(centre * half, upper.rpm)
	if to <= from then
		return if rpm >= centre then 1 else 0
	end
	return math.clamp(math.log(rpm / from) / math.log(to / from), 0, 1)
end

-- Equal-power shares of the loops in one load at `rpm`, by layer index.
local function shares(layers: { Layer }, load: Load, tuning: Tuning, rpm: number): { [number]: number }
	local chain: { number } = {}
	for index, layer in layers do
		if layer.load == load or layer.load == "Both" then
			table.insert(chain, index)
		end
	end
	table.sort(chain, function(a: number, b: number): boolean
		return layers[a].rpm < layers[b].rpm
	end)
	local result: { [number]: number } = {}
	if #chain == 0 then
		return result
	end
	if rpm <= layers[chain[1]].rpm then
		result[chain[1]] = 1
		return result
	end
	for position = 1, #chain - 1 do
		local lower, upper = chain[position], chain[position + 1]
		if rpm < layers[upper].rpm then
			local t = handover(layers[lower], layers[upper], tuning, rpm)
			result[lower] = math.cos(t * math.pi / 2)
			result[upper] = math.sin(t * math.pi / 2)
			return result
		end
	end
	result[chain[#chain]] = 1
	return result
end

-- The unsmoothed mix at `rpm` with `onShare` of the on-throttle loops (0 to 1).
function EngineSound.target(layers: { Layer }, tuning: Tuning, rpm: number, onShare: number): Mix
	rpm = math.max(rpm, 1)
	local share = math.clamp(onShare, 0, 1)
	local onGain, offGain = math.sin(share * math.pi / 2), math.cos(share * math.pi / 2)
	local power = table.create(#layers, 0)
	for index, value in shares(layers, "On", tuning, rpm) do
		power[index] += (onGain * value) ^ 2
	end
	for index, value in shares(layers, "Off", tuning, rpm) do
		power[index] += (offGain * value) ^ 2
	end
	local loud = EngineSound.loudness(tuning, rpm)
	local volumes, speeds = table.create(#layers, 0), table.create(#layers, 1)
	for index, layer in layers do
		volumes[index] = layer.volume * loud * math.sqrt(power[index])
		speeds[index] = math.clamp(rpm / layer.rpm, tuning.minSpeed, tuning.maxSpeed)
	end
	return { volumes = volumes, speeds = speeds }
end

function EngineSound.new(layers: { Layer }, tuning: Tuning): State
	assert(#layers > 0, "EngineSound needs at least one loop")
	for _, layer in layers do
		assert(layer.rpm > 0, "a loop's rpm must be positive")
	end
	return {
		layers = layers,
		tuning = tuning,
		throttle = 0,
		mix = { volumes = table.create(#layers, 0), speeds = table.create(#layers, 1) },
		primed = false,
	}
end

-- Advances the mix by `dt` toward rpm and throttle. Volumes start from silence; speeds start
-- on target, so the first frame neither clicks nor glides.
function EngineSound.step(state: State, rpm: number, throttle: number, dt: number): Mix
	local tuning = state.tuning
	local halfLife = if throttle < state.throttle then tuning.liftHalfLife else tuning.pressHalfLife
	state.throttle += (math.clamp(throttle, 0, 1) - state.throttle) * EngineSound.blend(dt, halfLife)
	local goal = EngineSound.target(state.layers, tuning, rpm, state.throttle)
	local volumeShare = EngineSound.blend(dt, tuning.volumeHalfLife)
	local speedShare = if state.primed then EngineSound.blend(dt, tuning.speedHalfLife) else 1
	local mix = state.mix
	for index in state.layers do
		mix.volumes[index] += (goal.volumes[index] - mix.volumes[index]) * volumeShare
		mix.speeds[index] += (goal.speeds[index] - mix.speeds[index]) * speedShare
	end
	state.primed = true
	return mix
end

return table.freeze(EngineSound)
