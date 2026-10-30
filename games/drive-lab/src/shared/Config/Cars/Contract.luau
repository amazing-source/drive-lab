--!strict
--[[
	Everything that differs from one car to the next, as one entry per car in Catalog. Shared
	systems read a car's part of it from the entry of the model they serve, never from a car's
	own modules. `define` checks that an entry's parts agree with each other, so a bad car fails
	at load time, and freezes it, so nothing can tune a car at run time.
]]
local Binding = require("./Binding")
local CarCamera = require("../CarCamera")
local CarEntry = require("../CarEntry")
local DriverArms = require("../DriverArms")
local DriverLegs = require("../DriverLegs")
local DriverStartup = require("../DriverStartup")
local Types = require("./Types")

export type Driver = {
	grip: DriverArms.Grip,
	footwell: DriverLegs.Footwell,
	-- Both hands through the start-up, keyed against this car's cabin.
	startupPaths: DriverStartup.Paths,
}

export type Entry = {
	physics: Types.CarConfig,
	model: Binding.CarModel,
	door: CarEntry.Door,
	startup: CarEntry.Startup,
	driver: Driver,
	camera: CarCamera.CarViews,
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

local function checkStartup(entry: Entry)
	local startup = entry.startup
	local controls = entry.model.controls or {}
	local moved: { [string]: boolean } = {}
	for _, move in startup.moves do
		local name = move.control
		assert(controls[name], `the start-up moves "{name}", which the model binding does not hinge`)
		assert(not moved[name], `the start-up moves "{name}" twice`)
		moved[name] = true
		assert(move.move > 0, `"{name}" needs a move time above 0`)
		assert(move.back == nil or move.back >= move.at, `"{name}" turns back before it has arrived`)
	end
	assert(startup.pressAt < startup.drivableAt, "driving unlocks before START is pressed")
	assert(startup.wheelAt <= startup.drivableAt, "driving unlocks before the hands are on the wheel")
end

-- The legs press the pedals the rig turns: each footwell pedal is one the binding hinges.
local function checkFootwell(entry: Entry)
	local hinged: { [string]: boolean } = {}
	local pedals = entry.model.pedals
	if pedals then
		for _, pedal in pedals do
			hinged[pedal.part] = true
		end
	end
	local footwell = entry.driver.footwell
	for _, pedal in { footwell.throttle, footwell.brake } do
		assert(hinged[pedal.part], `the footwell's "{pedal.part}" is not a pedal the model binding hinges`)
	end
end

function Contract.define(entry: Entry): Entry
	checkStartup(entry)
	checkFootwell(entry)
	return deepFreeze(entry)
end

return table.freeze(Contract)
