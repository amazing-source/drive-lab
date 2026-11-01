--!strict
--[[
	Prints a manual car's gear lever as the game rigs it, for tools/anim/shift_paths.py: the model
	binding's shifter and seat (car frame from the centre of mass, metres), the gearbox's gates (each
	gear's column and row in the H) and its shift timing.

	    lune run games/drive-lab/tools/shift_config [Boss302] [out.json]

	Without an output path it prints the JSON. The path tool turns the lever into the seat's frame as
	Rules/ShiftHand.leverFromBinding does, so a moved lever, gate or time is a re-run.
]]
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Binding = require("../src/shared/Config/Cars/Binding")
local Types = require("../src/shared/Config/Cars/Types")

type Car = { model: Binding.CarModel, physics: Types.CarConfig }

local CARS: { [string]: Car } = {
	Boss302 = {
		model = require("../src/shared/Config/Cars/Boss302/Model"),
		physics = require("../src/shared/Config/Cars/Boss302/Physics"),
	},
}

local name = process.args[1] or "Boss302"
local out = process.args[2]
local car = CARS[name]
assert(car, `no manual gear lever for a car called {name}`)
local shifter = assert(car.model.shifter, `{name}'s binding has no shifter`)
local manual = assert(car.physics.gearbox.manual, `{name}'s gearbox is not manual`)

local gates = {}
for gear, gate in manual.gates do
	local label = if gear < 0 then "R" elseif gear == 0 then "N" else tostring(gear)
	gates[label] = { gear = gear, column = gate.column, row = gate.row }
end

local result = {
	car = name,
	frame = "car frame from the centre of mass, metres; gate angles in radians",
	seat = car.model.seat,
	shifter = shifter,
	gates = gates,
	timing = manual.timing,
}

local text = serde.encode("json", result, true)
if out then
	fs.writeFile(out, text)
	print(`wrote {out}`)
else
	print(text)
end
