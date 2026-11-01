--!strict
--[[
	Prints the part names a car's config looks up in its model (tools/CarImportNames), as JSON, for
	tools/assets/car_import_data.py --binding: the import stops when one has no piece.

	    lune run games/drive-lab/tools/car_import_names [Boss302|DR458|SVJ] [out.json]
]]
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Binding = require("../src/shared/Config/Cars/Binding")
local CarImportNames = require("./CarImportNames")

local name = process.args[1] or "Boss302"
local out = process.args[2]
local folder = `games/drive-lab/src/shared/Config/Cars/{name}`
assert(fs.isDir(folder), `no car config folder {folder}`)
local model: Binding.CarModel = (require :: any)(`../src/shared/Config/Cars/{name}/Model`)
local lamps: CarImportNames.Lamps? = nil
if fs.isFile(`{folder}/Lights.luau`) then
	lamps = (require :: any)(`../src/shared/Config/Cars/{name}/Lights`)
end
local names = CarImportNames.of(model, lamps)
local text = serde.encode("json", names, true)
if out then
	fs.writeFile(out, text)
	print(`{#names} part names -> {out}`)
else
	print(text)
end
