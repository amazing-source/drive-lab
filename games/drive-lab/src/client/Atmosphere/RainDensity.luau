--!strict
--[[
	How much rain a quality tier may draw, and how much it draws at an intensity. Every rate is
	capped by the tier's budget, whatever the intensity, exposure, volume or speed asked for, so
	the cost has a ceiling that does not depend on the weather.
]]
export type Tier = "Low" | "Medium" | "High"
export type Budget = {
	-- Share of the rings' full densities this tier draws.
	share: number,
	-- The most particles per second one emitter may emit, and the most streaks alive at once.
	cap: number,
	live: number,
	splashColumns: number,
	splashRows: number,
	splashRate: number,
	rippleRate: number,
	shelterSamples: number,
	rays: number,
	lensDrops: number,
}
export type Levels = { low: number, medium: number }

local RainDensity = {}

local function unit(value: number): number
	if value ~= value then
		return 0
	end
	return math.clamp(value, 0, 1)
end

-- The tier for a saved graphics level (1 to 10). Automatic (0) is not a level and anything
-- unrecognised is not either: both get the fallback.
function RainDensity.tier(savedLevel: number, levels: Levels, fallback: Tier): Tier
	if savedLevel ~= savedLevel or savedLevel < 1 or savedLevel > 10 or savedLevel % 1 ~= 0 then
		return fallback
	end
	if savedLevel <= levels.low then
		return "Low"
	elseif savedLevel <= levels.medium then
		return "Medium"
	end
	return "High"
end

-- A full-rain rate at an intensity: rate * I^exponent, scaled by the share open to the sky.
function RainDensity.scaled(rate: number, intensity: number, exposure: number, exponent: number): number
	return rate * unit(intensity) ^ exponent * unit(exposure)
end

-- Particles per second for one block of `volume` cubic metres to hold `density` live particles
-- per cubic metre at full rain when each lives `lifetime` seconds, at an intensity and exposure,
-- never past `cap`. Below the cap the block holds density * volume particles at full rain.
function RainDensity.blockRate(
	density: number,
	volume: number,
	lifetime: number,
	intensity: number,
	exposure: number,
	exponent: number,
	cap: number
): number
	if lifetime ~= lifetime or lifetime <= 0 or density ~= density or volume ~= volume then
		return 0
	end
	local full = math.max(density, 0) * math.min(math.max(volume, 0), 1e9) / lifetime
	return math.min(RainDensity.scaled(full, intensity, exposure, exponent), math.max(cap, 0))
end

-- The factor every ring's rate takes so the streaks alive at once, `requested` at the rates
-- asked for, stay within `live`: 1 when they already do.
function RainDensity.within(requested: number, live: number): number
	if requested ~= requested or requested <= 0 then
		return 1
	end
	return math.clamp(live / requested, 0, 1)
end

function RainDensity.splashBoxes(budget: Budget): number
	return budget.splashColumns * budget.splashRows
end

-- Splashes per second for one box on the ground.
function RainDensity.splashes(intensity: number, exposure: number, budget: Budget, exponent: number): number
	return RainDensity.scaled(budget.splashRate, intensity, exposure, exponent)
end

-- Ripples per second for one box on the ground: as the splashes, but none on a road drier than
-- `wetFrom`, rising to the full rate on a soaked one.
function RainDensity.ripples(
	intensity: number,
	exposure: number,
	wetness: number,
	wetFrom: number,
	budget: Budget,
	exponent: number
): number
	if wetFrom >= 1 then
		return 0
	end
	local wet = unit((unit(wetness) - wetFrom) / (1 - wetFrom))
	return RainDensity.scaled(budget.rippleRate, intensity, exposure, exponent) * wet
end

-- Rays per second at full rain, all cast once per refresh: the shelter samples of the blocks
-- that take several, one for every other block, one down and one up at the camera (the ground
-- under it, the sky over the lens), and one down and one up per splash box.
function RainDensity.raysPerSecond(
	budget: Budget,
	sampledBlocks: number,
	otherBlocks: number,
	shelterInterval: number
): number
	local perRefresh = sampledBlocks * budget.shelterSamples
		+ otherBlocks
		+ 2
		+ 2 * RainDensity.splashBoxes(budget)
	return perRefresh / shelterInterval
end

-- Whole events due after dt at `rate` per second, and the fraction carried to the next frame,
-- so a rate below one per frame still fires on average at that rate. Never more than `cap` in
-- one call: a long frame drops events rather than bursting them.
function RainDensity.accumulate(carry: number, rate: number, dt: number, cap: number): (number, number)
	local total = carry + math.max(rate, 0) * math.max(dt, 0)
	if total ~= total then
		return 0, 0
	end
	local due = math.floor(total)
	if due > cap then
		return cap, 0
	end
	return due, total - due
end

return table.freeze(RainDensity)
