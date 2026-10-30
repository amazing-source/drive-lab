--!strict
--[[
	The windscreen wiper and washer, after the 458 Challenge's WIPER and WATER buttons (docs/research/
	12_dr458_challenge_evo.md §2). WIPER switches the wiper on and off; holding WATER sprays the
	screen and runs the wiper, which goes on for a few wipes after the spray stops. Switched off, the
	wiper finishes its sweep and parks. The sweep is a share from 0 (parked) to 1 (the far end).
]]
export type Tuning = {
	-- Seconds for one wipe, out and back.
	wipeSeconds: number,
	-- Wipes the wiper makes after the washer stops.
	afterWash: number,
}

export type State = {
	on: boolean,
	washing: boolean,
	-- Seconds into the current wipe; nil while parked.
	wipeAt: number?,
	-- Wipes still owed by the washer.
	owed: number,
}

local Wiper = {}

function Wiper.newState(): State
	return { on = false, washing = false, wipeAt = nil, owed = 0 }
end

-- The WIPER button.
function Wiper.toggle(state: State)
	state.on = not state.on
end

-- Advances the wiper by `dt` with the washer held or not.
function Wiper.step(state: State, tuning: Tuning, washerHeld: boolean, dt: number)
	if state.washing and not washerHeld then
		state.owed = tuning.afterWash
	end
	state.washing = washerHeld
	local running = state.on or state.washing or state.owed > 0
	if state.wipeAt == nil and not running then
		return
	end
	local at = (state.wipeAt or 0) + dt
	while at >= tuning.wipeSeconds do
		at -= tuning.wipeSeconds
		if not state.washing and state.owed > 0 then
			state.owed -= 1
		end
		if not (state.on or state.washing or state.owed > 0) then
			state.wipeAt = nil
			return
		end
	end
	state.wipeAt = at
end

-- How far the blade is from its parked position, 0 to 1: out over the first half of a wipe and
-- back over the second, easing at each end.
function Wiper.sweep(state: State, tuning: Tuning): number
	local at = state.wipeAt
	if at == nil then
		return 0
	end
	local phase = at / tuning.wipeSeconds
	return (1 - math.cos(phase * 2 * math.pi)) / 2
end

return table.freeze(Wiper)
