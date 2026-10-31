--!strict
--[[
	Prints what a car's hand gestures are keyed against, for tools/anim/gesture_paths.py: the
	steering hub, the drive-mode knob's hinge and its positions, every hinged cabin control with
	its rest and travel (the driver's seat frame: x right, y up, z back; metres), the drive modes in
	the order the key steps them, and the grip.

	    lune run games/drive-lab/tools/gesture_config [DR458] [out.json]

	Without an output path it prints the JSON. A moved knob or toggle in the car's binding is a
	re-run of the path tool.
]]
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Binding = require("../src/shared/Config/Cars/Binding")
local Contract = require("../src/shared/Config/Cars/Contract")

local CARS: { [string]: Contract.Entry } = {
	DR458 = require("../src/shared/Config/Cars/DR458"),
}

local name = process.args[1] or "DR458"
local out = process.args[2]
local entry = CARS[name]
assert(entry, `no gestures for a car called {name}`)

local model = entry.model
local seat = model.seat

local function inSeat(point: Binding.CarPoint): { number }
	return { point.right - seat.right, point.up - seat.up, -(point.forward - seat.forward) }
end

local function direction(axis: Binding.CarPoint): { number }
	return { axis.right, axis.up, -axis.forward }
end

local function hinge(bound: Binding.Hinge)
	return {
		part = bound.part,
		pivot = inSeat(bound.pivot),
		axis = direction(bound.axis),
		rest = bound.rest or 0,
		travel = bound.travel,
	}
end

local controls = {}
for control, bound in model.controls or {} do
	controls[control] = hinge(bound)
end

local knob = model.modeKnob
local grip = entry.driver.grip

local result = {
	car = name,
	frame = "DriverSeat frame: x right, y up, z back; metres",
	steeringHub = if model.steeringHub
		then { pivot = inSeat(model.steeringHub.pivot), axis = direction(model.steeringHub.axis) }
		else nil,
	steeringWheelLift = model.steeringWheelLift,
	modeKnob = if knob then { hinge = hinge(knob.hinge), positions = knob.positions } else nil,
	controls = controls,
	modeOrder = entry.physics.modeOrder,
	grip = {
		meshes = grip.meshes,
		wrist = { grip.wrist.x, grip.wrist.y, grip.wrist.z },
		forearm = { grip.forearm.x, grip.forearm.y, grip.forearm.z },
		back = { grip.back.x, grip.back.y, grip.back.z },
		centre = { grip.centre.x, grip.centre.y, grip.centre.z },
		cuff = { grip.cuff.x, grip.cuff.y, grip.cuff.z },
	},
}

local text = serde.encode("json", result, true)
if out then
	fs.writeFile(out, text)
	print(`wrote {out}`)
else
	print(text)
end
