--!strict
--[[
	Ford Mustang Boss 302 (2012, the Laguna Seca): its Contract entry, from the modules beside this
	one. It joins the catalog once its pending lists (ModelPending, StartupPending, EntryPending)
	are empty.
]]
local Assists = require("@self/Assists")
local Audio = require("@self/Audio")
local Camera = require("@self/Camera")
local Contract = require("./Contract")
local Door = require("@self/Door")
local Driver = require("@self/Driver")
local Gauges = require("@self/Gauges")
local Lights = require("@self/Lights")
local Model = require("@self/Model")
local Physics = require("@self/Physics")
local RimBlur = require("@self/RimBlur")
local Startup = require("@self/Startup")
local Switches = require("@self/Switches")

return Contract.define({
	physics = Physics,
	modeLabels = { Normal = "Normal", Sport = "Sport", TracKey = "TracKey" },
	model = Model,
	door = Door,
	startup = Startup,
	driver = Driver,
	camera = Camera,
	rimBlur = RimBlur,
	audio = Audio,
	lights = Lights,
	gauges = Gauges,
	assists = Assists,
	switches = Switches,
})
