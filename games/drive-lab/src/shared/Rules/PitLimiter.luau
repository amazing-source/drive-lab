--!strict
--[[
	The pit-lane speed limiter, after the 458 Challenge's PIT button (docs/research/
	12_dr458_challenge_evo.md §3.3): pressed in the arming gear below the arming speed, it arms, and
	the throttle then holds the limit. Pressed again it releases, and so does a shift down past the
	arming gear (Drive Lab's rule: no source says how the real one releases).
]]
export type Tuning = {
	-- km/h the car is held at.
	limitKmh: number,
	-- It arms only in this gear, and below this speed.
	armGear: number,
	armBelowKmh: number,
	-- km/h under the limit where the throttle starts to be taken away; at the limit none is left.
	band: number,
}

export type State = { armed: boolean }

local PitLimiter = {}

function PitLimiter.newState(): State
	return { armed = false }
end

-- The PIT button: releases an armed limiter, or arms one when the car is in the arming gear below
-- the arming speed. Returns whether it is armed after the press.
function PitLimiter.press(state: State, tuning: Tuning, gear: number, speedKmh: number): boolean
	if state.armed then
		state.armed = false
	elseif gear == tuning.armGear and speedKmh < tuning.armBelowKmh then
		state.armed = true
	end
	return state.armed
end

-- Releases the limiter once the car is in a gear below the arming gear (reverse and neutral
-- included).
function PitLimiter.update(state: State, tuning: Tuning, gear: number)
	if gear < tuning.armGear then
		state.armed = false
	end
end

-- The throttle the engine gets: the pedal, capped while armed so the car settles at the limit.
function PitLimiter.throttle(state: State, tuning: Tuning, pedal: number, speedKmh: number): number
	if not state.armed then
		return pedal
	end
	local cap = math.clamp((tuning.limitKmh - speedKmh) / tuning.band, 0, 1)
	return math.min(pedal, cap)
end

return table.freeze(PitLimiter)
