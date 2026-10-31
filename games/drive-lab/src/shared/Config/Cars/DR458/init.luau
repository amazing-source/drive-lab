--!strict
--[[
	Ferrari 458 Challenge Evo (the DR458): its Contract entry, from the modules beside this one.
]]
local Assists = require("@self/Assists")
local Audio = require("@self/Audio")
local Binnacle = require("@self/Binnacle")
local Camera = require("@self/Camera")
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
	modeLabels = { ["1"] = "1", ["2"] = "2", OFF = "OFF" },
	model = Model,
	door = Door,
	startup = Startup,
	driver = Driver,
	camera = Camera,
	rimBlur = RimBlur,
	audio = Audio,
	lights = Lights,
	binnacle = Binnacle,
	assists = Assists,
	switches = Switches,
})
