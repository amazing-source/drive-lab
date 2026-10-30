--!strict
--[[
	Lamborghini Aventador SVJ (LP 770-4 coupé): its Contract entry, from the modules beside this one.
]]
local Contract = require("./Contract")
local Model = require("@self/Model")
local Physics = require("@self/Physics")

return Contract.define({
	physics = Physics,
	model = Model,
})
