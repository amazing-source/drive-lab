--!strict
--[[
	The weather's sound as a mixer: from the rain's intensity, the road's wetness, the car's
	speed and the view, how loud each rain loop, the roof drumming and the tyres' spray play, how
	much the cockpit muffles the outside, and when a distant thunder rolls.

	The rain grows louder with intensity along a power curve and hands over from the light loop
	to the heavy one by an equal-power crossfade, so its power never dips in the hand-over. The
	intensity it follows is eased with half-lives, so the rain builds and fades even where the
	published value jumps. A view change moves at a fixed rate, so the cockpit's muffling takes
	the same time at any frame rate. Thunder waits for heavy rain, then rolls after random gaps,
	never the same take twice in a row.
]]

export type Range = { from: number, to: number }

export type Tuning = {
	-- Intensity at which the rain reaches its full level (the strongest preset's), and the
	-- curve up to it: level = (intensity / fullIntensity) ^ levelExponent, a linear gain.
	fullIntensity: number,
	levelExponent: number,
	-- Intensity over which the light loop hands over to the heavy one.
	heavyBlend: Range,
	-- Seconds for the followed intensity to cover half the gap, rising and falling.
	riseHalfLife: number,
	fallHalfLife: number,
	-- Linear volumes at a full share.
	rainVolume: number,
	roofVolume: number,
	sprayVolume: number,
	-- Seconds a change of view takes, and the cockpit's shaping of everything outside: a gain,
	-- and the equaliser's mid (400 Hz to 4 kHz) and high (above 4 kHz) bands in dB.
	viewSeconds: number,
	cockpitGain: number,
	cockpitMidDb: number,
	cockpitHighDb: number,
	-- The spray: km/h at which it is full, its growth with speed, its PlaybackSpeed from a
	-- standstill to full speed, and its volume's half-life.
	sprayFullKmh: number,
	sprayExponent: number,
	spraySpeed: Range,
	sprayHalfLife: number,
	-- Thunder: the followed intensity it needs, seconds before the first one and between the
	-- next, each one's volume (times the rain's level) and PlaybackSpeed, and how many takes.
	thunderFrom: number,
	thunderFirstGap: Range,
	thunderGap: Range,
	thunderVolume: Range,
	thunderSpeed: Range,
	thunderTakes: number,
}

export type Input = {
	rainIntensity: number,
	wetness: number,
	speedKmh: number,
	cockpit: boolean,
	driving: boolean,
}

export type Thunder = { take: number, volume: number, speed: number }

export type Mix = {
	rainLight: number,
	rainHeavy: number,
	roofLight: number,
	roofHeavy: number,
	spray: number,
	spraySpeed: number,
	-- Volumes of the outside and the roof groups, and the outside group's equaliser in dB.
	outside: number,
	roof: number,
	midGain: number,
	highGain: number,
	-- A thunder to start this frame.
	thunder: Thunder?,
}

export type State = {
	tuning: Tuning,
	random: () -> number,
	intensity: number,
	-- 0 outside the car's cabin, 1 in the cockpit.
	inside: number,
	spray: number,
	-- Seconds to the next thunder; nil while the rain is too light for one.
	thunderIn: number?,
	lastTake: number,
	primed: boolean,
	mix: Mix,
}

local WeatherAudio = {}

-- The share of the remaining gap to close this frame, so the gap halves every `halfLife` s.
function WeatherAudio.blend(dt: number, halfLife: number): number
	return 1 - 0.5 ^ (dt / halfLife)
end

-- NaN and the infinities read as 0: a missing or broken attribute is no rain, no speed.
local function finite(value: number): number
	return if value == value and math.abs(value) < math.huge then value else 0
end

local function between(state: State, range: Range): number
	return range.from + (range.to - range.from) * state.random()
end

function WeatherAudio.level(tuning: Tuning, intensity: number): number
	return math.clamp(intensity / tuning.fullIntensity, 0, 1) ^ tuning.levelExponent
end

-- The light and heavy loops' shares at `intensity`; their squares sum to 1.
function WeatherAudio.shares(tuning: Tuning, intensity: number): (number, number)
	local blend = tuning.heavyBlend
	local t = math.clamp((intensity - blend.from) / (blend.to - blend.from), 0, 1)
	return math.cos(t * math.pi / 2), math.sin(t * math.pi / 2)
end

-- The spray's share before its volume, from speed (either way) and the road's wetness.
function WeatherAudio.spray(tuning: Tuning, speedKmh: number, wetness: number): number
	local speed = math.clamp(math.abs(finite(speedKmh)) / tuning.sprayFullKmh, 0, 1)
	return speed ^ tuning.sprayExponent * math.clamp(finite(wetness), 0, 1)
end

local function pickTake(state: State): number
	local takes = state.tuning.thunderTakes
	if state.lastTake == 0 or takes == 1 then
		return math.min(takes, 1 + math.floor(state.random() * takes))
	end
	local skip = math.min(takes - 1, 1 + math.floor(state.random() * (takes - 1)))
	return (state.lastTake - 1 + skip) % takes + 1
end

local function thunder(state: State, level: number, dt: number): Thunder?
	local tuning = state.tuning
	if state.intensity < tuning.thunderFrom then
		state.thunderIn = nil
		return nil
	end
	local wait = state.thunderIn
	if wait == nil then
		state.thunderIn = between(state, tuning.thunderFirstGap)
		return nil
	end
	wait -= dt
	if wait > 0 then
		state.thunderIn = wait
		return nil
	end
	local take = pickTake(state)
	local volume = between(state, tuning.thunderVolume) * level
	local speed = between(state, tuning.thunderSpeed)
	state.lastTake = take
	state.thunderIn = between(state, tuning.thunderGap)
	return { take = take, volume = volume, speed = speed }
end

function WeatherAudio.new(tuning: Tuning, random: () -> number): State
	assert(tuning.thunderTakes >= 1, "WeatherAudio needs at least one thunder take")
	assert(tuning.heavyBlend.to > tuning.heavyBlend.from, "the light-to-heavy blend needs a width")
	return {
		tuning = tuning,
		random = random,
		intensity = 0,
		inside = 0,
		spray = 0,
		thunderIn = nil,
		lastTake = 0,
		primed = false,
		mix = {
			rainLight = 0,
			rainHeavy = 0,
			roofLight = 0,
			roofHeavy = 0,
			spray = 0,
			spraySpeed = tuning.spraySpeed.from,
			outside = 1,
			roof = 0,
			midGain = 0,
			highGain = 0,
			thunder = nil,
		},
	}
end

-- Advances the mix by `dt`. The rain and the spray start from silence; the view starts where
-- the camera is, so spawning in the cockpit does not fade the roof in.
function WeatherAudio.step(state: State, input: Input, dt: number): Mix
	local tuning = state.tuning
	local goal = math.clamp(finite(input.rainIntensity), 0, 1)
	local halfLife = if goal > state.intensity then tuning.riseHalfLife else tuning.fallHalfLife
	state.intensity += (goal - state.intensity) * WeatherAudio.blend(dt, halfLife)
	local insideGoal = if input.cockpit then 1 else 0
	if state.primed then
		local reach = dt / tuning.viewSeconds
		state.inside += math.clamp(insideGoal - state.inside, -reach, reach)
	else
		state.inside = insideGoal
	end
	local sprayGoal = if input.driving then WeatherAudio.spray(tuning, input.speedKmh, input.wetness) else 0
	state.spray += (sprayGoal - state.spray) * WeatherAudio.blend(dt, tuning.sprayHalfLife)
	state.primed = true

	local level = WeatherAudio.level(tuning, state.intensity)
	local light, heavy = WeatherAudio.shares(tuning, state.intensity)
	local inside = state.inside
	local mix = state.mix
	mix.rainLight = tuning.rainVolume * level * light
	mix.rainHeavy = tuning.rainVolume * level * heavy
	mix.roofLight = tuning.roofVolume * level * light
	mix.roofHeavy = tuning.roofVolume * level * heavy
	mix.spray = tuning.sprayVolume * state.spray
	local range = tuning.spraySpeed
	local speedShare = math.clamp(math.abs(finite(input.speedKmh)) / tuning.sprayFullKmh, 0, 1)
	mix.spraySpeed = range.from + (range.to - range.from) * speedShare
	-- The gain moves evenly in dB, the roof fades in at equal power.
	mix.outside = tuning.cockpitGain ^ inside
	mix.roof = math.sin(inside * math.pi / 2)
	mix.midGain = tuning.cockpitMidDb * inside
	mix.highGain = tuning.cockpitHighDb * inside
	mix.thunder = thunder(state, level, dt)
	return mix
end

return table.freeze(WeatherAudio)
