--!strict
--[[
	The pit-lane speed limiter, after the 458 Challenge's PIT button (docs/research/
	12_dr458_challenge_evo.md §3.3). Pressed in one of its arming gears, and below its arming speed
	where it has one, it arms: the throttle then cannot take the car past the limit, and above the
	limit it gives none at all, so the car slows by itself; it never brakes. Pressed again it
	releases, and so does a shift down past its lowest arming gear, or a drive mode it does not
	work in.
]]
export type Tuning = {
	-- km/h the car is held at.
	limitKmh: number,
	-- It arms in a gear from armFromGear up to armToGear (any forward gear above when nil), and
	-- only below armBelowKmh when that is set.
	armFromGear: number,
	armToGear: number?,
	armBelowKmh: number?,
	-- km/h under the limit where the throttle starts to be taken away; at the limit none is left.
	band: number,
	-- Whether both indicators flash while it is armed.
	hazards: boolean,
	-- The drive modes it works in (the Boss 302's TracKey); any when nil.
	modes: { string }?,
}

export type State = { armed: boolean }

local PitLimiter = {}

function PitLimiter.newState(): State
	return { armed = false }
end

-- Whether the limiter works in drive mode `mode`.
local function inMode(tuning: Tuning, mode: string?): boolean
	local modes = tuning.modes
	return modes == nil or (mode ~= nil and table.find(modes, mode) ~= nil)
end

-- Whether a press in `gear` at `speedKmh`, in drive mode `mode`, arms the limiter.
function PitLimiter.canArm(tuning: Tuning, gear: number, speedKmh: number, mode: string?): boolean
	local below = tuning.armBelowKmh
	return gear >= tuning.armFromGear
		and gear <= (tuning.armToGear or math.huge)
		and (below == nil or speedKmh < below)
		and inMode(tuning, mode)
end

-- The PIT button: releases an armed limiter, or arms one when PitLimiter.canArm allows it.
-- Returns whether it is armed after the press.
function PitLimiter.press(
	state: State,
	tuning: Tuning,
	gear: number,
	speedKmh: number,
	mode: string?
): boolean
	if state.armed then
		state.armed = false
	elseif PitLimiter.canArm(tuning, gear, speedKmh, mode) then
		state.armed = true
	end
	return state.armed
end

-- Releases the limiter once the car is in a gear below its lowest arming gear, or in a drive mode
-- it does not work in.
function PitLimiter.update(state: State, tuning: Tuning, gear: number, mode: string?)
	if gear < tuning.armFromGear or not inMode(tuning, mode) then
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
