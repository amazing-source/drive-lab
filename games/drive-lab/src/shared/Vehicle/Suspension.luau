--!strict
--[[
	One corner's vertical force (01 §2.2): a linear spring sized from a ride frequency, a
	two-slope damper with separate bump and rebound, a progressive bump stop, and anti-roll
	bars as an equal and opposite force pair across each axle.

	The wheel is massless, which removes the ~14 Hz wheel-hop mode (01 §5.2 point 4), so the
	chassis carries the unsprung mass too: the spring is preloaded for the whole corner weight
	while its rate comes from the sprung mass, as the ride-frequency rule defines it. A massless
	wheel cannot pull the body down, so a corner never pushes with less than zero.
]]
local Geometry = require("./Geometry")
local Types = require("../Config/Cars/Types")
local World = require("../Config/World")

export type Corner = {
	wheelRate: number,
	-- Compression where the spring is at its free length; negative when it is preloaded at full
	-- extension.
	freeCompression: number,
	criticalDamping: number,
	antiRollRate: number,
}

export type Suspension = {
	corners: { Corner },
	config: Types.SuspensionConfig,
}

local Suspension = {}

-- k = m·(2π·f)², the rate that gives `frequency` on `mass`.
function Suspension.wheelRate(mass: number, frequency: number): number
	local omega = 2 * math.pi * frequency
	return mass * omega * omega
end

-- Anti-roll rates (N/m at the wheel) that make the roll gradient and front share in the
-- config. Tyre forces act at the ground, so the roll moment arm is the full CG height; the
-- springs already give ½·k·t² per axle and the bars add k_bar·t².
local function antiRollRates(car: Types.CarConfig, rates: { number }): (number, number)
	local suspension = car.suspension
	local rollMomentPerG = car.mass * World.GRAVITY_MPS2 * car.cgHeight
	local total = rollMomentPerG / suspension.rollGradient
	local frontTrack, rearTrack = car.front.track, car.rear.track
	local springsFront = 0.5 * frontTrack * frontTrack * rates[1]
	local springsRear = 0.5 * rearTrack * rearTrack * rates[3]
	local front = math.max(0, total * suspension.frontRollShare - springsFront) / (frontTrack * frontTrack)
	local rear = math.max(0, total * (1 - suspension.frontRollShare) - springsRear) / (rearTrack * rearTrack)
	return front, rear
end

function Suspension.prepare(car: Types.CarConfig): Suspension
	local rates = table.create(Geometry.WHEELS, 0)
	for wheel = 1, Geometry.WHEELS do
		local axle = Geometry.axle(car, wheel)
		rates[wheel] = Suspension.wheelRate(Geometry.sprungCornerMass(car, wheel), axle.rideFrequency)
	end
	local barFront, barRear = antiRollRates(car, rates)
	local corners = table.create(Geometry.WHEELS)
	for wheel = 1, Geometry.WHEELS do
		local rate = rates[wheel]
		local weight = Geometry.cornerMass(car, wheel) * World.GRAVITY_MPS2
		corners[wheel] = table.freeze({
			wheelRate = rate,
			freeCompression = car.suspension.staticCompression - weight / rate,
			criticalDamping = 2 * math.sqrt(rate * Geometry.sprungCornerMass(car, wheel)),
			antiRollRate = if Geometry.isFront(wheel) then barFront else barRear,
		})
	end
	return table.freeze({ corners = table.freeze(corners), config = car.suspension })
end

-- Two slopes: `slope` up to the knee speed, then `slope · fastRatio`. Rebound is
-- `reboundRatio` times bump, with the pair averaging `ratio` of critical damping.
function Suspension.damperForce(
	corner: Corner,
	config: Types.SuspensionConfig,
	ratio: number,
	compressionSpeed: number
): number
	local average = ratio * corner.criticalDamping
	local rebound = config.damperReboundRatio
	local slope = if compressionSpeed >= 0
		then average * 2 / (1 + rebound)
		else average * 2 * rebound / (1 + rebound)
	local speed = math.abs(compressionSpeed)
	local knee = config.damperKneeSpeed
	local force = if speed <= knee
		then slope * speed
		else slope * knee + slope * config.damperFastRatio * (speed - knee)
	return if compressionSpeed >= 0 then force else -force
end

-- Progressive: rate rises linearly with depth (rate + 2·progression·depth) until it reaches
-- the cap, then stays there.
function Suspension.bumpStopForce(config: Types.SuspensionConfig, compression: number): number
	local depth = compression - config.bumpStopStart
	if depth <= 0 then
		return 0
	end
	local rate, progression, cap = config.bumpStopRate, config.bumpStopProgression, config.bumpStopMaxRate
	local capDepth = math.max(0, (cap - rate) / (2 * progression))
	if depth <= capDepth then
		return rate * depth + progression * depth * depth
	end
	return rate * capDepth + progression * capDepth * capDepth + cap * (depth - capDepth)
end

function Suspension.springForce(corner: Corner, compression: number): number
	return corner.wheelRate * (compression - corner.freeCompression)
end

-- Fills `forces` (N, up, per wheel) from each wheel's compression, speed and contact. An
-- airborne wheel hangs at full extension: its bar end still twists against the other side,
-- but it carries nothing itself.
function Suspension.forces(
	suspension: Suspension,
	damperRatio: number,
	compressions: { number },
	speeds: { number },
	grounded: { boolean },
	forces: { number }
)
	local config = suspension.config
	for wheel = 1, Geometry.WHEELS do
		if not grounded[wheel] then
			forces[wheel] = 0
			continue
		end
		local corner = suspension.corners[wheel]
		local compression = compressions[wheel]
		local partner = Geometry.partner(wheel)
		local partnerCompression = if grounded[partner] then compressions[partner] else 0
		local force = Suspension.springForce(corner, compression)
			+ Suspension.damperForce(corner, config, damperRatio, speeds[wheel])
			+ Suspension.bumpStopForce(config, compression)
			+ corner.antiRollRate * (compression - partnerCompression)
		forces[wheel] = math.max(0, force)
	end
end

return table.freeze(Suspension)
