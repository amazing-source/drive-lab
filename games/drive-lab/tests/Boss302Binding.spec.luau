--!strict
--[[
	The Boss 302's model binding against the redacted copy of its 3D manifest that tools/car_binding
	writes beside it (tests/fixtures/boss302_manifest.json), from the 3D artist's promoted full
	manifest.
]]
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Binding = require("../src/shared/Config/Cars/Binding")
local CarBindings = require("../tools/CarBindings")
local Hinge = require("../src/shared/Rules/Hinge")
local ManifestBinding = require("../tools/ManifestBinding")
local Model = require("../src/shared/Config/Cars/Boss302/Model")
local ModelPending = require("../src/shared/Config/Cars/Boss302/ModelPending")
local ShiftHand = require("../src/shared/Rules/ShiftHand")
local Startup = require("../src/shared/Config/Cars/Boss302/Startup")
local Types = require("../src/shared/Config/Cars/Types")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local MANIFEST: ManifestBinding.Manifest =
	serde.decode("json", fs.readFile("games/drive-lab/tests/fixtures/boss302_manifest.json"))
local CAR = CarBindings.Boss302
local CENTRE = ManifestBinding.centreOfMass(CAR.physics)

local function part(name: string): ManifestBinding.Part
	for _, entry in MANIFEST.parts do
		if entry.name == name then
			return entry
		end
	end
	error(`the fixture has no {name}`)
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

describe("Boss 302 binding", function()
	it("is the writer's output for the manifest and its notes, not a hand edit", function()
		local written, pending = ManifestBinding.binding(MANIFEST, CAR.physics, CAR.settings)
		for _, note in CAR.notes do
			table.insert(pending, note)
		end
		table.sort(pending)
		expect(same(Model, written)).toBe(true)
		expect(table.concat(ModelPending, "; ")).toBe(table.concat(pending, "; "))
	end)

	it("binds the key the start-up turns, to its START detent, from the rig's centre", function()
		local key = assert((Model.controls or {}).Key_Ignition, "the key is a bound control")
		local manifestKey = part("Key_Ignition")
		local pivot = assert(manifestKey.pivot, "the key has a pivot")
		expect(same(key.pivot, ManifestBinding.toRig(pivot, CENTRE))).toBe(true)
		expect(key.travel).toBeNear(math.pi / 2, 1e-4)
		for _, move in Startup.moves do
			expect(move.control).toBe("Key_Ignition")
		end
	end)

	it("binds a manual's three pedals, each turning about the car's right", function()
		local pedals = assert(Model.pedals, "the pedals are bound")
		local names = {}
		for _, pedal in pedals do
			table.insert(names, pedal.part)
			expect(pedal.axis.right > 0).toBe(true)
		end
		expect(table.concat(names, ",")).toBe("Pedal_Throttle,Pedal_Brake,Pedal_Clutch")
	end)

	it(
		"lays the lever's gates out as the MT-82's H: odd gears forward, columns left to right, R left of 1",
		function()
			local shifter = assert(Model.shifter, "the lever is bound")
			local gates = shifter.gates
			for _, gear in { "R", "1", "2", "3", "4", "5", "6", "N" } do
				expect(gates[gear] ~= nil).toBe(true)
			end
			for _, gear in { "R", "1", "3", "5" } do
				expect(gates[gear].fore > 0).toBe(true)
			end
			for _, gear in { "2", "4", "6" } do
				expect(gates[gear].fore < 0).toBe(true)
			end
			expect(gates.N.side == 0 and gates.N.fore == 0).toBe(true)
			expect(gates.R.side < gates["1"].side).toBe(true)
			expect(gates["1"].side < gates["3"].side and gates["3"].side < gates["5"].side).toBe(true)
			expect(gates["1"].side).toBe(gates["2"].side)
			local fore, side = shifter.axisFore, shifter.axisSide
			-- Two axes square to each other, each of unit length.
			expect(math.abs(fore.forward * side.forward + fore.right * side.right + fore.up * side.up) < 1e-4).toBe(
				true
			)
			expect(math.sqrt(fore.forward ^ 2 + fore.right ^ 2 + fore.up ^ 2)).toBeNear(1, 1e-4)
		end
	)

	it(
		"binds the knob's centre from the rig's centre and reverse's push depth, listed until the manifest has it",
		function()
			local shifter = assert(Model.shifter, "the lever is bound")
			local lever = part("Shifter_Lever")
			local knob = ManifestBinding.toRig(assert(lever.knob, "the fixture has the knob").centre, CENTRE)
			expect(shifter.knob.forward).toBeNear(knob.forward, 1e-4)
			expect(shifter.knob.right).toBeNear(knob.right, 1e-4)
			expect(shifter.knob.up).toBeNear(knob.up, 1e-4)
			expect(shifter.knob.up > shifter.pivot.up).toBe(true)
			local push = assert(lever.push_m, "the fixture has the push depth")
			expect(push > 0 and push < 0.03).toBe(true)
			expect(shifter.push).toBe(push)
			expect(string.find(table.concat(ModelPending, "\n"), "push_m", 1, true)).toBe(nil)

			local parts = table.clone(MANIFEST.parts)
			for index, entry in parts do
				if entry.name == "Shifter_Lever" then
					local unpushed = table.clone(entry)
					unpushed.push_m = nil
					parts[index] = unpushed
				end
			end
			local manifest = table.clone(MANIFEST)
			manifest.parts = parts
			local written, pending = ManifestBinding.binding(manifest, CAR.physics, CAR.settings)
			expect(assert(written.shifter, "the lever is bound").push).toBe(0)
			expect(string.find(table.concat(pending, "\n"), "push_m", 1, true) ~= nil).toBe(true)
		end
	)

	it("moves its knob into each gate where the 3D model's own gate pose puts it (Blender)", function()
		local shifter = assert(Model.shifter, "the lever is bound")
		local gates = (CAR.physics.gearbox.manual :: Types.ManualGearboxConfig).gates
		local lever = ShiftHand.leverFromBinding(shifter, gates, Model.seat)
		local offsets =
			assert(part("Shifter_Lever").knob_offset_m, "the fixture has the per-gate knob offsets")
		local checked = 0
		for name, offset in offsets do
			local gear = if name == "R" then -1 elseif name == "N" then 0 else assert(tonumber(name))
			local gate = gates[gear]
			local knob = ShiftHand.lever(lever, gate.column, gate.row, 0).position
			-- Seat frame (x right, y up, z back) against the manifest's (forward, right, up), rounded to 0.1 mm.
			expect(knob.x - lever.knob.x).toBeNear(offset.right, 1e-4)
			expect(knob.y - lever.knob.y).toBeNear(offset.up, 1e-4)
			expect(lever.knob.z - knob.z).toBeNear(offset.forward, 1e-4)
			checked += 1
		end
		expect(checked).toBe(8)
	end)

	it("seats the driver at the draft's hip point, from the rig's centre", function()
		local hip = assert(
			assert(MANIFEST.points, "the fixture has points").Driver_HPoint,
			"the draft has the hip point"
		)
		local seat = ManifestBinding.toRig(hip, CENTRE)
		expect(Model.seat.forward).toBeNear(seat.forward, 1e-4)
		expect(Model.seat.right).toBeNear(seat.right, 1e-4)
		expect(Model.seat.up).toBeNear(seat.up, 1e-4)
		-- The driver's side of a left-hand-drive car.
		expect(Model.seat.right < 0).toBe(true)
		expect(string.find(table.concat(ModelPending, "\n"), "seat:", 1, true)).toBe(nil)
	end)

	it("binds the full model's wheels, door, steering hub, exhaust tips and windscreen", function()
		expect(table.concat(Model.wheels, ",")).toBe(
			"Wheel_FL_Tyre,Wheel_FR_Tyre,Wheel_RL_Tyre,Wheel_RR_Tyre"
		)
		local parents = assert(Model.parents, "riders are bound")
		for _, corner in { "FL", "FR", "RL", "RR" } do
			-- The corner's spinning mesh rides its tyre, which the rig turns.
			expect(parents[`Wheel_{corner}`]).toBe(`Wheel_{corner}_Tyre`)
		end
		local door = assert(Model.door, "the driver's door is bound")
		expect(table.find(door.parts, "Door_L_Skin") ~= nil and table.find(door.parts, "Door_L_Glass") ~= nil).toBe(
			true
		)
		expect(door.pivot.right < 0 and door.openAngle > 0).toBe(true)
		local hub = assert(Model.steeringHub, "the wheel turns on a hub from the rim's fit")
		-- The column points back toward the driver and up.
		expect(hub.axis.forward < 0 and hub.axis.up > 0).toBe(true)
		expect(parents.SteeringWheel_Rim).toBe("SteeringWheel")
		local outlets = assert(Model.exhaustOutlets, "the exhaust tips are bound")
		expect(#outlets).toBe(2)
		for _, outlet in outlets do
			-- The rear tips (the model has no side pipes), pointing out behind the car.
			expect(outlet.axis.forward).toBeNear(-1, 1e-6)
			expect(outlet.centre.forward < -2).toBe(true)
		end
		expect(outlets[1].centre.right).toBeNear(-outlets[2].centre.right, 1e-4)
		local glass = Model.windshield
		expect(#glass).toBe(4)
		-- Top left, top right, bottom right, bottom left: the top higher and further back.
		expect(glass[1].up > glass[4].up and glass[1].forward < glass[4].forward).toBe(true)
		expect(glass[1].right < 0 and glass[2].right > 0).toBe(true)
	end)

	it("lists only what is not the model's, so the car stays out of the catalog until it lands", function()
		local listed = table.concat(ModelPending, "\n")
		for _, part in
			{
				"wheels:",
				"door:",
				"glazing:",
				"lamps:",
				"exhaust:",
				"steering wheel:",
				"windshield:",
				"calipers:",
				"seat:",
			}
		do
			expect(if string.find(listed, part, 1, true) then part else "bound").toBe("bound")
		end
		expect(string.find(listed, "the 3D model", 1, true) ~= nil).toBe(true)
		-- The car's entry (init.luau, with its driver's shift hand) exists, so neither is still listed.
		for _, done in { "shift animation", "the remaining car entry" } do
			expect(if string.find(listed, done, 1, true) then done else "done").toBe("done")
		end
		-- Its cluster is needles, so no live display screen is wanted.
		expect(string.find(listed, "cluster:", 1, true)).toBe(nil)
	end)

	it("binds each needle the manifest measures, and lists the others and the screens as pending", function()
		local needles = Model.needles or {}
		for _, name in CAR.settings.needles or {} do
			local fixture: ManifestBinding.Part? = nil
			for _, entry in MANIFEST.parts do
				if entry.name == name then
					fixture = entry
				end
			end
			local range = if fixture then fixture.range else nil
			if type(range) == "table" and #range >= 2 then
				local needle = needles[name]
				expect(needle and needle.part).toBe(name)
				local pivot = assert(assert(fixture).pivot, "a measured needle has a pivot")
				expect(needle.pivot.forward).toBeNear(pivot.forward - CENTRE.forward, 1e-5)
				expect(needle.pivot.up).toBeNear(pivot.up - CENTRE.up, 1e-5)
				expect(needle.travel :: number).toBeNear(range[#range] - range[1], 1e-5)
				expect(Hinge.restAngle(needle)).toBeNear(range[1], 1e-5)
			else
				expect(needles[name]).toBe(nil)
				local listed = table.concat(ModelPending, "\n")
				expect(string.find(listed, name, 1, true) ~= nil and "pending").toBe("pending")
			end
		end
		-- The speedometer's and the tachometer's sweeps and zero offsets are the manifest's measured
		-- ones, not an assumed half turn from the modelled pose.
		for _, name in { "Needle_Speedo", "Needle_Tach" } do
			local range = part(name).range :: { number }
			local needle = needles[name] :: Binding.Hinge
			expect(needle.travel :: number).toBeNear(range[#range] - range[1], 1e-4)
			expect(Hinge.restAngle(needle)).toBeNear(range[1], 1e-4)
		end
		for display, part in CAR.settings.displays or {} do
			local bound = (Model.displays or {})[display]
			local listed = table.concat(ModelPending, "\n")
			expect(bound ~= nil or string.find(listed, part, 1, true) ~= nil).toBe(true)
		end
	end)

	it("binds a needle's sweep as its rest and travel, and a display as a screen", function()
		local manifest: ManifestBinding.Manifest = {
			parts = {
				{ name = "Gauge", group = "Chassis", motion = "static" },
				{
					name = "Needle_A",
					group = "Gauge",
					motion = "rotary",
					pivot = { forward = 1, right = 0, up = 1 },
					axis = { forward = 2, right = 0, up = 0 },
					range = { -0.25, 4.5 },
				},
				{
					name = "Needle_B",
					group = "Chassis",
					motion = "rotary",
					pivot = { forward = 1, right = 0.1, up = 1 },
					axis = { forward = 1, right = 0, up = 0 },
				},
				{
					name = "Window",
					group = "Chassis",
					motion = "static",
					mesh = false,
					screen = {
						centre = { forward = 1, right = 0, up = 1.2 },
						width_m = 0.04,
						height_m = 0.02,
						normal = { forward = -1, right = 0, up = 0 },
						tilt_back_deg = 10,
					},
				},
			},
			points = {},
		}
		local settings = table.clone(CAR.settings)
		settings.needles = { "Needle_A", "Needle_B", "Needle_C" }
		settings.displays = { Readout = "Window", Missing = "NoWindow" }
		local model, pending = ManifestBinding.binding(manifest, CAR.physics, settings)
		local needle = (model.needles or {}).Needle_A :: Binding.Hinge
		expect(needle.travel :: number).toBeNear(4.75, 1e-5)
		expect(needle.rest :: number).toBeNear(-0.25, 1e-5)
		expect(needle.axis.forward).toBeNear(1, 1e-5)
		expect((model.needles or {}).Needle_B).toBe(nil)
		local screen = (model.displays or {}).Readout :: Binding.Screen
		expect(screen.width).toBeNear(0.04, 1e-5)
		expect(screen.tilt).toBeNear(math.rad(10), 1e-5)
		expect(screen.up).toBeNear(1.2 - CENTRE.up, 1e-5)
		local listed = table.concat(pending, "\n")
		for _, expected in { "Needle_B has no measured sweep", "has no Needle_C", "has no NoWindow" } do
			expect(if string.find(listed, expected, 1, true) then expected else listed).toBe(expected)
		end
	end)
end)
