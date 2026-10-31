--!strict
--[[
	The sound of speed as a mixer: from the car's speed, the view and the surface under it, how
	loud the wind and the tyres' roar play, how fast, how far the wind's low-pass has opened, and
	how each is equalised.

	Wind noise power grows with about the sixth power of speed, and with speed its energy
	climbs from a low rumble into a hiss, so the wind's level follows a power of speed and its
	cutoff opens in even octaves between two speeds. The roar grows more slowly, about
	30 log10(speed) dB. The speed both follow is eased with a half-life, so a jump in the
	published speed never steps the mix; a view change moves at a fixed rate, as the weather's
	does; a change of surface eases in with its own half-life.
]]

export type Range = { from: number, to: number }

-- Gains in dB: the whole sound, and its bands below 400 Hz, from 400 Hz to 4 kHz, and above.
export type Shaping = { gain: number, low: number, mid: number, high: number }

export type Tuning = {
	-- km/h at which both loops play at their full volume: the car's top speed.
	topKmh: number,
	-- Wind: linear volume at top speed, amplitude growth (speed / topKmh) ^ windExponent, the
	-- low-pass cutoff in Hz opening from cutoffHz.from at cutoffKmh.from to cutoffHz.to at
	-- cutoffKmh.to, and its PlaybackSpeed from a standstill to top speed.
	windVolume: number,
	windExponent: number,
	cutoffKmh: Range,
	cutoffHz: Range,
	windSpeed: Range,
	-- Roar: the same, without a cutoff. The loop was recorded near roadSpeed's 1.
	roadVolume: number,
	roadExponent: number,
	roadSpeed: Range,
	-- Seconds for the followed speed to cover half the gap.
	speedHalfLife: number,
	-- Seconds a change of view takes, and each sound's shaping outside and in the cockpit.
	viewSeconds: number,
	outside: { wind: Shaping, road: Shaping },
	cockpit: { wind: Shaping, road: Shaping },
	-- The roar's shaping on each surface, by material name, and on any other; its half-life.
	surfaces: { [string]: Shaping },
	otherSurface: Shaping,
	surfaceHalfLife: number,
}

export type Input = {
	speedKmh: number,
	cockpit: boolean,
	driving: boolean,
	-- Material name under the car, or nil while nothing is under it.
	surface: string?,
	-- The driven car's level (Config/CarAudio carGain): the wind and the roar heard in it follow
	-- it, so they keep their balance with its engine. 1 when nil.
	carGain: number?,
}

export type Mix = {
	-- Linear volumes and PlaybackSpeeds.
	wind: number,
	windSpeed: number,
	windCutoff: number,
	road: number,
	roadSpeed: number,
	-- Equaliser gains in dB.
	windEq: Shaping,
	roadEq: Shaping,
}

export type State = {
	tuning: Tuning,
	speed: number,
	-- 0 outside the car's cabin, 1 in the cockpit.
	inside: number,
	surface: Shaping,
	primed: boolean,
	mix: Mix,
}

local RoadAudio = {}

-- The share of the remaining gap to close this frame, so the gap halves every `halfLife` s.
function RoadAudio.blend(dt: number, halfLife: number): number
	return 1 - 0.5 ^ (dt / halfLife)
end

-- NaN and the infinities read as 0: a missing or broken attribute is no speed.
local function finite(value: number): number
	return if value == value and math.abs(value) < math.huge then value else 0
end

local function share(tuning: Tuning, speedKmh: number): number
	return math.clamp(speedKmh / tuning.topKmh, 0, 1)
end

local function lerp(range: Range, t: number): number
	return range.from + (range.to - range.from) * t
end

local function shaping(): Shaping
	return { gain = 0, low = 0, mid = 0, high = 0 }
end

-- Writes into `into` the shaping `t` of the way from `a` to `b`, plus `extra`.
local function mixShaping(into: Shaping, a: Shaping, b: Shaping, t: number, extra: Shaping?)
	into.gain = a.gain + (b.gain - a.gain) * t + (if extra then extra.gain else 0)
	into.low = a.low + (b.low - a.low) * t + (if extra then extra.low else 0)
	into.mid = a.mid + (b.mid - a.mid) * t + (if extra then extra.mid else 0)
	into.high = a.high + (b.high - a.high) * t + (if extra then extra.high else 0)
end

-- The wind's linear volume at `speedKmh`, before the view's gain.
function RoadAudio.wind(tuning: Tuning, speedKmh: number): number
	return tuning.windVolume * share(tuning, math.abs(finite(speedKmh))) ^ tuning.windExponent
end

-- The roar's linear volume at `speedKmh`, before the view's and the surface's gains.
function RoadAudio.road(tuning: Tuning, speedKmh: number): number
	return tuning.roadVolume * share(tuning, math.abs(finite(speedKmh))) ^ tuning.roadExponent
end

-- The wind's low-pass cutoff at `speedKmh`, Hz: even octaves between the two speeds.
function RoadAudio.cutoff(tuning: Tuning, speedKmh: number): number
	local range = tuning.cutoffKmh
	local t = math.clamp((math.abs(finite(speedKmh)) - range.from) / (range.to - range.from), 0, 1)
	return tuning.cutoffHz.from * (tuning.cutoffHz.to / tuning.cutoffHz.from) ^ t
end

function RoadAudio.new(tuning: Tuning): State
	assert(tuning.topKmh > 0, "RoadAudio needs a top speed")
	assert(tuning.cutoffKmh.to > tuning.cutoffKmh.from, "the cutoff needs a speed range")
	assert(tuning.cutoffHz.from > 0 and tuning.cutoffHz.to > 0, "cutoffs are frequencies")
	return {
		tuning = tuning,
		speed = 0,
		inside = 0,
		surface = shaping(),
		primed = false,
		mix = {
			wind = 0,
			windSpeed = tuning.windSpeed.from,
			windCutoff = tuning.cutoffHz.from,
			road = 0,
			roadSpeed = tuning.roadSpeed.from,
			windEq = shaping(),
			roadEq = shaping(),
		},
	}
end

local function stepSurface(state: State, name: string?, dt: number)
	local tuning = state.tuning
	local goal = if name then tuning.surfaces[name] or tuning.otherSurface else tuning.otherSurface
	local surface = state.surface
	local t = if state.primed then RoadAudio.blend(dt, tuning.surfaceHalfLife) else 1
	surface.gain += (goal.gain - surface.gain) * t
	surface.low += (goal.low - surface.low) * t
	surface.mid += (goal.mid - surface.mid) * t
	surface.high += (goal.high - surface.high) * t
end

-- Advances the mix by `dt`. The speed starts from a standstill, so getting in at speed fades
-- in; the view and the surface start where they are.
function RoadAudio.step(state: State, input: Input, dt: number): Mix
	local tuning = state.tuning
	local goal = if input.driving then math.abs(finite(input.speedKmh)) else 0
	state.speed += (goal - state.speed) * RoadAudio.blend(dt, tuning.speedHalfLife)
	local insideGoal = if input.cockpit then 1 else 0
	if state.primed then
		local reach = dt / tuning.viewSeconds
		state.inside += math.clamp(insideGoal - state.inside, -reach, reach)
	else
		state.inside = insideGoal
	end
	stepSurface(state, input.surface, dt)
	state.primed = true

	local speed = state.speed
	local t = share(tuning, speed)
	local mix = state.mix
	mixShaping(mix.windEq, tuning.outside.wind, tuning.cockpit.wind, state.inside, nil)
	mixShaping(mix.roadEq, tuning.outside.road, tuning.cockpit.road, state.inside, state.surface)
	-- The view's and the surface's whole-sound gains go into the volumes, not the equaliser.
	local car = input.carGain or 1
	mix.wind = RoadAudio.wind(tuning, speed) * 10 ^ (mix.windEq.gain / 20) * car
	mix.road = RoadAudio.road(tuning, speed) * 10 ^ (mix.roadEq.gain / 20) * car
	mix.windSpeed = lerp(tuning.windSpeed, t)
	mix.roadSpeed = lerp(tuning.roadSpeed, t)
	mix.windCutoff = RoadAudio.cutoff(tuning, speed)
	return mix
end

return table.freeze(RoadAudio)
