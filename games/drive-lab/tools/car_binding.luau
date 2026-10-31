--!strict
--[[
	Writes a car's model binding from its 3D manifest (tools/CarBindingTool, tools/CarBindings). Run
	it from the repo root whenever a manifest changes:

	    lune run games/drive-lab/tools/car_binding [--write] [Car] [path to its manifest]

	With no car it checks every car in tools/CarBindings; without --write it only reports.
]]
local process = require("@lune/process")

local CarBindingTool = require("./CarBindingTool")
local CarBindings = require("./CarBindings")

local write = false
local car: string? = nil
local path: string? = nil
for _, argument in process.args do
	if argument == "--write" then
		write = true
	elseif CarBindings[argument] then
		car = argument
	else
		path = argument
	end
end
if car then
	CarBindingTool.run(car, write, path)
else
	local names = {}
	for name in CarBindings do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		CarBindingTool.run(name, write, nil)
	end
end
