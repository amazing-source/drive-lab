--!strict
--[[
	The automatic's gear selection on the pedals, for a keyboard or a pad, as GTA and Forza do it:
	at a standstill the brake held on its own selects reverse, and in reverse the accelerator held
	on its own selects first again. In reverse the pedals swap, so the brake key backs the car up
	and the accelerator key brakes it. It is input help (Config/InputHelp.reverseHoldTime), not the
	car: manual keeps the paddles' neutral and reverse, and a preset without the hold drives the
	pedals as they are.
]]
local Gearbox = require("./Gearbox")
local InputFilter = require("./InputFilter")
local InputHelp = require("../Config/InputHelp")
local Interface = require("./Interface")
local Types = require("../Config/Cars/Types")

-- A pedal past HELD asks for a gear only while the other is under LIFTED: both pedals at once
-- hold the car on the brake, which selects nothing.
local HELD = 0.5
local LIFTED = 0.1

export type SelectorState = {
	-- Seconds the pedal asking for the other direction has been held, on its own, at a standstill.
	held: number,
}

local Selector = {}

function Selector.newState(): SelectorState
	return { held = 0 }
end

function Selector.swapped(
	help: InputHelp.InputHelp,
	gearbox: Gearbox.GearboxState,
	mode: Gearbox.GearboxMode
): boolean
	return help.reverseHoldTime ~= nil and mode == "auto" and gearbox.gear < 0
end

-- The gear the device pedals ask for: reverse from a forward gear, first from reverse.
local function asked(gear: number, throttle: number, brake: number): number?
	if gear > 0 and brake >= HELD and throttle < LIFTED then
		return -1
	elseif gear < 0 and throttle >= HELD and brake < LIFTED then
		return 1
	end
	return nil
end

-- One frame of the device's pedals (before any swap). Neutral is the paddles' and is left alone.
-- While launch control can arm (`launchReady`), the brake is arming a launch and selects nothing;
-- reverse stays on the paddle there (#74).
function Selector.update(
	help: InputHelp.InputHelp,
	config: Types.GearboxConfig,
	gearbox: Gearbox.GearboxState,
	state: SelectorState,
	input: Interface.DriverInput,
	groundSpeed: number,
	launchReady: boolean,
	dt: number
)
	local hold = help.reverseHoldTime
	local target = if hold ~= nil
			and input.gearboxMode == "auto"
			and groundSpeed < config.selectorMaxSpeed
			and not launchReady
		then asked(gearbox.gear, input.throttle, input.brake)
		else nil
	if hold == nil or target == nil then
		state.held = 0
		return
	end
	state.held += dt
	if state.held >= hold and Gearbox.select(config, gearbox, target, groundSpeed) then
		state.held = 0
	end
end

-- The pedals the input filter reads, written into `out`: the device's, swapped in reverse.
function Selector.pedals(
	help: InputHelp.InputHelp,
	gearbox: Gearbox.GearboxState,
	input: Interface.DriverInput,
	out: InputFilter.RawControls
): InputFilter.RawControls
	local swap = Selector.swapped(help, gearbox, input.gearboxMode)
	out.steer, out.handbrake = input.steer, input.handbrake
	out.throttle = if swap then input.brake else input.throttle
	out.brake = if swap then input.throttle else input.brake
	return out
end

return table.freeze(Selector)
