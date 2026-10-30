--!strict
local Binding = require("../src/shared/Config/Cars/Binding")
local CarEntry = require("../src/shared/Config/CarEntry")
local DoorStrap = require("../src/shared/Rules/DoorStrap")
local Entry = require("../src/shared/Rules/CarEntry")
local Hinge = require("../src/shared/Rules/Hinge")
local SVJModel = require("../src/shared/Config/Cars/SVJ/Model")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local function near(actual: Hinge.Vector, expected: Hinge.Vector, tolerance: number)
	expect(actual.x).toBeNear(expected.x, tolerance)
	expect(actual.y).toBeNear(expected.y, tolerance)
	expect(actual.z).toBeNear(expected.z, tolerance)
end

local SHAPE: DoorStrap.Shape = {
	length = 0.25,
	lean = math.rad(5),
	hang = {
		{ angle = 0, length = 0.16 },
		{ angle = 0.02, length = 0.02 },
		{ angle = 0.1, length = 0.2 },
		{ angle = 0.3, length = 0.25 },
	},
}
local GRAB = math.rad(30)
local TOP = { x = -0.6, y = -0.2, z = -0.5 }
-- The card facing straight into the cabin, so its hang leans inboard (+x) only.
local INBOARD = { x = 1, y = 0, z = 0 }

local function state(overrides: { [string]: any }): Entry.State
	local base: Entry.State = {
		entry = "None",
		entryAt = 0,
		entryDoorOpen = false,
		door = "Closed",
		doorAt = 0,
		engine = "Off",
		engineAt = 0,
	}
	for key, value in overrides do
		(base :: any)[key] = value
	end
	return base
end

describe("DoorStrap", function()
	describe("when the hand holds it", function()
		it("holds it in a strap-closing clip from the grab angle down", function()
			expect(DoorStrap.held("InsideClose", GRAB, GRAB)).toBe(true)
			expect(DoorStrap.held("InsideClose", math.rad(10), GRAB)).toBe(true)
			expect(DoorStrap.held("GetIn", math.rad(29), GRAB)).toBe(true)
		end)

		it("does not hold it while the door is still above the grab angle", function()
			expect(DoorStrap.held("InsideClose", math.rad(31), GRAB)).toBe(false)
			expect(DoorStrap.held("GetIn", math.rad(45), GRAB)).toBe(false)
		end)

		it("lets go as the door shuts", function()
			expect(DoorStrap.held("InsideClose", 0, GRAB)).toBe(false)
		end)

		it("is never held by a clip that opens the door, nor at rest", function()
			for _, clip in { "InsideOpen", "OutsideOpen", "OutsideClose", "GetOut" } do
				expect(DoorStrap.held(clip, math.rad(10), GRAB)).toBe(false)
			end
			expect(DoorStrap.held(nil, math.rad(10), GRAB)).toBe(false)
		end)
	end)

	describe("the clip moving the door", function()
		it("is the seated door motion while it plays, and nothing once it has finished", function()
			local close = state({ entry = "Enter", entryAt = 0, door = "InsideClose", doorAt = 100 })
			expect(DoorStrap.clip(close, 100.5)).toBe("InsideClose")
			expect(DoorStrap.clip(close, 100 + CarEntry.CLIPS.InsideClose.duration + 0.01)).toBe(nil)
		end)

		it("is the running sequence's step, which drives the door over its own motion", function()
			local entering = state({ entry = "Enter", entryAt = 10, door = "Closed" })
			local steps = Entry.steps("Enter", false)
			local second = steps[2]
			expect(DoorStrap.clip(entering, 10 + second.start + 0.1)).toBe(second.clip)
			expect(DoorStrap.clip(entering, 10.1)).toBe(steps[1].clip)
		end)

		it("is nothing with the door at rest", function()
			expect(DoorStrap.clip(state({ door = "Open", doorAt = 5 }), 5.1)).toBe(nil)
			expect(DoorStrap.clip(state({ door = "Closed" }), 5)).toBe(nil)
		end)
	end)

	describe("held", function()
		it("runs from its top toward the palm, as far as the palm", function()
			local palm = { x = TOP.x + 0.1, y = TOP.y + 0.08, z = TOP.z }
			local pose = DoorStrap.pose(SHAPE, TOP, INBOARD, 0.2, palm)
			expect(pose.length).toBeNear(math.sqrt(0.1 ^ 2 + 0.08 ^ 2), 1e-12)
			near(pose.direction, { x = 0.1 / pose.length, y = 0.08 / pose.length, z = 0 }, 1e-12)
		end)

		it("never runs past its length toward a palm out of reach", function()
			local palm = { x = TOP.x, y = TOP.y + 0.4, z = TOP.z - 0.3 }
			local pose = DoorStrap.pose(SHAPE, TOP, INBOARD, 0.2, palm)
			expect(pose.length).toBeNear(0.25, 1e-12)
			near(pose.direction, { x = 0, y = 0.8, z = -0.6 }, 1e-12)
		end)

		it("hangs when the palm sits on its top", function()
			local pose = DoorStrap.pose(SHAPE, TOP, INBOARD, 0.3, TOP)
			expect(pose.length).toBeNear(0.25, 1e-12)
			expect(pose.direction.y).toBeNear(-math.cos(math.rad(5)), 1e-12)
		end)
	end)

	describe("hanging", function()
		it("hangs down, leaned off the card toward the cabin", function()
			near(
				DoorStrap.hanging(INBOARD, math.rad(5)),
				{ x = math.sin(math.rad(5)), y = -math.cos(math.rad(5)), z = 0 },
				1e-12
			)
			-- A card tilted face-down leans it along the card's level facing only.
			local tilted = DoorStrap.hanging({ x = 0.6, y = -0.8, z = 0 }, math.rad(5))
			near(tilted, { x = math.sin(math.rad(5)), y = -math.cos(math.rad(5)), z = 0 }, 1e-12)
		end)

		it("leans inboard when the card faces straight down", function()
			near(
				DoorStrap.hanging({ x = 0, y = -1, z = 0 }, math.rad(5)),
				{ x = math.sin(math.rad(5)), y = -math.cos(math.rad(5)), z = 0 },
				1e-12
			)
		end)

		it("is as long as the trim lets it: linear between rows, held past the ends", function()
			expect(DoorStrap.hangLength(SHAPE, 0)).toBeNear(0.16, 1e-12)
			expect(DoorStrap.hangLength(SHAPE, 0.01)).toBeNear(0.09, 1e-12)
			expect(DoorStrap.hangLength(SHAPE, 0.06)).toBeNear(0.11, 1e-12)
			expect(DoorStrap.hangLength(SHAPE, -0.05)).toBeNear(0.16, 1e-12)
			expect(DoorStrap.hangLength(SHAPE, 2)).toBeNear(0.25, 1e-12)
			local pose = DoorStrap.pose(SHAPE, TOP, INBOARD, 0.01, nil)
			expect(pose.length).toBeNear(0.09, 1e-12)
		end)

		it("is never longer than the strap, whatever a row says", function()
			local long = {
				length = 0.25,
				lean = 0,
				hang = { { angle = 0, length = 0.3 }, { angle = 1, length = 0.4 } },
			}
			expect(DoorStrap.hangLength(long, 0)).toBeNear(0.25, 1e-12)
			expect(DoorStrap.hangLength(long, 0.5)).toBeNear(0.25, 1e-12)
			expect(DoorStrap.hangLength(long, 2)).toBeNear(0.25, 1e-12)
		end)
	end)

	describe("the SVJ's strap", function()
		local door = SVJModel.door :: any
		local strap = door.strap :: Binding.DoorStrap

		it("turns with the door as in Blender (door rig, 30 degrees)", function()
			-- hero_car_door_strap.py strap.json: the top at 30 degrees, Blender
			-- (0.93345, -0.12122, 0.61210); car frame forward = -(y - 0.279), right = -x, up = z - 0.4314.
			local turned = Hinge.rotate(
				Hinge.chassis(strap.top),
				Hinge.chassis(door.pivot),
				Hinge.chassis(door.axis),
				math.rad(30)
			)
			near(turned, Hinge.chassis({ forward = 0.40022, right = -0.93345, up = 0.18070 }), 1e-3)
		end)

		it("is 25 cm, taken at 30 degrees, its rows ascending, never longer, past the open angle", function()
			expect(strap.length).toBeNear(0.25, 1e-12)
			expect(strap.grab).toBeNear(math.rad(30), 1e-12)
			local facing = strap.facing
			expect(math.sqrt(facing.forward ^ 2 + facing.right ^ 2 + facing.up ^ 2)).toBeNear(1, 1e-4)
			for index, row in strap.hang do
				expect(row.length <= strap.length).toBe(true)
				if index > 1 then
					expect(row.angle > strap.hang[index - 1].angle).toBe(true)
				end
			end
			expect(strap.hang[#strap.hang].angle >= door.openAngle).toBe(true)
		end)
	end)
end)
