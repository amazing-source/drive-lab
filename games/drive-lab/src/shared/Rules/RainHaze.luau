--!strict
--[[
	How far you see through rain, and the Atmosphere density that shows it. Rain scatters
	light, so contrast falls with distance as exp(-sigma d); the extinction sigma grows with
	the rain rate as a power law, about 3 per km at 50 mm/h, where contrast halves in about
	230 m and objects are gone within a kilometre. Roblox's Atmosphere is not a plain
	exponential in its Density, so the density is read off a table measured in Studio:
	apparent black-white contrast of panel pairs at 25 to 800 m, one capture per density.

	In rain, the shown density moves from the preset's own value to the rain's, by how hard
	it rains, so a preset still sets the dry look (the haze that greys the sky stays its own).
]]
export type Point = { density: number, extinction: number }

export type Tuning = {
	-- Rain rate at full intensity (mm/h).
	fullRate: number,
	-- Extinction at 50 mm/h (per km), and its power of the rain rate.
	extinction50: number,
	exponent: number,
	-- From this intensity on, the density is the rain's alone.
	takeOver: number,
	-- Measured: Atmosphere density against its extinction (per km), rising in both.
	calibration: { Point },
}

local RainHaze = {}

local function unit(value: number): number
	if value ~= value then
		return 0
	end
	return math.clamp(value, 0, 1)
end

-- Rain rate (mm/h) at an intensity from 0 to 1.
function RainHaze.rainRate(intensity: number, tuning: Tuning): number
	return tuning.fullRate * unit(intensity)
end

-- Extinction (per km) of rain falling at `rate` mm/h.
function RainHaze.extinction(rate: number, tuning: Tuning): number
	if rate ~= rate or rate <= 0 then
		return 0
	end
	return tuning.extinction50 * (math.min(rate, 1e6) / 50) ^ tuning.exponent
end

-- Distance (m) over which contrast halves.
function RainHaze.halfContrast(extinction: number): number
	if extinction ~= extinction or extinction <= 0 then
		return math.huge
	end
	return math.log(2) / extinction * 1000
end

-- The Atmosphere density whose fog has this extinction, interpolated in log extinction
-- between measured points and held at the table's ends.
function RainHaze.densityFor(extinction: number, calibration: { Point }): number
	local first, last = calibration[1], calibration[#calibration]
	if extinction ~= extinction or extinction <= first.extinction then
		return first.density
	end
	if extinction >= last.extinction then
		return last.density
	end
	for index = 2, #calibration do
		local low, high = calibration[index - 1], calibration[index]
		if extinction <= high.extinction then
			local share = math.log(extinction / low.extinction) / math.log(high.extinction / low.extinction)
			return low.density + (high.density - low.density) * share
		end
	end
	return last.density
end

-- The density to show for a preset's own density in rain of `intensity`.
function RainHaze.density(presetDensity: number, intensity: number, tuning: Tuning): number
	local rain = unit(intensity)
	if rain <= 0 then
		return presetDensity
	end
	local wet =
		RainHaze.densityFor(RainHaze.extinction(RainHaze.rainRate(rain, tuning), tuning), tuning.calibration)
	local share = if tuning.takeOver > 0 then unit(rain / tuning.takeOver) else 1
	return presetDensity + (wet - presetDensity) * share
end

return table.freeze(RainHaze)
