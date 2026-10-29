--!strict
--[[
	Launch control, after the Aventador's procedure (research note 2026-10-29, section 1; the
	LP700-4's, nothing SVJ-specific found). In its drive mode with ESC off, stopped in first, the
	brake held and the accelerator floored arm it; the engine then holds the launch rpm, as it does
	whenever the brake holds the clutch open at a standstill (Gearbox, Model). Releasing the brake
	launches: traction control works the tyres at the launch's slip even with TC switched off,
	until the accelerator lifts, the brake comes back or the car passes the end speed. Lifting the
	accelerator before the release cancels it.
]]
local Interface = require("./Interface")
local Types = require("../Config/Cars/Types")

export type LaunchState = { phase: Interface.LaunchPhase }

-- The accelerator counts as floored from FULL; the brake as held from HELD and as released
-- under RELEASED, where the gearbox stops holding the clutch open.
local FULL = 0.95
local HELD = 0.5
local RELEASED = 0.1

local Launch = {}

function Launch.newState(): LaunchState
	return { phase = "Off" }
end

-- Whether the drive mode and ESC are as launch control needs them.
function Launch.selected(config: Types.LaunchConfig, input: Interface.DriverInput): boolean
	return input.drivingMode == config.mode and not input.assists.esc
end

-- Whether launch control can arm now: selected, stopped (under `standstill`, m/s) in first, not
-- mid-shift.
function Launch.available(
	config: Types.LaunchConfig,
	input: Interface.DriverInput,
	gear: number,
	shifting: boolean,
	groundSpeed: number,
	standstill: number
): boolean
	return Launch.selected(config, input) and gear == 1 and not shifting and groundSpeed < standstill
end

local function launchOver(
	config: Types.LaunchConfig,
	selected: boolean,
	throttle: number,
	brake: number,
	gear: number,
	groundSpeed: number
): boolean
	return not selected or throttle < FULL or brake >= RELEASED or gear < 1 or groundSpeed >= config.endSpeed
end

-- One frame, on the pedals the car gets (after the input filter).
function Launch.update(
	config: Types.LaunchConfig,
	state: LaunchState,
	selected: boolean,
	available: boolean,
	throttle: number,
	brake: number,
	gear: number,
	groundSpeed: number
)
	local phase = state.phase
	if phase == "Off" then
		if available and brake >= HELD and throttle >= FULL then
			state.phase = "Armed"
		end
	elseif phase == "Armed" then
		if not available or throttle < FULL then
			state.phase = "Off"
		elseif brake < RELEASED then
			state.phase = "Launching"
		end
	elseif launchOver(config, selected, throttle, brake, gear, groundSpeed) then
		state.phase = "Off"
	end
end

return table.freeze(Launch)
