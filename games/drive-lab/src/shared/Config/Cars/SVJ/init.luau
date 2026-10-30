--!strict
--[[
	Lamborghini Aventador SVJ (LP 770-4 coupé): its Contract entry, from the modules beside this one.
]]
local Assists = require("@self/Assists")
local Audio = require("@self/Audio")
local Camera = require("@self/Camera")
local Cluster = require("@self/Cluster")
local Contract = require("./Contract")
local Door = require("@self/Door")
local Driver = require("@self/Driver")
local Lights = require("@self/Lights")
local Model = require("@self/Model")
local Physics = require("@self/Physics")
local RimBlur = require("@self/RimBlur")
local Startup = require("@self/Startup")
local Switches = require("@self/Switches")

return Contract.define({
	physics = Physics,
	modeLabels = { Strada = "Strada", Sport = "Sport", Corsa = "Corsa" },
	model = Model,
	door = Door,
	startup = Startup,
	driver = Driver,
	camera = Camera,
	rimBlur = RimBlur,
	audio = Audio,
	lights = Lights,
	cluster = Cluster,
	assists = Assists,
	switches = Switches,
})
