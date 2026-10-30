--!strict
--[[
	Every car the place can rig, by the name a car model carries in its "Car" attribute. A new car
	is a folder beside this module whose init returns its Contract entry, and one line here.
]]
local Contract = require("./Contract")
local SVJ = require("./SVJ")

export type Entry = Contract.Entry

local ATTRIBUTE = "Car"

local cars: { [string]: Entry } = table.freeze({
	SVJ = SVJ,
})

local Catalog = { cars = cars }

-- The entry of the car `model` is, or nil for any other instance.
function Catalog.of(model: Instance): Entry?
	local name = model:GetAttribute(ATTRIBUTE)
	return if typeof(name) == "string" then cars[name] else nil
end

return table.freeze(Catalog)
