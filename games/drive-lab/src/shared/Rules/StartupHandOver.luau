--!strict
--[[
	The hand-over from a car's start-up one-shot to its engine loops: the loops' share each frame,
	and what the start-up's Sound has to do (Controllers/CarAudio plays it). The start-up is either
	the events file's region, faded in its file, or the car's own sound, faded here. Driving the
	revs past abortRpm, or a sound that never loads, hands over early and quickly.

	The Sound is read, not modelled: a one-shot is removed as it ends, and a removed Sound no
	longer reads as loaded.
]]
local EngineSound = require("./EngineSound")

-- Seconds after which a start-up that has not loaded is skipped rather than left holding the engine.
local LOAD_TIMEOUT = 3
-- An early hand-over is complete past this share.
local DONE_SHARE = 0.99

export type Region = { from: number, to: number }

export type Settings = {
	-- Seconds into the events file.
	region: Region,
	-- Seconds into the region where its fade-out, and so the hand-over, begins.
	handOver: number,
	abortRpm: number,
	abortHalfLife: number,
}

-- The car's own start-up sound, seconds into it: played from `from`, handed over from
-- `handOver` to `to`.
export type Own = { from: number, handOver: number, to: number }

-- What the start-up's Sound reads this frame.
export type Playback = {
	-- Still parented, and Sound.Playing (set by Play(), so true while it loads).
	playing: boolean,
	loaded: boolean,
	position: number,
}

export type State = {
	settings: Settings,
	own: Own?,
	-- os.clock() at the START press and when this start-up's Sound was made.
	pressedAt: number,
	startedAt: number,
	-- The loops' share once the start-up hands over early; nil until it does.
	handedOver: number?,
	caughtUp: boolean,
	-- The start-up's gain over its full volume, as last set.
	gain: number,
	-- The start-up is over: its Sound can go, and the loops play in full.
	done: boolean,
}

local StartupHandOver = {}

function StartupHandOver.new(settings: Settings, own: Own?, pressedAt: number, startedAt: number): State
	return {
		settings = settings,
		own = own,
		pressedAt = pressedAt,
		startedAt = startedAt,
		handedOver = nil,
		caughtUp = false,
		gain = 1,
		done = false,
	}
end

-- The loops' share this frame (0 to 1), then the start-up's gain over its full volume and the
-- playhead to move it to, each nil when the Sound keeps its own.
function StartupHandOver.step(
	state: State,
	playback: Playback,
	rpm: number,
	now: number,
	dt: number
): (number, number?, number?)
	if state.done then
		return 1, nil, nil
	end
	local settings = state.settings
	local ended = not playback.playing
	if state.own and state.handedOver == nil and ended then
		state.done = true
		return 1, nil, nil
	end
	if
		state.handedOver == nil
		and (rpm > settings.abortRpm or (not playback.loaded and now - state.startedAt > LOAD_TIMEOUT))
	then
		state.handedOver = 0
	end
	local handedOver = state.handedOver
	if handedOver then
		local step = EngineSound.blend(dt, settings.abortHalfLife)
		state.gain *= 1 - step
		local share = handedOver + (1 - handedOver) * step
		state.handedOver = share
		state.done = share > DONE_SHARE
		return share, state.gain, nil
	end
	if not playback.loaded then
		return 0, nil, nil
	end
	if ended then
		state.done = true
		return 1, nil, nil
	end
	local own = state.own
	if own then
		local position = playback.position
		local seek: number? = nil
		if not state.caughtUp then
			-- A playhead set before the sound loads is lost: it catches up with the engine here,
			-- the starter cut short by however late it loaded.
			state.caughtUp = true
			position = own.from + now - state.pressedAt
			seek = position
		end
		local share, gain = EngineSound.handOver(own.handOver, own.to, position)
		state.gain = gain
		return share, gain, seek
	end
	local region = settings.region
	local length = region.to - region.from
	local progress =
		math.clamp((playback.position - region.from - settings.handOver) / (length - settings.handOver), 0, 1)
	return math.sin(progress * math.pi / 2), nil, nil
end

return table.freeze(StartupHandOver)
