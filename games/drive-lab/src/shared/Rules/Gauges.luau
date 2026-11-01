--!strict
--[[
	An analog cluster's needles (Config/Gauges): where a reading puts a needle on its dial, how the
	needle follows it, when the cluster is lit, and its optional start-up sweep.
]]
local Binding = require("../Config/Cars/Binding")
local CarEntryConfig = require("../Config/CarEntry")
local CarEntryRules = require("./CarEntry")
local Gauges = require("../Config/Gauges")
local Hinge = require("./Hinge")

-- Where a needle is, as a share of its travel, and how fast it moves (shares a second); `met`
-- once it has first reached its reading since the cluster lit.
export type Needle = { share: number, velocity: number, met: boolean }

local KMH_PER_MPH = 1.609344
local KPA_PER_PSI = 6.894757

-- The units each reading may be printed in.
local UNITS: { [Gauges.Reading]: { [Gauges.Unit]: boolean } } = {
	speed = { kmh = true, mph = true },
	rpm = { rpm = true },
	fuel = { share = true },
	coolant = { degC = true, degF = true },
	oilPressure = { kPa = true, psi = true },
}

local Rules = {}

function Rules.unitFits(reading: Gauges.Reading, unit: Gauges.Unit): boolean
	local units = UNITS[reading]
	return units ~= nil and units[unit] == true
end

-- A reading in its own unit (km/h, rpm, share, °C, kPa) in a dial's printed unit.
function Rules.convert(value: number, unit: Gauges.Unit): number
	if unit == "mph" then
		return value / KMH_PER_MPH
	elseif unit == "degF" then
		return value * 9 / 5 + 32
	elseif unit == "psi" then
		return value / KPA_PER_PSI
	end
	return value
end

-- The share of its travel a dial's needle points at for `value` in the reading's own unit.
function Rules.share(dial: Gauges.Dial, value: number): number
	local printed = Rules.convert(value, dial.unit)
	local scale = dial.scale
	if printed <= scale[1][1] then
		return scale[1][2]
	end
	for index = 2, #scale do
		local low, high = scale[index - 1], scale[index]
		if printed <= high[1] then
			return low[2] + (high[2] - low[2]) * (printed - low[1]) / (high[1] - low[1])
		end
	end
	return scale[#scale][2]
end

-- The turn (radians) from a bound needle's rest, the dial's zero, at `share` of its dial: its
-- measured sweep, not an assumed one. The rig's weld already rests the needle there.
function Rules.turn(needle: Binding.Hinge, share: number): number
	return share * (needle.travel or 0)
end

-- The needle's angle from its modelled pose at `share` of its dial, as the manifest's range
-- measures it: the zero's offset plus the turn.
function Rules.poseAngle(needle: Binding.Hinge, share: number): number
	return Hinge.restAngle(needle) + Rules.turn(needle, share)
end

function Rules.newNeedle(): Needle
	return { share = 0, velocity = 0, met = false }
end

--[[
	Moves a needle toward `target` over `dt` seconds as a critically damped spring with time
	constant `response`, its speed capped at `maxRate`. A step that would carry it past the target
	(a needle still moving toward a reading that changed in front of it) stops it there, so it never
	overshoots, as a stepper-motor cluster's does not.
]]
function Rules.step(needle: Needle, target: number, dt: number, response: number, maxRate: number)
	if dt <= 0 then
		return
	end
	local omega = 1 / response
	local error0 = needle.share - target
	local carry = needle.velocity + omega * error0
	local decay = math.exp(-omega * dt)
	local share = target + (error0 + carry * dt) * decay
	local velocity = (needle.velocity - omega * carry * dt) * decay
	local moved = math.clamp(share - needle.share, -maxRate * dt, maxRate * dt)
	share = needle.share + moved
	local error1 = share - target
	if error0 ~= 0 and (error1 == 0 or (error1 > 0) ~= (error0 > 0)) then
		share, velocity = target, 0
	end
	needle.share, needle.velocity = share, velocity
end

-- One frame of a dial's needle: the catch-up time constant until it first meets its reading.
function Rules.follow(needle: Needle, dial: Gauges.Dial, target: number, dt: number)
	local response = if needle.met then dial.response else dial.catchUp
	Rules.step(needle, target, dt, response, dial.maxRate)
	if math.abs(needle.share - target) <= Gauges.MET then
		needle.met = true
	end
end

-- Seconds into the start-up at which `control`'s first move arrives, or nil if it never moves.
function Rules.lightAt(startup: CarEntryConfig.Startup, control: string): number?
	local first: number? = nil
	for _, move in startup.moves do
		if move.control == control and (first == nil or move.at < first) then
			first = move.at
		end
	end
	return first
end

-- Seconds since the cluster lit, or nil while it is dark: from the start-up's `control` reaching
-- its first position until the engine is off.
function Rules.sinceLit(
	startup: CarEntryConfig.Startup,
	control: string,
	state: CarEntryRules.State,
	now: number
): number?
	if state.engine == "Off" then
		return nil
	end
	local since = now - state.engineAt - (Rules.lightAt(startup, control) or startup.pressAt)
	return if since >= 0 then since else nil
end

-- The share a needle sweeps to `sinceLit` seconds into a sweep of `seconds`, or nil once it ends.
function Rules.sweepShare(seconds: number?, sinceLit: number): number?
	if seconds == nil or sinceLit < 0 or sinceLit >= seconds then
		return nil
	end
	return math.sin(math.pi * sinceLit / seconds)
end

return table.freeze(Rules)
