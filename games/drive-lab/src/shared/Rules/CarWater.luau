--!strict
--[[
	The water a car throws and catches in the rain: spray off the rear tyres, which grows with
	speed and with how wet the road is, and drops splashing on the bodywork, which follow the
	rain and stop under a roof. Every rate is capped per emitter, so the cost has a ceiling
	whatever the weather or the speed.
]]
export type Spray = {
	-- No spray below minSpeed (km/h); all of it from fullSpeed.
	minSpeed: number,
	fullSpeed: number,
	-- Below this road wetness the tyres throw nothing; a fully wet road throws all of it.
	wetFrom: number,
	-- Particles per second per emitter at full speed on a soaked road.
	rate: number,
}

export type Splashes = {
	-- Splashes per second per square metre of bodywork in full rain.
	perArea: number,
	exponent: number,
	-- The most one emitter may emit per second.
	maxRate: number,
}

local CarWater = {}

local function unit(value: number): number
	if value ~= value then
		return 0
	end
	return math.clamp(value, 0, 1)
end

-- How much of the spray a speed (km/h, either direction) raises: 0 to 1.
function CarWater.speedShare(speedKmh: number, spray: Spray): number
	local speed = math.abs(speedKmh)
	if speed ~= speed or speed == math.huge or spray.fullSpeed <= spray.minSpeed then
		return 0
	end
	return unit((speed - spray.minSpeed) / (spray.fullSpeed - spray.minSpeed))
end

-- How much of the spray a road wetness (0 to 1) allows: 0 to 1.
function CarWater.wetShare(wetness: number, spray: Spray): number
	if spray.wetFrom >= 1 then
		return 0
	end
	return unit((unit(wetness) - spray.wetFrom) / (1 - spray.wetFrom))
end

-- Spray particles per second for one emitter.
function CarWater.spray(speedKmh: number, wetness: number, spray: Spray): number
	return spray.rate * CarWater.speedShare(speedKmh, spray) * CarWater.wetShare(wetness, spray)
end

-- Splashes per second on a patch of bodywork of `area` square metres, in rain of `intensity`,
-- with `exposure` the share of it open to the sky.
function CarWater.splashes(intensity: number, exposure: number, area: number, splashes: Splashes): number
	local open = math.max(if area ~= area then 0 else area, 0)
	local rate = splashes.perArea * open * unit(intensity) ^ splashes.exponent * unit(exposure)
	return math.min(rate, splashes.maxRate)
end

return table.freeze(CarWater)
