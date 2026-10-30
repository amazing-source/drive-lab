--!strict
--[[
	The car camera's vibrations as angles, in plain numbers: the road's fine vibration rising with
	speed, the engine's rocking under throttle at low speed, a rumble on a hard launch, and the
	pitch kick of each upshift (the nose dips as the drive cuts, then the car squats as it bites).
	Smooth noise around wherever the camera is placed this frame, so it never lags behind the car.
]]
local CarShake = {}

-- How much of each part reaches the camera in a view; `lift` is metres of vertical jitter.
export type ViewShare = { road: number, engine: number, launch: number, shift: number, lift: number }

export type Range = { number }

export type Tuning = {
	-- Degrees of the road's vibration: `base` once rolling, plus `gain` * (speed / topKmh) ^
	-- exponent; its frequency (Hz) runs from hz[1] at rest to hz[2] at topKmh.
	road: { base: number, gain: number, exponent: number, topKmh: number, hz: Range },
	-- Degrees of engine vibration from closed to full throttle, its frequency, and the speeds
	-- over which it fades out under the road's.
	engine: { degrees: Range, hz: number, fadeKmh: Range },
	-- Degrees of rumble as longitudinal g goes from fromG to toG, fading out by fadeKmh.
	launch: { degrees: number, fromG: number, toG: number, fadeKmh: number, hz: number },
	-- The upshift's pitch: down to `down` degrees over `dip` s, up to `up` over `rise` s, back to
	-- level over `settle` s; scaled by the input's `shiftScale`.
	shift: { down: number, up: number, dip: number, rise: number, settle: number },
	-- Per view (Chase, Cockpit, Hood); a view not listed takes Chase's.
	views: { [string]: ViewShare },
	scale: number,
}

export type Input = {
	view: string,
	speedKmh: number,
	throttle: number,
	longitudinalG: number,
	gear: number,
	-- The share of the upshift's kick the car's gearbox gives in its drive mode.
	shiftScale: number,
}

-- Radians, and metres of lift.
export type Offset = { pitch: number, yaw: number, roll: number, lift: number }

export type State = {
	roadPhase: number,
	enginePhase: number,
	launchPhase: number,
	gear: number?,
	shiftAge: number,
	shiftScale: number,
	offset: Offset,
}

local function finite(value: number): number
	return if value == value and math.abs(value) < math.huge then value else 0
end

local function share(value: number, from: number, to: number): number
	return math.clamp((value - from) / (to - from), 0, 1)
end

-- Smooth noise in -1..1 along a phase, one independent track per channel.
local function noise(phase: number, channel: number): number
	return math.clamp(math.noise(phase, channel * 7.31 + 0.5, 0.37) * 1.6, -1, 1)
end

function CarShake.new(): State
	return {
		roadPhase = 0,
		enginePhase = 0,
		launchPhase = 0,
		gear = nil,
		shiftAge = math.huge,
		shiftScale = 0,
		offset = { pitch = 0, yaw = 0, roll = 0, lift = 0 },
	}
end

function CarShake.roadDegrees(speedKmh: number, tuning: Tuning): number
	local road = tuning.road
	local speed = math.abs(finite(speedKmh))
	local rolling = math.min(speed / 20, 1)
	return road.base * rolling + road.gain * share(speed, 0, road.topKmh) ^ road.exponent
end

function CarShake.engineDegrees(throttle: number, speedKmh: number, tuning: Tuning): number
	local engine = tuning.engine
	local open = math.clamp(finite(throttle), 0, 1)
	local degrees = engine.degrees[1] + (engine.degrees[2] - engine.degrees[1]) * open
	return degrees * (1 - share(math.abs(finite(speedKmh)), engine.fadeKmh[1], engine.fadeKmh[2]))
end

function CarShake.launchDegrees(longitudinalG: number, speedKmh: number, tuning: Tuning): number
	local launch = tuning.launch
	local pull = share(finite(longitudinalG), launch.fromG, launch.toG)
	return launch.degrees * pull * (1 - share(math.abs(finite(speedKmh)), 0, launch.fadeKmh))
end

-- Degrees of pitch `age` seconds after an upshift: negative dips the view.
function CarShake.shiftPitch(age: number, tuning: Tuning): number
	local shift = tuning.shift
	if age < 0 or age ~= age then
		return 0
	elseif age < shift.dip then
		return -shift.down * math.sin(age / shift.dip * math.pi / 2)
	elseif age < shift.dip + shift.rise then
		local t = (age - shift.dip) / shift.rise
		return -shift.down + (shift.up + shift.down) * (1 - math.cos(t * math.pi)) / 2
	elseif age < shift.dip + shift.rise + shift.settle then
		local t = (age - shift.dip - shift.rise) / shift.settle
		return shift.up * (1 + math.cos(t * math.pi)) / 2
	end
	return 0
end

-- Advances the vibrations by `dt` and returns this frame's offset.
function CarShake.step(state: State, input: Input, dt: number, tuning: Tuning): Offset
	dt = math.max(finite(dt), 0)
	local gear = finite(input.gear)
	local last = state.gear
	if last ~= nil and last >= 1 and gear > last then
		state.shiftAge = 0
		state.shiftScale = input.shiftScale
	else
		state.shiftAge += dt
	end
	state.gear = gear

	local road = tuning.road
	local speedShare = share(math.abs(finite(input.speedKmh)), 0, road.topKmh)
	state.roadPhase += (road.hz[1] + (road.hz[2] - road.hz[1]) * speedShare) * dt
	state.enginePhase += tuning.engine.hz * dt
	state.launchPhase += tuning.launch.hz * dt

	local view = tuning.views[input.view] or tuning.views.Chase
	local scale = tuning.scale
	local roadDeg = CarShake.roadDegrees(input.speedKmh, tuning) * view.road
	local engineDeg = CarShake.engineDegrees(input.throttle, input.speedKmh, tuning) * view.engine
	local launchDeg = CarShake.launchDegrees(input.longitudinalG, input.speedKmh, tuning) * view.launch
	local kick = CarShake.shiftPitch(state.shiftAge, tuning) * state.shiftScale * view.shift
	local rp, ep, lp = state.roadPhase, state.enginePhase, state.launchPhase

	local offset = state.offset
	offset.pitch = math.rad(
		scale * (roadDeg * noise(rp, 1) + engineDeg * 0.5 * noise(ep, 2) + launchDeg * noise(lp, 3) + kick)
	)
	offset.roll = math.rad(
		scale * (roadDeg * 0.6 * noise(rp, 4) + engineDeg * noise(ep, 5) + launchDeg * 0.5 * noise(lp, 6))
	)
	offset.yaw = math.rad(scale * (roadDeg * 0.25 * noise(rp, 7) + engineDeg * 0.2 * noise(ep, 8)))
	offset.lift = scale * view.lift * speedShare * noise(rp, 9)
	return offset
end

return table.freeze(CarShake)
