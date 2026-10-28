--!strict
--[[
	What a car's lights show for a given state: headlights by mode (automatic at night or in heavy
	rain), brake lights on the pedal, reversing lights in reverse, and an indicator's blink.
]]
local CarLights = {}

export type Mode = "Auto" | "On" | "Off"
export type Side = "Left" | "Right"

export type State = {
	mode: Mode,
	night: boolean,
	rain: number,
	brake: number,
	gear: number,
	indicator: Side?,
	time: number,
}

export type Tuning = {
	rainOn: number,
	brakeOn: number,
	blinkHz: number,
}

export type Lit = {
	headlights: boolean,
	brake: boolean,
	reverse: boolean,
	left: boolean,
	right: boolean,
}

local MODES: { Mode } = { "Auto", "On", "Off" }

-- The next headlight mode, cycling Auto, On, Off.
function CarLights.nextMode(mode: Mode): Mode
	local index = table.find(MODES, mode) or 1
	return MODES[index % #MODES + 1]
end

-- Whether a blinking light is in its lit half at `time` seconds: half a period on, half off.
function CarLights.blinkOn(time: number, hz: number): boolean
	return (time * hz) % 1 < 0.5
end

function CarLights.decide(state: State, tuning: Tuning): Lit
	local auto = state.night or state.rain >= tuning.rainOn
	local blink = CarLights.blinkOn(state.time, tuning.blinkHz)
	return {
		headlights = state.mode == "On" or (state.mode == "Auto" and auto),
		brake = state.brake >= tuning.brakeOn,
		reverse = state.gear < 0,
		left = state.indicator == "Left" and blink,
		right = state.indicator == "Right" and blink,
	}
end

return table.freeze(CarLights)
