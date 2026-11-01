--!strict
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Boss302Model = require("../src/shared/Config/Cars/Boss302/Model")
local Boss302Physics = require("../src/shared/Config/Cars/Boss302/Physics")
local Config = require("../src/shared/Config/DriverShift")
local ShiftHand = require("../src/shared/Rules/ShiftHand")
local Types = require("../src/shared/Config/Cars/Types")
local StartupArms = require("../src/shared/Rules/StartupArms")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

type Pose = ShiftHand.Pose

-- A lever for the specs: upright, 25 cm from pivot to knob, the H's columns 9 degrees apart with
-- reverse beyond first, 12.5 degrees fore and aft (a car's real one comes from its model binding).
local SHIFTER: ShiftHand.Lever = {
	pivot = { x = 0.35, y = -0.2, z = -0.3 },
	knob = { x = 0.35, y = 0.05, z = -0.3 },
	right = { x = 1, y = 0, z = 0 },
	back = { x = 0, y = 0, z = 1 },
	columns = {
		{ column = -1, degrees = -18 },
		{ column = 0, degrees = -9 },
		{ column = 1, degrees = 0 },
		{ column = 2, degrees = 9 },
	},
	forward = 12.5,
	backward = 12.5,
	push = 0.012,
}

local HALF = math.sqrt(0.5)
-- The wrist 7 cm above the knob's centre and 6 cm toward the driver, turned a quarter about x.
local GRIP: Config.Key = { 0, 0, 0.07, 0.06, HALF, HALF, 0, 0 }

local SHIFT: Config.Shift = {
	knobRadius = 0.025,
	grip = GRIP,
	hand = {
		keys = {
			{ 0, 0.2, 0.25, -0.35, 1, 0, 0, 0 },
			{ 0.15, 0.3, 0.12, -0.2, 0.9239, 0.3827, 0, 0 },
			{ 0.3, 0.35, 0.12, -0.18, HALF, HALF, 0, 0 },
		},
		shapes = { { at = 0, shape = "Grip" }, { at = 0.05, shape = "Rest" }, { at = 0.25, shape = "Knob" } },
	},
	reach = 0.3,
	release = 0.3,
	foot = 0.2,
}

local function distance(a: StartupArms.Vector, b: StartupArms.Vector): number
	return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
end

-- The angle (radians) between two rotations.
local function turnBetween(a: StartupArms.Rotation, b: StartupArms.Rotation): number
	local d = math.abs(a.w * b.w + a.x * b.x + a.y * b.y + a.z * b.z)
	return 2 * math.acos(math.min(1, d))
end

describe("Shift hand: the lever", function()
	it("stands the knob a lever's length above the pivot in neutral and leans it into the gates", function()
		local pivot, length = SHIFTER.pivot, 0.25
		local neutral = ShiftHand.lever(SHIFTER, 1, 0, 0).position
		expect(distance(neutral, { x = pivot.x, y = pivot.y + length, z = pivot.z })).toBeNear(0, 1e-12)
		local first = ShiftHand.lever(SHIFTER, 0, 1, 0).position
		-- Sideways about the forward axis for the column, then fore and aft about the car's right.
		local s, f = math.rad(9), math.rad(12.5)
		expect(first.x).toBeNear(pivot.x - length * math.sin(s), 1e-12)
		expect(first.y).toBeNear(pivot.y + length * math.cos(s) * math.cos(f), 1e-12)
		expect(first.z).toBeNear(pivot.z - length * math.cos(s) * math.sin(f), 1e-12)
		local sixth = ShiftHand.lever(SHIFTER, 2, -1, 0).position
		expect(sixth.z > pivot.z).toBe(true)
		expect(sixth.x > neutral.x).toBe(true)
		for _, place in { { -1, 1 }, { 0, -1 }, { 1, 1 }, { 2, -1 }, { 0.5, 0 }, { 1.7, 0.4 } } do
			local knob = ShiftHand.lever(SHIFTER, place[1], place[2], 0).position
			expect(distance(knob, pivot)).toBeNear(length, 1e-12)
			local pushed = ShiftHand.lever(SHIFTER, place[1], place[2], 1).position
			expect(distance(pushed, pivot)).toBeNear(length - SHIFTER.push, 1e-12)
		end
	end)

	it("turns between its columns' angles and holds past the outer ones", function()
		expect(ShiftHand.columnAngle(SHIFTER, 0.5)).toBeNear(-4.5, 1e-12)
		expect(ShiftHand.columnAngle(SHIFTER, 1.5)).toBeNear(4.5, 1e-12)
		expect(ShiftHand.columnAngle(SHIFTER, -3)).toBe(-18)
		expect(ShiftHand.columnAngle(SHIFTER, 5)).toBe(9)
		local a = ShiftHand.lever(SHIFTER, 0.999, 0, 0).position
		local b = ShiftHand.lever(SHIFTER, 1.001, 0, 0).position
		expect(distance(a, b) < 1e-4).toBe(true)
	end)

	it("carries the grip with the lever: the wrist keeps its place in the knob's frame", function()
		for _, place in { { 1, 0 }, { 1, 1 }, { 2, -1 }, { -1, 1 } } do
			local knob = ShiftHand.lever(SHIFTER, place[1], place[2], 0)
			local wrist = ShiftHand.knobWrist(knob, GRIP)
			expect(distance(wrist.position, knob.position)).toBeNear(math.sqrt(0.07 ^ 2 + 0.06 ^ 2), 1e-9)
			local held = StartupArms.multiply(knob.rotation, { w = HALF, x = HALF, y = 0, z = 0 })
			expect(turnBetween(wrist.rotation, held)).toBeNear(0, 1e-6)
			-- 7 cm up the lever, whichever way it leans: the lever's axis from its pivot to the knob.
			local offset = {
				x = wrist.position.x - knob.position.x,
				y = wrist.position.y - knob.position.y,
				z = wrist.position.z - knob.position.z,
			}
			local p = SHIFTER.pivot
			local axis = { x = knob.position.x - p.x, y = knob.position.y - p.y, z = knob.position.z - p.z }
			local along = (offset.x * axis.x + offset.y * axis.y + offset.z * axis.z) / 0.25
			expect(along).toBeNear(0.07, 1e-9)
		end
		local upright = ShiftHand.lever(SHIFTER, 1, 0, 0)
		local wrist = ShiftHand.knobWrist(upright, GRIP)
		expect(wrist.position.y).toBeNear(upright.position.y + 0.07, 1e-9)
		expect(wrist.position.z).toBeNear(upright.position.z + 0.06, 1e-9)
	end)
end)

describe("Shift hand: the lever from the car's model binding", function()
	local shifter = assert(Boss302Model.shifter, "the Boss binds its lever")
	local gates = (Boss302Physics.gearbox.manual :: Types.ManualGearboxConfig).gates
	local seat = { forward = 0.4, right = -0.3, up = 0.1 }
	local lever = ShiftHand.leverFromBinding(shifter, gates, seat)

	it("puts the pivot and knob in the seat's frame and turns about the car's right and back", function()
		expect(lever.pivot.x).toBeNear(shifter.pivot.right - seat.right, 1e-12)
		expect(lever.pivot.y).toBeNear(shifter.pivot.up - seat.up, 1e-12)
		expect(lever.pivot.z).toBeNear(seat.forward - shifter.pivot.forward, 1e-12)
		expect(lever.knob.x).toBeNear(shifter.knob.right - seat.right, 1e-12)
		expect(lever.knob.y).toBeNear(shifter.knob.up - seat.up, 1e-12)
		expect(lever.knob.z).toBeNear(seat.forward - shifter.knob.forward, 1e-12)
		expect(distance(lever.right, { x = 1, y = 0, z = 0 })).toBeNear(0, 1e-12)
		expect(distance(lever.back, { x = 0, y = 0, z = 1 })).toBeNear(0, 1e-12)
		expect(lever.push).toBe(shifter.push)
	end)

	it("takes each column's angle and the rows' throws from the binding's gates", function()
		local expected = { { -1, -18 }, { 0, -9 }, { 1, 0 }, { 2, 9 } }
		expect(#lever.columns).toBe(#expected)
		for index, column in expected do
			expect(lever.columns[index].column).toBe(column[1])
			expect(lever.columns[index].degrees).toBeNear(column[2], 1e-3)
		end
		expect(lever.forward).toBeNear(12.5, 1e-3)
		expect(lever.backward).toBeNear(12.5, 1e-3)
	end)

	it("leans the knob to the driver's view of the MT-82's H: 1 up-left, 6 down-right, R past 1", function()
		local function at(gear: number): StartupArms.Vector
			local gate = gates[gear]
			return ShiftHand.lever(lever, gate.column, gate.row, 0).position
		end
		local neutral = at(0)
		expect(distance(neutral, lever.knob)).toBeNear(0, 1e-12)
		local first, sixth, reverse = at(1), at(6), at(-1)
		expect(first.x < neutral.x and first.z < neutral.z).toBe(true)
		expect(sixth.x > neutral.x and sixth.z > neutral.z).toBe(true)
		expect(reverse.x < first.x and reverse.z < neutral.z).toBe(true)
		expect(at(2).z > neutral.z and at(3).z < neutral.z).toBe(true)
	end)

	it("refuses gates whose gears of one column, or of one row, disagree on its angle", function()
		for _, change in { { "4", 0.05, nil }, { "3", nil, 0.3 }, { "6", nil, -0.1 } } do
			local skewed = table.clone(shifter.gates)
			local angles = skewed[change[1]]
			skewed[change[1]] = { side = change[2] or angles.side, fore = change[3] or angles.fore }
			local bent = table.clone(shifter)
			bent.gates = skewed
			expect(function()
				ShiftHand.leverFromBinding(bent, gates, seat)
			end).toThrow()
		end
	end)

	it("moves a part on the lever rigidly about the pivot, slid down the lever by the push", function()
		local pushing = table.clone(SHIFTER)
		for _, place in { { 1, 0, 0 }, { 0, 1, 0 }, { 2, -1, 0 }, { -1, 1, 1 }, { 0.4, 0, 0.5 } } do
			local turn, slide = ShiftHand.joint(pushing, place[1], place[2], place[3])
			local pose = ShiftHand.lever(pushing, place[1], place[2], place[3])
			local p = pushing.pivot
			local reach = { x = pushing.knob.x - p.x, y = pushing.knob.y - p.y, z = pushing.knob.z - p.z }
			-- The knob's modelled centre lands where the lever's pose puts it.
			local q = turn
			local t = {
				x = 2 * (q.y * reach.z - q.z * reach.y),
				y = 2 * (q.z * reach.x - q.x * reach.z),
				z = 2 * (q.x * reach.y - q.y * reach.x),
			}
			local turned = {
				x = reach.x + q.w * t.x + (q.y * t.z - q.z * t.y),
				y = reach.y + q.w * t.y + (q.z * t.x - q.x * t.z),
				z = reach.z + q.w * t.z + (q.x * t.y - q.y * t.x),
			}
			local landed =
				{ x = p.x + slide.x + turned.x, y = p.y + slide.y + turned.y, z = p.z + slide.z + turned.z }
			expect(distance(landed, pose.position)).toBeNear(0, 1e-12)
			local length = math.sqrt(slide.x ^ 2 + slide.y ^ 2 + slide.z ^ 2)
			expect(length).toBeNear(pushing.push * place[3], 1e-12)
			expect(turnBetween(turn, pose.rotation)).toBeNear(0, 1e-9)
		end
	end)
end)

describe("Shift hand: between the wheel and the knob", function()
	-- The live grip and knob away from where the keys were made, as when the wheel is turned and the
	-- lever is in third.
	local grip: Pose =
		{ position = { x = 0.18, y = 0.27, z = -0.36 }, rotation = { w = 0.9962, x = 0, y = 0, z = 0.0872 } }
	local knobWrist = ShiftHand.knobWrist(ShiftHand.lever(SHIFTER, 1, 1, 0), GRIP)

	it("starts on the live grip and ends on the live knob", function()
		local start = ShiftHand.pose(SHIFT, 0, grip, knobWrist)
		expect(distance(start.position, grip.position)).toBeNear(0, 1e-9)
		expect(turnBetween(start.rotation, grip.rotation)).toBeNear(0, 1e-6)
		local finish = ShiftHand.pose(SHIFT, 1, grip, knobWrist)
		expect(distance(finish.position, knobWrist.position)).toBeNear(0, 1e-9)
		expect(turnBetween(finish.rotation, knobWrist.rotation)).toBeNear(0, 1e-6)
	end)

	it("moves without a jump on the way", function()
		local span = distance(grip.position, knobWrist.position)
		local previous = ShiftHand.pose(SHIFT, 0, grip, knobWrist)
		for step = 1, 100 do
			local pose = ShiftHand.pose(SHIFT, step / 100, grip, knobWrist)
			expect(distance(pose.position, previous.position) < span * 0.05).toBe(true)
			expect(turnBetween(pose.rotation, previous.rotation) < math.rad(5)).toBe(true)
			previous = pose
		end
	end)

	it("shows the grip, opens the hand, and closes it on the knob", function()
		local _, atWheel = ShiftHand.pose(SHIFT, 0, grip, knobWrist)
		local _, between = ShiftHand.pose(SHIFT, 0.5, grip, knobWrist)
		local _, atKnob = ShiftHand.pose(SHIFT, 1, grip, knobWrist)
		expect(atWheel).toBe("Grip")
		expect(between).toBe("Rest")
		expect(atKnob).toBe("Knob")
	end)
end)

describe("Shift hand: the wrist from the lever's place", function()
	local grip: Pose =
		{ position = { x = 0.18, y = 0.27, z = -0.36 }, rotation = { w = 0.9962, x = 0, y = 0, z = 0.0872 } }

	it("is the live grip at the wheel and the hand on the knob wherever the lever is", function()
		for _, place in { { 1, 0, 0 }, { 0, 1, 0 }, { 2, -1, 0 }, { -1, 1, 1 }, { 0.5, 0, 0 } } do
			local atWheel, shown = ShiftHand.wrist(SHIFT, SHIFTER, 0, place[1], place[2], place[3], grip)
			expect(distance(atWheel.position, grip.position)).toBeNear(0, 1e-9)
			expect(shown).toBe("Grip")
			local onKnob, held = ShiftHand.wrist(SHIFT, SHIFTER, 1, place[1], place[2], place[3], grip)
			local knob = ShiftHand.knobWrist(ShiftHand.lever(SHIFTER, place[1], place[2], place[3]), GRIP)
			expect(distance(onKnob.position, knob.position)).toBeNear(0, 1e-9)
			expect(turnBetween(onKnob.rotation, knob.rotation)).toBeNear(0, 1e-6)
			expect(held).toBe("Knob")
		end
	end)

	it("puts the Boss's knob where the shift-hand tool keyed it, at every gate and on the way", function()
		local data =
			serde.decode("json", fs.readFile("games/drive-lab/tests/fixtures/boss302_shift_parity.json"))
		local shifter = assert(Boss302Model.shifter, "the Boss binds its lever")
		local gates = (Boss302Physics.gearbox.manual :: Types.ManualGearboxConfig).gates
		local lever = ShiftHand.leverFromBinding(shifter, gates, Boss302Model.seat)
		local checked = 0
		for _, place in data.parity do
			local knob = ShiftHand.lever(lever, place.column, place.row, place.knob)
			local p = place.position
			expect(distance(knob.position, { x = p[1], y = p[2], z = p[3] })).toBeNear(0, 1e-5)
			-- Component by component (the tool rounds to 7 decimals; an angle through acos near 1
			-- would turn that rounding into about 5e-4 rad).
			local q, r = place.rotation, knob.rotation
			local sign = if r.w * q[1] + r.x * q[2] + r.y * q[3] + r.z * q[4] < 0 then -1 else 1
			for index, component in { r.w, r.x, r.y, r.z } do
				expect(component).toBeNear(sign * q[index], 1e-6)
			end
			checked += 1
		end
		expect(checked).toBe(14)
	end)
end)
