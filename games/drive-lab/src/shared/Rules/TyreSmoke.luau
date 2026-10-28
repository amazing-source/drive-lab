--!strict
--[[
	How much smoke each tyre makes. Rubber smokes when its contact patch slides over the road
	hard enough to heat it: past the slip of peak grip, where the patch slides rather than
	grips, and fast, since a creeping wheel heats nothing. A wheel's share needs both. A wet road
	cools the tyre and makes none (CarWater's spray takes over there), and a wheel off the
	ground reads no slip. All the wheels together are capped, so the cost has a ceiling.
]]
local Interface = require("../Vehicle/Interface")
local Model = require("../Vehicle/Model")

export type Range = { from: number, to: number }

export type Thresholds = {
	-- Combined slip over the slip at peak grip (1 is the limit of grip).
	slip: Range,
	-- m/s the contact patch slides over the road.
	slide: Range,
	-- Road wetness (0 to 1): all the smoke up to `from`, none from `to`.
	wet: Range,
	-- Particles a second from one wheel at its full share, and from every wheel together.
	rate: number,
	totalRate: number,
	-- Half-lives (s) of a wheel's smoke building as the tread heats and dying as it cools; a
	-- one-frame spike in the slip makes next to none.
	rise: number,
	fall: number,
}

export type Throw = {
	-- The smoke leaves the patch at this share of the slide speed (m/s), within min and max.
	share: number,
	min: number,
	max: number,
}

-- One tyre's readings, as Driving publishes them.
export type Wheel = { slip: number, slide: number }

local SETTLED = 1e-3

local TyreSmoke = {}

local function finite(value: number): number
	if value ~= value or value == math.huge or value == -math.huge then
		return 0
	end
	return value
end

-- 0 at `range.from`, 1 at `range.to`, eased at both ends so smoke starts and stops softly.
local function ease(value: number, range: Range): number
	if range.to <= range.from then
		return 0
	end
	local t = math.clamp((finite(value) - range.from) / (range.to - range.from), 0, 1)
	return t * t * (3 - 2 * t)
end

-- m/s the contact patch slides over the road: the tyre's surface speed less the road's speed
-- under it along the wheel, and all of the road's speed across it.
function TyreSmoke.slideSpeed(surfaceSpeed: number, groundSpeed: number, lateralSpeed: number): number
	local along = finite(surfaceSpeed) - finite(groundSpeed)
	local across = finite(lateralSpeed)
	return math.sqrt(along * along + across * across)
end

-- Each tyre's readings from the vehicle model's last step, into `into` (reused). Reads only.
function TyreSmoke.measure(
	state: Model.VehicleState,
	wheels: { Interface.WheelResult },
	into: { Wheel }
): { Wheel }
	for wheel, result in wheels do
		local reading: Wheel = into[wheel] or { slip = 0, slide = 0 }
		reading.slip = result.combinedSlip
		reading.slide = if state.grounded[wheel]
			then TyreSmoke.slideSpeed(
				state.spins[wheel] * state.tyres[wheel].radius,
				state.ground[wheel],
				state.lateral[wheel]
			)
			else 0
		into[wheel] = reading
	end
	return into
end

-- One wheel's share of its full smoke, 0 to 1.
function TyreSmoke.share(wheel: Wheel, thresholds: Thresholds): number
	return ease(wheel.slip, thresholds.slip) * ease(wheel.slide, thresholds.slide)
end

-- How much of the smoke a road of `wetness` lets through, 0 to 1.
function TyreSmoke.dryShare(wetness: number, thresholds: Thresholds): number
	return 1 - ease(wetness, thresholds.wet)
end

-- A wheel's smoke share moved toward `target` over `dt` seconds, by half each half-life.
function TyreSmoke.follow(current: number, target: number, dt: number, thresholds: Thresholds): number
	local halfLife = if target > current then thresholds.rise else thresholds.fall
	if dt ~= dt or dt <= 0 then
		return current
	end
	if halfLife <= 0 then
		return target
	end
	local moved = target + (current - target) * 0.5 ^ (dt / halfLife)
	-- Settles exactly, so a cooled tyre's emitter rests at a rate of 0 rather than a trickle.
	return if math.abs(moved - target) < SETTLED then target else moved
end

-- Particles a second for each wheel, written into `into`, scaled down together when their sum
-- would pass the total cap. `heats` holds each wheel's smoke share between frames.
function TyreSmoke.rates(
	wheels: { Wheel },
	wetness: number,
	thresholds: Thresholds,
	heats: { number },
	dt: number,
	into: { number }
): { number }
	local dry = TyreSmoke.dryShare(wetness, thresholds)
	local total = 0
	for index, wheel in wheels do
		local heat =
			TyreSmoke.follow(heats[index] or 0, TyreSmoke.share(wheel, thresholds) * dry, dt, thresholds)
		heats[index] = heat
		local rate = thresholds.rate * heat
		into[index] = rate
		total += rate
	end
	if total > thresholds.totalRate then
		local scale = thresholds.totalRate / total
		for index in wheels do
			into[index] *= scale
		end
	end
	return into
end

-- m/s the smoke is thrown from the patch, from how fast it slides.
function TyreSmoke.throwSpeed(slide: number, throw: Throw): number
	return math.clamp(math.abs(finite(slide)) * throw.share, throw.min, throw.max)
end

return table.freeze(TyreSmoke)
