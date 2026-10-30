--!strict
--[[
	The DR458's model binding against the redacted copy of its 3D manifest that tools/dr458_binding
	writes beside it (tests/fixtures/dr458_manifest.json).
]]
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local DR458 = require("../src/shared/Config/Cars/DR458/Physics")
local Model = require("../src/shared/Config/Cars/DR458/Model")
local ModelPending = require("../src/shared/Config/Cars/DR458/ModelPending")
local ManifestBinding = require("../tools/ManifestBinding")
local Screen = require("../src/shared/Config/Cars/DR458/Binnacle")
local Settings = require("../tools/DR458Binding")
local Startup = require("../src/shared/Config/Cars/DR458/Startup")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local MANIFEST: ManifestBinding.Manifest =
	serde.decode("json", fs.readFile("games/drive-lab/tests/fixtures/dr458_manifest.json"))
local BY_NAME = ManifestBinding.index(MANIFEST)

local function part(name: string): ManifestBinding.Part
	local found = BY_NAME[name]
	assert(found, `the manifest has no {name}`)
	return found
end

local function vector(point: ManifestBinding.Point?): ManifestBinding.Point
	assert(point, "a point")
	return point
end

local function offset(
	point: ManifestBinding.Point,
	forward: number,
	right: number,
	up: number
): ManifestBinding.Point
	return { forward = point.forward + forward, right = point.right + right, up = point.up + up }
end

-- Every name the binding asks the model for.
local function bindingNames(): { string }
	local names: { string } = { Model.steeringWheel }
	local function add(list: { string }?)
		if list then
			for _, name in list do
				table.insert(names, name)
			end
		end
	end
	add(Model.wheels)
	for _, set in Model.calipers do
		add(set)
	end
	add(Model.glazing)
	add(Model.shiftLights)
	local door = Model.door
	add(door and door.parts)
	local controls, pedals, parents, lamps = Model.controls, Model.pedals, Model.parents, Model.panelLamps
	assert(
		controls and pedals and parents and lamps,
		"the DR458's binding has its controls, pedals, riders and lamps"
	)
	for name, hinge in controls do
		table.insert(names, name)
		table.insert(names, hinge.part)
	end
	for _, hinge in pedals do
		table.insert(names, hinge.part)
	end
	for rider, carrier in parents do
		table.insert(names, rider)
		table.insert(names, carrier)
	end
	for _, lamp in lamps do
		table.insert(names, lamp)
	end
	local knob = Model.modeKnob
	if knob then
		table.insert(names, knob.hinge.part)
	end
	return names
end

local function same(a: unknown, b: unknown): boolean
	if type(a) == "number" and type(b) == "number" then
		return math.abs(a - b) <= 1e-5
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	local left, right = a :: { [unknown]: unknown }, b :: { [unknown]: unknown }
	for key, value in left do
		if not same(value, right[key]) then
			return false
		end
	end
	for key in right do
		if left[key] == nil then
			return false
		end
	end
	return true
end

describe("DR458 binding", function()
	it("asks the model only for parts the manifest has", function()
		for _, name in bindingNames() do
			expect(BY_NAME[name] and name).toBe(name)
		end
	end)

	it("finds every part's group, and every chain of groups ends at the body", function()
		expect(table.concat(ManifestBinding.problems(MANIFEST, Settings), "; ")).toBe("")
	end)

	it("is the writer's output for the manifest, not a hand edit", function()
		local written, pending = ManifestBinding.binding(MANIFEST, DR458, Settings)
		expect(same(Model, written)).toBe(true)
		expect(table.concat(ModelPending, "; ")).toBe(table.concat(pending, "; "))
	end)

	it("lists what it still lacks: the windscreen's corners, the lamps, the pedals' sense", function()
		local pending = table.concat(ModelPending, "\n")
		expect(#Model.windshield == 0 and string.find(pending, "windshield", 1, true) ~= nil).toBe(true)
		expect(string.find(pending, "lamps", 1, true) ~= nil).toBe(true)
		local pedals = Model.pedals
		assert(pedals, "the DR458 has pedals")
		for _, hinge in pedals do
			if part(hinge.part).positive == nil then
				expect(string.find(pending, hinge.part, 1, true) ~= nil).toBe(true)
			end
		end
	end)

	it("moves every point from the rear axle on the ground to the centre of mass", function()
		local centre = ManifestBinding.centreOfMass(DR458)
		expect(centre.forward).toBeNear(2.650 * 0.42, 1e-9)
		expect(centre.up).toBe(DR458.cgHeight)
		local door = Model.door
		assert(door, "the DR458 has a door")
		expect(door.pivot.forward + centre.forward).toBeNear(vector(part("Door_L_Skin").pivot).forward, 1e-5)
		expect(door.pivot.up + centre.up).toBeNear(vector(part("Door_L_Skin").pivot).up, 1e-5)
	end)

	it("sits the binnacle's canvas on a screen of its own shape", function()
		local shape = (Screen.canvasWidth / Screen.canvasHeight)
			/ (Model.cluster.width / Model.cluster.height)
		expect(math.abs(shape - 1) <= 0.05).toBe(true)
	end)
end)

describe("DR458 binding: which way each part turns", function()
	it("swings the driver's door's rear edge out to the car's left as it opens (75 degrees)", function()
		local hinge = part("Door_L_Skin")
		local pivot, axis = vector(hinge.pivot), vector(hinge.axis)
		local rearEdge = offset(pivot, -1, 0, 0)
		local open = ManifestBinding.turned(rearEdge, pivot, axis, math.rad(75))
		expect(open.right < rearEdge.right - 0.5).toBe(true)
		expect(math.abs(open.up - rearEdge.up) < 0.1).toBe(true)
	end)

	it("rolls each wheel forward on a positive turn: the top of the tyre moves toward the nose", function()
		for _, group in Settings.wheelGroups do
			local wheel = part(group)
			local pivot, axis = vector(wheel.pivot), vector(wheel.axis)
			local top = offset(pivot, 0, 0, 0.3)
			expect(ManifestBinding.turned(top, pivot, axis, 0.1).forward > top.forward).toBe(true)
		end
	end)

	it("turns the steering wheel about an axis to the driver, anticlockwise as the driver sees it", function()
		local wheel = part("SteeringWheel")
		local pivot, axis = vector(wheel.pivot), vector(wheel.axis)
		expect(axis.forward < 0).toBe(true)
		local top = offset(pivot, 0.05, 0, 0.17)
		expect(ManifestBinding.turned(top, pivot, axis, 0.1).right < top.right).toBe(true)
	end)

	it(
		"turns the start-up's controls from off to on: key anticlockwise from above, guard up, switch up",
		function()
			local controls = Model.controls
			assert(controls, "the DR458 has controls")
			local function turned(name: string, point: ManifestBinding.Point): ManifestBinding.Point
				local hinge = controls[name]
				local pivot, axis = vector(part(name).pivot), vector(part(name).axis)
				local rested = ManifestBinding.turned(point, pivot, axis, hinge.rest or 0)
				return ManifestBinding.turned(rested, pivot, axis, hinge.travel or 0)
			end
			local key = vector(part("TunnelKey_Master").pivot)
			local grip = offset(key, 0.03, 0, 0)
			expect(turned("TunnelKey_Master", grip).right < key.right - 0.02).toBe(true)
			local guard = vector(part("PanelGuard_Ignition").pivot)
			local edge = offset(guard, 0, 0, -0.03)
			local lifted = turned("PanelGuard_Ignition", edge)
			expect(lifted.forward < guard.forward and lifted.up > edge.up).toBe(true)
			local switch = vector(part("PanelSwitch_Ignition").pivot)
			local tip = offset(switch, -0.02, 0, 0)
			local off = ManifestBinding.turned(tip, switch, vector(part("PanelSwitch_Ignition").axis), 0.35)
			expect(off.up < switch.up).toBe(true)
			expect(turned("PanelSwitch_Ignition", tip).up > switch.up).toBe(true)
		end
	)
end)

describe("DR458 start-up", function()
	it("turns each of its controls through the binding's travel, in order, before START", function()
		local controls = Model.controls
		assert(controls, "the DR458 has controls")
		local last = -1
		for _, move in Startup.moves do
			local hinge = controls[move.control]
			expect(hinge and move.angle).toBe(hinge and hinge.travel)
			expect(move.at > last).toBe(true)
			last = move.at
			expect(move.at + move.move <= Startup.pressAt).toBe(true)
		end
		expect(Startup.moves[1].control).toBe("TunnelKey_Master")
		expect(Startup.moves[3].control).toBe("PanelSwitch_Ignition")
	end)
end)

describe("ManifestBinding", function()
	local SETTINGS = { assemblies = {} } :: any

	local function problems(parts: { any }): string
		return table.concat(ManifestBinding.problems({ parts = parts } :: any, SETTINGS), "; ")
	end

	it("refuses a group that names neither the body, a part nor an assembly", function()
		expect(problems({ { name = "Knob", group = "Chassis", motion = "toggle" } })).toBe("")
		local found = problems({ { name = "Tip", group = "Knbo", motion = "static" } })
		expect(string.find(found, "Tip rides Knbo", 1, true) ~= nil).toBe(true)
	end)

	it("refuses a chain of groups that loops", function()
		local found = problems({
			{ name = "A", group = "B", motion = "hinge" },
			{ name = "B", group = "A", motion = "hinge" },
		})
		expect(string.find(found, "loops", 1, true) ~= nil).toBe(true)
	end)

	it("lets a part ride past a part that does not move, to what moves it or the body", function()
		local manifest = {
			parts = {
				{ name = "Column", group = "Chassis", motion = "static" },
				{ name = "Paddle", group = "Column", motion = "hinge" },
				{ name = "Label", group = "Paddle", motion = "static" },
			},
		} :: any
		local byName = ManifestBinding.index(manifest)
		expect(ManifestBinding.mover(byName, SETTINGS, byName.Paddle)).toBe(nil)
		expect(ManifestBinding.mover(byName, SETTINGS, byName.Label)).toBe("Paddle")
	end)
end)
