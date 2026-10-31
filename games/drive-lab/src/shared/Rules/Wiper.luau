--!strict
--[[
	The windscreen wiper and washer, after the 458 Challenge's WIPER and WATER buttons (docs/research/
	12_dr458_challenge_evo.md §2). WIPER steps the wiper through its speeds and back to off; holding
	WATER sprays the screen and runs the wiper at its first speed (or faster, if it is already),
	and the wiper goes on for a few wipes after the spray stops. Switched off, the wiper finishes its
	sweep at the speed it had and parks. The sweep is a share from 0 (parked) to 1 (the far end).
]]
export type Tuning = {
	-- Seconds for one wipe, out and back, at each speed step, slowest first.
	speeds: { number },
	-- Wipes the wiper makes after the washer stops.
	afterWash: number,
}

export type State = {
	-- The speed step switched on: 0 for off.
	speed: number,
	washing: boolean,
	-- Share of the current wipe done, 0 to 1; nil while parked.
	phase: number?,
	-- Seconds the current wipe takes.
	wipeSeconds: number,
	-- Wipes still owed by the washer.
	owed: number,
}

local Wiper = {}

function Wiper.newState(tuning: Tuning): State
	return { speed = 0, washing = false, phase = nil, wipeSeconds = tuning.speeds[1], owed = 0 }
end

-- The WIPER button: the next speed step, and off after the fastest.
function Wiper.cycle(state: State, tuning: Tuning)
	state.speed = (state.speed + 1) % (#tuning.speeds + 1)
end

-- The speed step the wiper runs at: the switch's, or the first while the washer wants wipes.
local function running(state: State): number
	local washer = if state.washing or state.owed > 0 then 1 else 0
	return math.max(state.speed, washer)
end

-- Advances the wiper by `dt` with the washer held or not. A change of speed keeps the blade where
-- it is on the glass.
function Wiper.step(state: State, tuning: Tuning, washerHeld: boolean, dt: number)
	if state.washing and not washerHeld then
		state.owed = tuning.afterWash
	end
	state.washing = washerHeld
	local step = running(state)
	if state.phase == nil and step == 0 then
		return
	end
	if step > 0 then
		state.wipeSeconds = tuning.speeds[step]
	end
	local phase = (state.phase or 0) + dt / state.wipeSeconds
	while phase >= 1 do
		phase -= 1
		if not state.washing and state.owed > 0 then
			state.owed -= 1
		end
		if running(state) == 0 then
			state.phase = nil
			return
		end
	end
	state.phase = phase
end

-- How far the blade is from its parked position, 0 to 1: out over the first half of a wipe and
-- back over the second, easing at each end.
function Wiper.sweep(state: State): number
	local phase = state.phase
	if phase == nil then
		return 0
	end
	return (1 - math.cos(phase * 2 * math.pi)) / 2
end

return table.freeze(Wiper)
