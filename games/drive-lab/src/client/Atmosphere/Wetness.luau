--!strict
--[[
	How wet the road is, from how hard it rains. The road takes water at a rate set by the rain
	and loses it at a rate set by its absence:

		dW/dt = a (1 - W) - b W,   a = I / wetSeconds,   b = (1 - I) / drySeconds

	For a rain intensity held over a step this has an exact solution, used here, so the result
	does not depend on the frame rate and can never overshoot 0 or 1.
]]
export type Rates = { wetSeconds: number, drySeconds: number }

local Wetness = {}

local function finite(value: number, fallback: number): number
	return if value ~= value or value == math.huge or value == -math.huge then fallback else value
end

local function unit(value: number): number
	return math.clamp(finite(value, 0), 0, 1)
end

-- The wetness after dt seconds of rain at intensity (0 to 1). Invalid input counts as dry
-- weather, no time, or a dry road, never as an error.
function Wetness.step(wetness: number, intensity: number, dt: number, rates: Rates): number
	local current = unit(wetness)
	local elapsed = finite(dt, 0)
	if elapsed <= 0 then
		return current
	end
	local rain = unit(intensity)
	local gain = rain / rates.wetSeconds
	local loss = (1 - rain) / rates.drySeconds
	local rate = gain + loss
	local settled = gain / rate
	return math.clamp(settled + (current - settled) * math.exp(-rate * elapsed), 0, 1)
end

-- Which material state shows (1 = driest), given the one showing now. starts[i] is the wetness
-- from which state i takes over; a change needs wetness past the boundary by the hysteresis, so
-- a value hovering on a boundary never flickers between two states.
function Wetness.stage(current: number, wetness: number, starts: { number }, hysteresis: number): number
	local value = unit(wetness)
	local index = math.clamp(current, 1, #starts)
	while index < #starts and value >= starts[index + 1] + hysteresis do
		index += 1
	end
	while index > 1 and value < starts[index] - hysteresis do
		index -= 1
	end
	return index
end

-- The albedo factor at a wetness: 1 dry, soaked when fully wet. An exponent below 1 darkens a
-- damp surface quickly and then levels off.
function Wetness.darkening(wetness: number, soaked: number, exponent: number): number
	return 1 + (soaked - 1) * unit(wetness) ^ exponent
end

return table.freeze(Wetness)
