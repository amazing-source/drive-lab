--!strict
--[[
	Every car the place can rig, by the name a car model carries in its "Car" attribute. A new
	car is a physics config, a model binding and one line here.
]]
local SVJ = require("./SVJ")
local SVJModel = require("./SVJModel")
local Types = require("./Types")

export type Entry = { physics: Types.CarConfig, model: SVJModel.CarModel }

local Catalog: { [string]: Entry } = table.freeze({
	SVJ = table.freeze({ physics = SVJ, model = SVJModel }),
})

return Catalog
