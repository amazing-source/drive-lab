--!strict
local Config = require("../src/shared/Config/DriverShift")
local ShiftHand = require("../src/shared/Rules/ShiftHand")
local StartupArms = require("../src/shared/Rules/StartupArms")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

type Pose = ShiftHand.Pose

-- A lever for the specs: upright, 25 cm from pivot to knob, the H's columns 9 degrees apart with
-- reverse beyond first, 12.5 degrees fore and aft (a car's real one comes from shift_paths.py).
local SHIFTER: Config.Shifter = {
	pivot = { x = 0.35, y = -0.2, z = -0.3 },
	knob = { x = 0.35, y = 0.05, z = -0.3 },
	right = { x = 1, y = 0, z = 0 },
	back = { x = 0, y = 0, z = 1 },
	knobRadius = 0.025,
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
	shifter = SHIFTER,
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
