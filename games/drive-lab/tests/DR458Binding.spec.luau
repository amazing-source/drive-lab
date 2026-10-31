--!strict
--[[
	The DR458's model binding against the redacted copy of its 3D manifest that tools/dr458_binding
	writes beside it (tests/fixtures/dr458_manifest.json).
]]
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local DR458 = require("../src/shared/Config/Cars/DR458/Physics")
local Geometry = require("../src/shared/Vehicle/Geometry")
local Hinge = require("../src/shared/Rules/Hinge")
local Model = require("../src/shared/Config/Cars/DR458/Model")
local ModelPending = require("../src/shared/Config/Cars/DR458/ModelPending")
local ManifestBinding = require("../tools/ManifestBinding")
local Screen = require("../src/shared/Config/Cars/DR458/Binnacle")
local Settings = require("../tools/DR458Binding")
local Startup = require("../src/shared/Config/Cars/DR458/Startup")
local T = require("../../../tools/test/T")
local Units = require("../src/shared/Units")

local describe, it, expect = T.describe, T.it, T.expect
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

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

-- The rig's chassis space (Car/CarRig carSpace): studs from the centre of mass, x right, y up,
-- z toward the back.
local function studs(point: ManifestBinding.Point): Vector3
	local v = Hinge.chassis(point)
	return Vector3.new(Units.metresToStuds(v.x), Units.metresToStuds(v.y), Units.metresToStuds(v.z))
end

local function metres(v: Vector3): ManifestBinding.Point
	return {
		forward = -Units.studsToMetres(v.Z),
		right = Units.studsToMetres(v.X),
		up = Units.studsToMetres(v.Y),
	}
end

-- A frame at a binding's pivot, raised with the body as the rig raises it. Lune's CFrame.lookAt
-- faces the opposite way to Roblox's, so frames are built from their axes.
local function frameAt(
	pivot: ManifestBinding.Point,
	x: Hinge.Vector,
	y: Hinge.Vector,
	z: Hinge.Vector
): CFrame
	return CFrame.fromMatrix(
		studs({ forward = pivot.forward, right = pivot.right, up = pivot.up + Model.bodyRaise }),
		Vector3.new(x.x, x.y, x.z),
		Vector3.new(y.x, y.y, y.z),
		Vector3.new(z.x, z.y, z.z)
	)
end

-- A hinge weld's rest C0 as Car/CarRig hingeFrame builds it, its X along the axis.
local function hingeRest(pivot: ManifestBinding.Point, axis: ManifestBinding.Point): CFrame
	local x, y, z = Hinge.frame(Hinge.chassis(axis))
	return frameAt(pivot, x, y, z)
end

local function beside(frame: CFrame, forward: number, right: number, up: number): Vector3
	return frame.Position + studs({ forward = forward, right = right, up = up })
end

-- Where a point on a welded part goes when the weld's C0 goes from `rest` to `posed`: a weld holds
-- its Part1 at Part0 * C0 * C1:Inverse(), and C1 never changes.
local function carried(point: Vector3, rest: CFrame, posed: CFrame): ManifestBinding.Point
	return metres(posed * rest:Inverse() * point)
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

	it("lists a pedal with no turning sense as pending", function()
		local pending = table.concat(ModelPending, "\n")
		local pedals = Model.pedals
		assert(pedals, "the DR458 has pedals")
		for _, hinge in pedals do
			if part(hinge.part).positive == nil then
				expect(string.find(pending, hinge.part, 1, true) ~= nil).toBe(true)
			end
		end
	end)

	it("takes the windscreen's corners from the manifest's points, driver's left first", function()
		local centre = ManifestBinding.centreOfMass(DR458)
		local points = MANIFEST.points
		assert(points, "the fixture has points")
		expect(#Model.windshield).toBe(4)
		for index, name in Settings.windshield do
			local point, corner = vector(points[name]), Model.windshield[index]
			expect(corner.forward + centre.forward).toBeNear(point.forward, 1e-5)
			expect(corner.right + centre.right).toBeNear(point.right, 1e-5)
			expect(corner.up + centre.up).toBeNear(point.up, 1e-5)
		end
		local topLeft, topRight, bottomRight, bottomLeft = table.unpack(Model.windshield)
		expect(topLeft.right < 0 and topRight.right > 0).toBe(true)
		expect(bottomLeft.right < 0 and bottomRight.right > 0).toBe(true)
		expect(topLeft.up > bottomLeft.up and topRight.up > bottomRight.up).toBe(true)
	end)

	it("lists the windscreen and the exterior lamps as pending when the manifest lacks them", function()
		local points = table.clone(MANIFEST.points :: { [string]: ManifestBinding.Point })
		points.Windshield_BottomLeft = nil
		local parts = {}
		for _, entry in MANIFEST.parts do
			if string.sub(entry.name, 1, 6) ~= "Light_" then
				table.insert(parts, entry)
			end
		end
		local written, pending = ManifestBinding.binding({ parts = parts, points = points }, DR458, Settings)
		local listed = table.concat(pending, "\n")
		expect(#written.windshield).toBe(0)
		expect(string.find(listed, "windshield", 1, true) ~= nil).toBe(true)
		expect(string.find(listed, "lamps", 1, true) ~= nil).toBe(true)
		local _, complete = ManifestBinding.binding(MANIFEST, DR458, Settings)
		expect(table.concat(complete, "; ")).toBe("")
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

-- The binding itself (Model), posed through the welds the rig builds and the turns the runtime
-- applies to them, in the chassis's space.
describe("DR458 binding: which way each part turns, as the rig turns it", function()
	it(
		"opens the driver's door 75 degrees, its rear edge out to the car's left (Controllers/CarDoor)",
		function()
			local door = Model.door
			assert(door, "the DR458 has a door")
			expect(door.openAngle).toBeNear(math.rad(75), 1e-3)
			expect(door.pivot.right < 0).toBe(true)
			local rest = hingeRest(door.pivot, door.axis)
			local rearEdge = beside(rest, -1, 0, 0)
			local shut = metres(rearEdge)
			local open = carried(rearEdge, rest, rest * CFrame.Angles(Hinge.angle(1, door.openAngle), 0, 0))
			expect(open.right < shut.right - 0.9).toBe(true)
			expect(math.abs(open.up - shut.up) < 0.1).toBe(true)
		end
	)

	-- The binding names no wheel axis: Car/VehicleRunner spins each bound tyre about the chassis's x
	-- at its own centre. The binding decides which tyre each physics wheel turns and what rides it.
	it(
		"puts each physics wheel on the tyre at its corner, which rolls forward with its rim on a positive spin",
		function()
			local parents = Model.parents
			assert(parents, "the DR458's wheels carry their rims")
			local centre = ManifestBinding.centreOfMass(DR458)
			local positions = Geometry.wheelPositions(DR458)
			expect(#Model.wheels).toBe(#positions)
			for slot, tyre in Model.wheels do
				-- The corner's spin root, the rim, carries the wheel's centre and axle.
				local rim = part(part(tyre).group)
				local hub = ManifestBinding.toRig(vector(rim.pivot), centre)
				expect(hub.forward).toBeNear(positions[slot].forward, 0.05)
				expect(hub.right).toBeNear(positions[slot].right, 0.05)
				expect(math.abs(vector(rim.axis).right)).toBeNear(1, 1e-3)
				for _, rider in MANIFEST.parts do
					if rider.group == rim.name and rider.name ~= tyre then
						expect(parents[rider.name]).toBe(tyre)
					end
				end
				for rider, carrier in parents do
					if carrier == tyre then
						expect(part(rider).group).toBe(rim.name)
					end
				end
				local rest = CFrame.new(studs(hub))
				local top = beside(rest, 0, 0, 0.3)
				local spun = CFrame.new(rest.Position) * CFrame.Angles(-0.1, 0, 0) * rest.Rotation
				expect(carried(top, rest, spun).forward > metres(top).forward).toBe(true)
			end
		end
	)

	it(
		"turns the steering hub anticlockwise as the driver sees it, and clockwise on a right steer",
		function()
			local hub = Model.steeringHub
			assert(hub, "the DR458's steering wheel turns on a hub")
			local pivot, axis, seat = hub.pivot, hub.axis, Model.seat
			local toSeat = {
				forward = seat.forward - pivot.forward,
				right = seat.right - pivot.right,
				up = seat.up - pivot.up,
			}
			expect(axis.forward * toSeat.forward + axis.right * toSeat.right + axis.up * toSeat.up > 0).toBe(
				true
			)
			-- As Car/VehicleRunner turns a steering wheel: its rest's +Z along the column toward the
			-- driver, turned by CFrame.Angles(0, 0, -angle) for a steer of `angle` to the right.
			local x, y, z = Hinge.frame(Hinge.chassis(axis))
			local rest = frameAt(pivot, { x = -z.x, y = -z.y, z = -z.z }, y, x)
			local top = rest * Vector3.new(0, Units.metresToStuds(0.17), 0)
			local level = metres(top).right
			expect(carried(top, rest, rest * CFrame.Angles(0, 0, 0.1)).right < level - 0.01).toBe(true)
			expect(carried(top, rest, rest * CFrame.Angles(0, 0, -0.1)).right > level + 0.01).toBe(true)
		end
	)

	it(
		"turns the start-up's controls from rest to on (Controllers/CarDoor): key anticlockwise from above, guard up, switch from down to up",
		function()
			local controls = Model.controls
			assert(controls, "the DR458 has controls")
			-- Its modelled pose, its rest (the binding's `rest` from there), and on: the start-up's move
			-- turned in full from rest.
			local function poses(name: string): (CFrame, CFrame, CFrame)
				local hinge = controls[name]
				assert(hinge, `the DR458's binding has {name}`)
				local modelled = hingeRest(hinge.pivot, hinge.axis)
				local rest = modelled * CFrame.Angles(hinge.rest or 0, 0, 0)
				local angle = 0
				for _, move in Startup.moves do
					if move.control == name then
						angle = Hinge.angle(1, move.angle)
					end
				end
				return modelled, rest, rest * CFrame.Angles(angle, 0, 0)
			end

			local modelled, rest, on = poses("TunnelKey_Master")
			local grip = beside(modelled, 0.03, 0, 0)
			expect(carried(grip, modelled, on).right < carried(grip, modelled, rest).right - 0.02).toBe(true)

			modelled, rest, on = poses("PanelGuard_Ignition")
			local edge = beside(modelled, 0, 0, -0.03)
			local closed, lifted = carried(edge, modelled, rest), carried(edge, modelled, on)
			expect(lifted.up > closed.up + 0.02 and lifted.forward < closed.forward).toBe(true)

			modelled, rest, on = poses("PanelSwitch_Ignition")
			local tip = beside(modelled, -0.02, 0, 0)
			local pivot = metres(modelled.Position)
			expect(carried(tip, modelled, rest).up < pivot.up).toBe(true)
			expect(carried(tip, modelled, on).up > pivot.up).toBe(true)
		end
	)

	it(
		"presses each pedal through its travel (Controllers/DriverLegs): the hanging brake pad and the throttle pad move toward the nose, the throttle's down",
		function()
			local pedals = Model.pedals
			assert(pedals, "the DR458 has pedals")
			-- The brake's pad hangs below its pivot; the organ throttle's rises from its floor hinge,
			-- the heel at the hinge and the toes ahead of it.
			local pads = {
				Pedal_Brake = { forward = 0, up = -0.35 },
				Pedal_Throttle = { forward = 0.05, up = 0.09 },
			}
			for _, pedal in pedals do
				expect(pedal.axis.right).toBe(1)
				local rest = hingeRest(pedal.pivot, pedal.axis)
				local spot = pads[pedal.part]
				assert(spot, `a pad point for {pedal.part}`)
				local pad = beside(rest, spot.forward, 0, spot.up)
				local free = metres(pad)
				local pressed = carried(pad, rest, rest * CFrame.Angles(pedal.travel or 0, 0, 0))
				expect(pressed.forward > free.forward + 0.005).toBe(true)
				if pedal.part == "Pedal_Throttle" then
					expect(pressed.up < free.up).toBe(true)
				end
			end
		end
	)

	it("points each exhaust outlet out of the back of the car", function()
		local outlets = Model.exhaustOutlets
		assert(outlets and #outlets > 0, "the DR458 has exhaust outlets")
		for _, outlet in outlets do
			expect(outlet.axis.forward < -0.9).toBe(true)
		end
	end)
end)

describe("DR458 start-up", function()
	it(
		"turns each of its controls through the binding's travel, one after another, after the start key and before START",
		function()
			local controls = Model.controls
			assert(controls, "the DR458 has controls")
			-- A move turns over `move` seconds and arrives at `at` (Rules/CarEntry.controlOpenness).
			local free = 0
			for _, move in Startup.moves do
				local hinge = controls[move.control]
				expect(hinge and move.angle).toBe(hinge and hinge.travel)
				expect(move.at - move.move >= free).toBe(true)
				free = move.at
				expect(move.at <= Startup.pressAt).toBe(true)
			end
			expect(Startup.moves[1].control).toBe("TunnelKey_Master")
			expect(Startup.moves[3].control).toBe("PanelSwitch_Ignition")
		end
	)
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
