--!strict
--[[
	Lamborghini Aventador SVJ (LP 770-4 coupé): its Contract entry, from the modules beside this one.
]]
local Contract = require("./Contract")
local Door = require("@self/Door")
local Model = require("@self/Model")
local Physics = require("@self/Physics")
local Startup = require("@self/Startup")
local StartupPaths = require("@self/StartupPaths")

return Contract.define({
	physics = Physics,
	model = Model,
	door = Door,
	startup = Startup,
	driver = {
		startupPaths = StartupPaths,
	},
})
