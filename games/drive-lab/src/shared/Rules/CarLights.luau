--!strict
--[[
	What a car's lamps show for a given state, as the Aventador S and SVJ behave (sources in
	Config/CarLights): nothing lit until the ignition is on; running lights then, dimmed with the
	headlights and out on the side whose indicator runs; headlights by mode (automatic at night or
	in heavy rain), with the high beam on top of them when the driver asks for it, or on its own
	while a flasher is held; tail lights with the headlights; brake and reversing lights; indicators
	that flash from the moment they are switched on; a rear rain light, steady or flashing as the
	car's is; and the cabin light, which works with the ignition off.
]]
local CarLights = {}

export type Mode = "Auto" | "On" | "Off"
export type Side = "Left" | "Right"

export type State = {
	-- The ignition is on: from the START press while the engine runs.
	running: boolean,
	mode: Mode,
	-- The driver has the high beam selected; it shines only while the headlights are on.
	highBeam: boolean,
	-- The driver holds a headlight flasher: the high beam shines with the headlights on or off.
	flash: boolean?,
	night: boolean,
	rain: number,
	brake: number,
	gear: number,
	indicator: Side?,
	-- Seconds since the indicator was switched on.
	indicating: number,
	cabin: boolean,
	-- The rain light's switch, and seconds since it was switched on.
	rainLight: boolean?,
	rainLightFor: number?,
}

-- How a car's rain light shows while switched on: flashing at `hz`, lit for `onShare` of each
-- period, or steady at an `hz` of 0.
export type RainPattern = { hz: number, onShare: number }

export type Tuning = {
	rainOn: number,
	brakeOn: number,
	blinkHz: number,
	-- Share of each flash period the lamp is lit.
	blinkOnShare: number,
	-- The running lights' level with the headlights on, and on the indicator's side while it runs.
	drlWithHeadlights: number,
	drlWhileIndicating: number,
	-- The projector's glow on high beam, a share of its low-beam glow.
	highBeamLevel: number,
}

export type Lit = {
	headlights: boolean,
	highBeam: boolean,
	drlLeft: number,
	drlRight: number,
	tail: boolean,
	brake: boolean,
	reverse: boolean,
	left: boolean,
	right: boolean,
	cabin: boolean,
	-- The rain light switched on with the ignition, and whether its lamp is lit this instant.
	rainLightOn: boolean,
	rainLight: boolean,
}

export type Levels = {
	drlLeft: number,
	drlRight: number,
	projector: number,
	left: number,
	right: number,
	position: number,
	tail: number,
	stop: number,
	reverse: number,
	rain: number,
}

export type Press = { since: number?, spent: boolean }
export type Gesture = "Tap" | "Hold"

local MODES: { Mode } = { "Auto", "On", "Off" }

-- The next headlight mode, cycling Auto, On, Off.
function CarLights.nextMode(mode: Mode): Mode
	local index = table.find(MODES, mode) or 1
	return MODES[index % #MODES + 1]
end

-- Whether a flashing lamp is lit `elapsed` seconds after it was switched on: a flasher starts
-- with the lamp lit, then holds each period's lit share.
function CarLights.blinkOn(elapsed: number, hz: number, onShare: number): boolean
	return (math.max(elapsed, 0) * hz) % 1 < onShare
end

local function drl(side: Side, state: State, headlights: boolean, tuning: Tuning): number
	if not state.running then
		return 0
	end
	if state.indicator == side then
		return tuning.drlWhileIndicating
	end
	return if headlights then tuning.drlWithHeadlights else 1
end

-- Whether a switched-on rain light is lit `elapsed` seconds after it was switched on.
function CarLights.rainLit(elapsed: number, pattern: RainPattern?): boolean
	if pattern == nil or pattern.hz <= 0 then
		return true
	end
	return CarLights.blinkOn(elapsed, pattern.hz, pattern.onShare)
end

function CarLights.decide(state: State, tuning: Tuning, rainPattern: RainPattern?): Lit
	local running = state.running
	local auto = state.night or state.rain >= tuning.rainOn
	local headlights = running and (state.mode == "On" or (state.mode == "Auto" and auto))
	local flash = running and CarLights.blinkOn(state.indicating, tuning.blinkHz, tuning.blinkOnShare)
	return {
		headlights = headlights,
		highBeam = running and ((headlights and state.highBeam) or state.flash == true),
		drlLeft = drl("Left", state, headlights, tuning),
		drlRight = drl("Right", state, headlights, tuning),
		tail = headlights,
		brake = running and state.brake >= tuning.brakeOn,
		reverse = running and state.gear < 0,
		left = state.indicator == "Left" and flash,
		right = state.indicator == "Right" and flash,
		cabin = state.cabin,
		rainLightOn = running and state.rainLight == true,
		rainLight = running
			and state.rainLight == true
			and CarLights.rainLit(state.rainLightFor or 0, rainPattern),
	}
end

-- The pad's lights button steps the headlights Auto, On, high beam, Off and round again; a high
-- beam selected from the keyboard in Auto counts as Auto.
function CarLights.nextPadLights(mode: Mode, highBeam: boolean): (Mode, boolean)
	if mode == "Auto" then
		return "On", false
	elseif mode == "On" and not highBeam then
		return "On", true
	elseif mode == "On" then
		return "Off", false
	end
	return "Auto", false
end

-- Each lamp's output as a share of its full: the projector at `highBeamLevel` on high beam; the
-- Y tail lamps burn at `tailShare` of their brake output; the markers and plate lamps are
-- position lamps, lit with the tail lamps.
function CarLights.levels(lit: Lit, tailShare: number, highBeamLevel: number): Levels
	local function on(flag: boolean): number
		return if flag then 1 else 0
	end
	return {
		drlLeft = lit.drlLeft,
		drlRight = lit.drlRight,
		projector = if lit.highBeam then highBeamLevel elseif lit.headlights then 1 else 0,
		left = on(lit.left),
		right = on(lit.right),
		position = on(lit.tail),
		tail = if lit.brake then 1 elseif lit.tail then tailShare else 0,
		stop = on(lit.brake),
		reverse = on(lit.reverse),
		rain = on(lit.rainLight),
	}
end

-- Whether the cockpit's tell-tale for `switch` is lit: it shows the switch, so a flashing rain
-- light's tell-tale stays steady. Unknown switches stay dark.
function CarLights.tellTale(switch: string, lit: Lit): boolean
	if switch == "headlights" then
		return lit.headlights
	elseif switch == "highBeam" then
		return lit.highBeam
	elseif switch == "rainLight" then
		return lit.rainLightOn
	end
	return false
end

-- How much of an LED's full colour it shows (0 to 1) at a glow `strength`, against its day
-- strength: Neon has no strength of its own, its glow follows how bright its colour is.
function CarLights.ledShare(strength: number, day: number): number
	if day <= 0 then
		return 0
	end
	return math.clamp(strength / day, 0, 1)
end

-- A lamp's EmissiveStrength at `level` of its output, between its night and day strengths.
function CarLights.strength(level: number, night: number, day: number, daylight: number): number
	return level * (night + (day - night) * daylight)
end

-- How much of the day's light the scene has, 0 at night to 1 by day, from Lighting.Brightness
-- between the two the weather presets use. Lamps are drawn brighter by day: Roblox has no eye
-- that adapts, so a lamp that reads in sunlight would glare at night at the same strength.
function CarLights.daylight(brightness: number, night: number, day: number): number
	return math.clamp((brightness - night) / (day - night), 0, 1)
end

-- A button that does one thing on a tap and another on a hold, polled every frame: "Hold" once,
-- when it has been down `hold` seconds; "Tap" when it comes up before that.
function CarLights.press(press: Press, down: boolean, now: number, hold: number): Gesture?
	if down then
		local since = press.since
		if since == nil then
			press.since = now
			press.spent = false
		elseif not press.spent and now - since >= hold then
			press.spent = true
			return "Hold"
		end
		return nil
	end
	local wasDown = press.since ~= nil
	press.since = nil
	if wasDown and not press.spent then
		return "Tap"
	end
	return nil
end

return table.freeze(CarLights)
