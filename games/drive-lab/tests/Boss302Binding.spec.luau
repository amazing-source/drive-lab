--!strict
--[[
	The Boss 302's model binding against the redacted copy of its 3D manifest that tools/car_binding
	writes beside it (tests/fixtures/boss302_manifest.json): the 3D artist's cockpit parts draft until
	the full manifest is promoted.
]]
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local CarBindings = require("../tools/CarBindings")
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

	it("lists what the draft lacks, so the car stays out of the catalog until it has it", function()
		local listed = table.concat(ModelPending, "\n")
		for _, lacking in
			{ "wheels", "door", "steering wheel", "windshield", "the 3D model", "shift animation" }
		do
			expect(string.find(listed, lacking, 1, true) ~= nil).toBe(true)
		end
	end)
end)
