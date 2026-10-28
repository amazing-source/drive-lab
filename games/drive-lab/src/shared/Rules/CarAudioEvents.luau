--!strict
--[[
	Reads the car's sound events off its per-frame readouts. The readouts are the engine's own
	throttle, after the gearbox's shift cut and the limiter's fuel cut, so a closed throttle is
	not on its own a lift: a lift is a throttle that was open and closes at high rpm outside a
	shift, the limiter and traction control. The limiter flag itself is only true during each
	cut, so it is held across the bounce.
]]

export type Readout = {
	rpm: number,
	throttle: number,
	gear: number,
	shifting: boolean,
	limiter: boolean,
	tcActive: boolean,
}

export type Tuning = {
	-- A lift arms once the throttle reaches liftFrom and fires when it falls to liftTo.
	liftFrom: number,
	liftTo: number,
	liftMinRpm: number,
	-- Seconds the limiter counts as active after its last cut.
	limiterHold: number,
}

export type Events = {
	-- A shift began: the gearbox cut the torque.
	cut: boolean,
	-- A new gear engaged, and which way.
	gear: ("Up" | "Down")?,
	-- The throttle closed at high rpm.
	lift: boolean,
	-- The limiter is bouncing.
	limiter: boolean,
}

export type State = {
	tuning: Tuning,
	previous: Readout?,
	armed: boolean,
	limiterAge: number,
}

local CarAudioEvents = {}

function CarAudioEvents.new(tuning: Tuning): State
	return { tuning = tuning, previous = nil, armed = false, limiterAge = math.huge }
end

function CarAudioEvents.step(state: State, readout: Readout, dt: number): Events
	local tuning = state.tuning
	local previous = state.previous
	state.limiterAge = if readout.limiter then 0 else state.limiterAge + dt
	local limiter = state.limiterAge <= tuning.limiterHold
	local events: Events = { cut = false, gear = nil, lift = false, limiter = limiter }
	if previous then
		events.cut = readout.shifting and not previous.shifting
		if readout.gear ~= previous.gear then
			events.gear = if readout.gear > previous.gear then "Up" else "Down"
		end
	end
	local quiet = readout.shifting or limiter or readout.tcActive
	if readout.throttle >= tuning.liftFrom and not quiet then
		state.armed = true
	elseif readout.throttle <= tuning.liftTo and state.armed and not quiet then
		state.armed = false
		events.lift = readout.rpm >= tuning.liftMinRpm
	end
	state.previous = readout
	return events
end

return table.freeze(CarAudioEvents)
