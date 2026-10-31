--!strict
--[[
	Prints a car's start-up as the game plays it, for tools/blender/startup_paths.py: the times,
	each control move, and the binding's hinge of every control it turns, in the driver's seat
	frame (the DriverSeat part: x right, y up, z back; metres).

	    lune run games/drive-lab/tools/startup_config [DR458|SVJ] [out.json]

	Without an output path it prints the JSON. The path tool reads it, so a changed time in a car's
	Startup.luau or a moved control in its binding is a re-run and a re-bake.
]]
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Binding = require("../src/shared/Config/Cars/Binding")
local CarEntry = require("../src/shared/Config/CarEntry")

type Car = { startup: CarEntry.Startup, model: Binding.CarModel }

local CARS: { [string]: Car } = {
	DR458 = {
		startup = require("../src/shared/Config/Cars/DR458/Startup"),
		model = require("../src/shared/Config/Cars/DR458/Model"),
	},
	SVJ = {
		startup = require("../src/shared/Config/Cars/SVJ/Startup"),
		model = require("../src/shared/Config/Cars/SVJ/Model"),
	},
}

local name = process.args[1] or "DR458"
local out = process.args[2]
local car = CARS[name]
assert(car, `no start-up for a car called {name}`)

local model = car.model
local seat = model.seat

-- The seat and the controls ride the same body raise, so it cancels here.
local function inSeat(point: Binding.CarPoint): { number }
	return { point.right - seat.right, point.up - seat.up, -(point.forward - seat.forward) }
end

local function direction(axis: Binding.CarPoint): { number }
	return { axis.right, axis.up, -axis.forward }
end

local moves = {}
for _, move in car.startup.moves do
	table.insert(moves, {
		control = move.control,
		angle = move.angle,
		move = move.move,
		at = move.at,
		back = move.back,
	})
end

local controls = {}
for control, hinge in model.controls or {} do
	controls[control] = { part = hinge.part, pivot = inSeat(hinge.pivot), axis = direction(hinge.axis) }
end

local result = {
	car = name,
	frame = "DriverSeat frame: x right, y up, z back; metres",
	moves = moves,
	pressAt = car.startup.pressAt,
	wheelAt = car.startup.wheelAt,
	drivableAt = car.startup.drivableAt,
	brake = car.startup.brake,
	controls = controls,
	steeringHub = if model.steeringHub
		then { pivot = inSeat(model.steeringHub.pivot), axis = direction(model.steeringHub.axis) }
		else nil,
	steeringWheelLift = model.steeringWheelLift,
}

local text = serde.encode("json", result, true)
if out then
	fs.writeFile(out, text)
	print(`wrote {out}`)
else
	print(text)
end
