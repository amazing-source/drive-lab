--!strict
--[[
	A car's drive modes, by name and in the order its mode control steps through them
	(Config/Cars, `modeOrder`). The driving client publishes the mode on the model's DrivingMode
	attribute; every other reader takes it through `current`, so a value from another car or
	none at all reads as this car's first mode.
]]
local DriveModes = {}

-- The mode `value` names if it is one of the car's, or the car's first mode.
function DriveModes.current(order: { string }, value: unknown): string
	if typeof(value) == "string" and table.find(order, value) then
		return value
	end
	return order[1]
end

-- The mode the control selects after `mode`, from the last back to the first.
function DriveModes.after(order: { string }, mode: string): string
	local index = table.find(order, mode) or 0
	return order[index % #order + 1]
end

return table.freeze(DriveModes)
