--!strict
--[[
	The tyres' squeal and skid as a mixer, one pair of loops per axle, from what Driving publishes
	for each tyre: its combined slip over the slip of peak grip (1 is the limit) and how fast its
	contact patch slides. The onset squeal comes in right at the limit, so the limit is heard
	before it is passed; the sustained skid carries a slide or a drift. A locked or spinning wheel,
	far past any drift, trades most of its squeal for the rough skid. Both fade on a wet road, as the
	smoke does, and all four loops together never play louder than what the engine plays at that
	moment, less a headroom.

	Each axle follows its noisier wheel. Volumes ease toward their goal with a short attack and a
	longer release, so a one-frame spike in the slip makes no click.
]]

export type Range = { from: number, to: number }

-- Gains in dB: the whole sound, and its bands below 400 Hz, from 400 Hz to 4 kHz, and above.
export type Shaping = { gain: number, low: number, mid: number, high: number }

export type Layer = {
	-- Linear volume at its full share.
	volume: number,
	-- The share eases in over these ranges of slip and of slide speed (m/s); the share is their
	-- product.
	slip: Range,
	slide: Range,
	-- PlaybackSpeed from `pitch.from` to `pitch.to` as the slide speed goes over `pitchSlide`.
	pitch: Range,
	pitchSlide: Range,
}

export type Tuning = {
	squeal: Layer,
	skid: Layer,
	-- Over this slip the squeal loses up to `lockCut` of itself: a lock or a burnout, not a drift.
	lockSlip: Range,
	lockCut: number,
	-- Road wetness over which both fade out.
	wet: Range,
	-- The tyres' loudness against the engine's (dB, from the loops' measured loudness), and how far
	-- under the engine they must stay.
	loudnessOffsetDb: number,
	headroomDb: number,
	-- Half-lives (s) of a volume rising and falling.
	attack: number,
	release: number,
	-- Seconds a change of view takes, and each layer's shaping outside and in the cockpit.
	viewSeconds: number,
	outside: { squeal: Shaping, skid: Shaping },
	cockpit: { squeal: Shaping, skid: Shaping },
}

-- One axle's two tyres, as published.
export type Axle = { slips: { number }, slides: { number } }

export type Input = {
	front: Axle,
	rear: Axle,
	wetness: number,
	-- What the engine plays at this moment, as one linear amplitude (Rules/EngineSound.level times
	-- the pack's engine volume, without the shift dip or the start-up).
	engineLevel: number,
	cockpit: boolean,
	driving: boolean,
}

export type AxleMix = { squeal: number, squealSpeed: number, skid: number, skidSpeed: number }

export type Mix = {
	front: AxleMix,
	rear: AxleMix,
	squealEq: Shaping,
	skidEq: Shaping,
}

export type State = {
	tuning: Tuning,
	inside: number,
	primed: boolean,
	mix: Mix,
}

local TyreAudio = {}

-- NaN and the infinities read as 0: a missing or broken attribute is no slip.
local function finite(value: number): number
	return if value == value and math.abs(value) < math.huge then value else 0
end

-- 0 at `range.from`, 1 at `range.to`, eased at both ends.
function TyreAudio.ease(value: number, range: Range): number
	if range.to <= range.from then
		return 0
	end
	local t = math.clamp((finite(value) - range.from) / (range.to - range.from), 0, 1)
	return t * t * (3 - 2 * t)
end

function TyreAudio.blend(dt: number, halfLife: number): number
	return 1 - 0.5 ^ (dt / halfLife)
end

local function lerp(range: Range, t: number): number
	return range.from + (range.to - range.from) * t
end

-- The squeal's and the skid's shares (0 to 1) for a tyre at `slip` and `slide` on a road of
-- `wetness`.
function TyreAudio.shares(tuning: Tuning, slip: number, slide: number, wetness: number): (number, number)
	local dry = 1 - TyreAudio.ease(wetness, tuning.wet)
	local lock = 1 - tuning.lockCut * TyreAudio.ease(slip, tuning.lockSlip)
	local squeal = TyreAudio.ease(slip, tuning.squeal.slip)
		* TyreAudio.ease(slide, tuning.squeal.slide)
		* lock
	local skid = TyreAudio.ease(slip, tuning.skid.slip) * TyreAudio.ease(slide, tuning.skid.slide)
	return squeal * dry, skid * dry
end

-- The most the two layers together may play at, as one amplitude, under an engine at `engineLevel`.
function TyreAudio.ceiling(tuning: Tuning, engineLevel: number): number
	return math.max(finite(engineLevel), 0) * 10 ^ ((tuning.loudnessOffsetDb - tuning.headroomDb) / 20)
end

-- An axle's goal volumes and speeds: its noisier tyre's.
function TyreAudio.axle(tuning: Tuning, axle: Axle, wetness: number): AxleMix
	local squeal, skid, slide = 0, 0, 0
	for index, slip in axle.slips do
		local wheelSlide = finite(axle.slides[index] or 0)
		local wheelSqueal, wheelSkid = TyreAudio.shares(tuning, slip, wheelSlide, wetness)
		if wheelSqueal * wheelSqueal + wheelSkid * wheelSkid > squeal * squeal + skid * skid then
			squeal, skid, slide = wheelSqueal, wheelSkid, wheelSlide
		end
	end
	squeal *= tuning.squeal.volume
	skid *= tuning.skid.volume
	local squealPitch = TyreAudio.ease(slide, tuning.squeal.pitchSlide)
	local skidPitch = TyreAudio.ease(slide, tuning.skid.pitchSlide)
	return {
		squeal = squeal,
		squealSpeed = lerp(tuning.squeal.pitch, squealPitch),
		skid = skid,
		skidSpeed = lerp(tuning.skid.pitch, skidPitch),
	}
end

-- Scales both axles' volumes together so all four loops, as one amplitude, stay within `cap`.
function TyreAudio.limit(front: AxleMix, rear: AxleMix, cap: number)
	local level = math.sqrt(front.squeal ^ 2 + front.skid ^ 2 + rear.squeal ^ 2 + rear.skid ^ 2)
	if level <= cap then
		return
	end
	local scale = if level > 0 then cap / level else 0
	front.squeal *= scale
	front.skid *= scale
	rear.squeal *= scale
	rear.skid *= scale
end

local function quietAxle(tuning: Tuning): AxleMix
	return { squeal = 0, squealSpeed = tuning.squeal.pitch.from, skid = 0, skidSpeed = tuning.skid.pitch.from }
end

local function shaping(): Shaping
	return { gain = 0, low = 0, mid = 0, high = 0 }
end

function TyreAudio.new(tuning: Tuning): State
	assert(tuning.lockCut >= 0 and tuning.lockCut <= 1, "the lock cut is a share")
	assert(tuning.attack > 0 and tuning.release > 0, "volumes need half-lives")
	return {
		tuning = tuning,
		inside = 0,
		primed = false,
		mix = {
			front = quietAxle(tuning),
			rear = quietAxle(tuning),
			squealEq = shaping(),
			skidEq = shaping(),
		},
	}
end

local function follow(current: number, goal: number, tuning: Tuning, dt: number): number
	local halfLife = if goal > current then tuning.attack else tuning.release
	return current + (goal - current) * TyreAudio.blend(dt, halfLife)
end

local function stepAxle(
	into: AxleMix,
	goal: AxleMix,
	gainSqueal: number,
	gainSkid: number,
	tuning: Tuning,
	dt: number
)
	into.squeal = follow(into.squeal, goal.squeal * gainSqueal, tuning, dt)
	into.skid = follow(into.skid, goal.skid * gainSkid, tuning, dt)
	into.squealSpeed, into.skidSpeed = goal.squealSpeed, goal.skidSpeed
end

local function mixShaping(into: Shaping, a: Shaping, b: Shaping, t: number)
	into.gain = a.gain + (b.gain - a.gain) * t
	into.low = a.low + (b.low - a.low) * t
	into.mid = a.mid + (b.mid - a.mid) * t
	into.high = a.high + (b.high - a.high) * t
end

-- Advances the mix by `dt`. The ceiling applies to the volumes that play, after the easing and the
-- view's gain: an engine that falls faster than the release (a lock-up opening the clutch) still
-- has the tyres under it the same frame.
function TyreAudio.step(state: State, input: Input, dt: number): Mix
	local tuning, mix = state.tuning, state.mix
	local insideGoal = if input.cockpit then 1 else 0
	if state.primed then
		local reach = dt / tuning.viewSeconds
		state.inside += math.clamp(insideGoal - state.inside, -reach, reach)
	else
		state.inside = insideGoal
	end
	state.primed = true
	mixShaping(mix.squealEq, tuning.outside.squeal, tuning.cockpit.squeal, state.inside)
	mixShaping(mix.skidEq, tuning.outside.skid, tuning.cockpit.skid, state.inside)
	local gainSqueal = math.min(1, 10 ^ (mix.squealEq.gain / 20))
	local gainSkid = math.min(1, 10 ^ (mix.skidEq.gain / 20))
	local cap = TyreAudio.ceiling(tuning, input.engineLevel)
	local wetness = finite(input.wetness)
	local front = if input.driving then TyreAudio.axle(tuning, input.front, wetness) else quietAxle(tuning)
	local rear = if input.driving then TyreAudio.axle(tuning, input.rear, wetness) else quietAxle(tuning)
	stepAxle(mix.front, front, gainSqueal, gainSkid, tuning, dt)
	stepAxle(mix.rear, rear, gainSqueal, gainSkid, tuning, dt)
	TyreAudio.limit(mix.front, mix.rear, cap)
	return mix
end

return table.freeze(TyreAudio)
