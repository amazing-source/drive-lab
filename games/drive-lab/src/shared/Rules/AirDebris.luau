--!strict
--[[
	The air a fast car drives through: a little dust, grit and the odd leaf hanging in it, or
	fine water when the road is wet. The debris is left at rest in the world, so it is the car's
	own motion that brings it past the camera, at the speed the road goes by. It is emitted in
	slabs of air beside and above the path the car will take a moment from now, never in the
	path itself, so nothing passes through the car.

	For an even density in the air, a slab must emit what the car sweeps through it: density
	times the slab's cross-section times the speed. Every rate is capped.
]]
export type Speeds = {
	-- km/h: no debris below `from`, its full density from `to`, eased by `exponent`.
	from: number,
	to: number,
	exponent: number,
}

local AirDebris = {}

local function finite(value: number): number
	if value ~= value or value == math.huge or value == -math.huge then
		return 0
	end
	return value
end

-- How much of its full density the air shows at a speed (km/h, either way), 0 to 1.
function AirDebris.speedShare(kmh: number, speeds: Speeds): number
	if speeds.to <= speeds.from then
		return 0
	end
	local share = math.clamp((math.abs(finite(kmh)) - speeds.from) / (speeds.to - speeds.from), 0, 1)
	return share ^ speeds.exponent
end

-- The share of the debris that is water on a road of `wetness`: none below `from`, all from `to`.
function AirDebris.waterShare(wetness: number, from: number, to: number): number
	if to <= from then
		return if finite(wetness) >= to then 1 else 0
	end
	return math.clamp((finite(wetness) - from) / (to - from), 0, 1)
end

-- Particles a second for a slab of `area` square metres swept at `speed` m/s through air
-- holding `density` particles a cubic metre, at `share` of it, never above `cap`.
function AirDebris.rate(density: number, area: number, speed: number, share: number, cap: number): number
	local rate = finite(density)
		* math.max(finite(area), 0)
		* math.abs(finite(speed))
		* math.max(finite(share), 0)
	return math.min(rate, cap)
end

-- Where the car will be `seconds` from now, from its speed and how fast its path turns (rad/s,
-- positive to the right): distance ahead and to the right, in the speed's units times seconds,
-- and the heading turned by then (rad, positive right). A steady arc, which over the fraction
-- of a second this looks ahead is close enough to keep the slabs off the path in a bend.
function AirDebris.ahead(speed: number, turnRate: number, seconds: number): (number, number, number)
	local v, omega, t = finite(speed), finite(turnRate), finite(seconds)
	local heading = omega * t
	if math.abs(heading) < 1e-6 then
		return v * t, 0, heading
	end
	return v * math.sin(heading) / omega, v * (1 - math.cos(heading)) / omega, heading
end

-- Scales `rates` (any keys) in place so they sum to at most `cap`; returns the scale used.
function AirDebris.cap<K>(rates: { [K]: number }, cap: number): number
	local total = 0
	for _, rate in rates do
		total += rate
	end
	if total <= cap or total <= 0 then
		return 1
	end
	local scale = cap / total
	for key, rate in rates do
		rates[key] = rate * scale
	end
	return scale
end

return table.freeze(AirDebris)
