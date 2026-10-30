--!strict
--[[
	Everything that differs from one car to the next, as one entry per car in Catalog. Shared
	systems read a car's part of it from the entry of the model they serve, never from a car's
	own modules. `define` freezes an entry, so nothing can tune a car at run time.
]]
local Binding = require("./Binding")
local Types = require("./Types")

export type Entry = {
	physics: Types.CarConfig,
	model: Binding.CarModel,
}

local Contract = {}

local function deepFreeze<T>(value: T): T
	if type(value) == "table" and not table.isfrozen(value) then
		for _, child in value :: { [unknown]: unknown } do
			deepFreeze(child)
		end
		table.freeze(value)
	end
	return value
end

function Contract.define(entry: Entry): Entry
	return deepFreeze(entry)
end

return table.freeze(Contract)
