--!strict
--[[
	The part names a car's config looks up in its model, for the import's checks: every one must be a
	piece of the imported car, or the rig silently leaves that part on the body (CarRig finds most
	parts with FindFirstChild and skips a missing one).

	Read: the wheels, calipers, glazing, the door's parts and strap, the exhaust housings, shift lights,
	panel lamps, every `part` of a hinge-like entry anywhere in the binding (controls, pedals, the mode
	knob, the wiper, the shifter, and fields added later in the same form), both sides of `parents`,
	and the lamp config's `required` pieces. Left out: the steering wheel when the binding gives a
	steeringHub (the rig builds that part itself when the model has none), and the `displays` field
	(the rig builds its screen parts).
]]
local Binding = require("../src/shared/Config/Cars/Binding")

local CarImportNames = {}

local SKIPPED_FIELDS: { [string]: true } = { displays = true }

local function addPartKeys(value: unknown, add: (string) -> ())
	if type(value) ~= "table" then
		return
	end
	local entry = value :: { [any]: any }
	if type(entry.part) == "string" then
		add(entry.part)
	end
	for key, child in entry do
		if type(child) == "table" and not SKIPPED_FIELDS[key] then
			addPartKeys(child, add)
		end
	end
end

-- Sorted, without repeats.
function CarImportNames.of(model: Binding.CarModel, required: { string }?): { string }
	local seen: { [string]: true } = {}
	local function add(name: string)
		seen[name] = true
	end
	local builtHub = if model.steeringHub then model.steeringWheel else nil
	for _, name in model.wheels do
		add(name)
	end
	for _, group in model.calipers do
		for _, name in group do
			add(name)
		end
	end
	if builtHub == nil then
		add(model.steeringWheel)
	end
	for _, name in model.glazing do
		add(name)
	end
	if model.door then
		for _, name in model.door.parts do
			add(name)
		end
	end
	if model.exhaust then
		add(model.exhaust.left)
		add(model.exhaust.right)
	end
	for _, name in model.shiftLights or {} do
		add(name)
	end
	for _, name in model.panelLamps or {} do
		add(name)
	end
	for rider, carrier in model.parents or {} do
		add(rider)
		if carrier ~= builtHub then
			add(carrier)
		end
	end
	for key, value in model :: { [string]: any } do
		if not SKIPPED_FIELDS[key] then
			addPartKeys(value, add)
		end
	end
	for _, name in required or {} do
		add(name)
	end
	local names = {}
	for name in seen do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

return table.freeze(CarImportNames)
