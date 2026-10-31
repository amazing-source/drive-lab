--!strict
--[[
	Writes the DR458's model binding from its 3D manifest (tools/car_binding for the DR458, kept as
	the command its files name). Run it from the repo root whenever the manifest changes:

	    lune run games/drive-lab/tools/dr458_binding --write [path to dr458_manifest.json]

	Without --write it only reports whether the committed binding matches the manifest; without a
	manifest (in CI) it reports that and stops.
]]
local process = require("@lune/process")

local CarBindingTool = require("./CarBindingTool")

local write = false
local path: string? = process.env.DR458_MANIFEST
for _, argument in process.args do
	if argument == "--write" then
		write = true
	else
		path = argument
	end
end
CarBindingTool.run("DR458", write, path)
