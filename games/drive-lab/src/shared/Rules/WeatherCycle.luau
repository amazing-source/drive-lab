--!strict
local WeatherCycle = {}

-- Where in `cycle` the preset after `current` sits, wrapping round. A preset outside the cycle
-- (one the Studio developer panel chose) leads to the cycle's first.
function WeatherCycle.nextIndex<T>(cycle: { T }, current: T): number
	local index = table.find(cycle, current)
	return if index then index % #cycle + 1 else 1
end

return table.freeze(WeatherCycle)
