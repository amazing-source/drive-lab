--!strict
local Binding = require("../src/shared/Config/Cars/Binding")
local CarEntryRules = require("../src/shared/Rules/CarEntry")
local Hinge = require("../src/shared/Rules/Hinge")
local Model = require("../src/shared/Config/Cars/DR458/Model")
local Paths = require("../src/shared/Config/Cars/DR458/StartupPaths")
local Startup = require("../src/shared/Config/Cars/DR458/Startup")
local StartupArms = require("../src/shared/Rules/StartupArms")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

type Vector = StartupArms.Vector

-- How close the hand stays to a control while the game turns it, metres (as the SVJ's flap).
local TOUCH_GAP = 0.002
local TOUCHES = assert(Paths.TOUCHES, "the DR458's paths list the controls the hand works")
local CONTROLS = assert(Model.controls, "the DR458's binding hinges its start-up controls")

local RUNNING: CarEntryRules.State = {
	entry = "Enter",
	entryAt = -100,
	entryDoorOpen = false,
	door = "Closed",
	doorAt = 0,
	engine = "On",
	engineAt = 0,
}

local function gap(a: Vector, b: Vector): number
	return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
end

-- A binding point in the DriverSeat's frame: the seat and the controls ride the same body raise.
local function inSeat(point: Binding.CarPoint): Vector
	local p, s = Hinge.chassis(point), Hinge.chassis(Model.seat)
	return { x = p.x - s.x, y = p.y - s.y, z = p.z - s.z }
end

local function moveOf(control: string)
	for _, move in Startup.moves do
		if move.control == control then
			return move
		end
	end
	return nil
end

-- Where a touched point of a control is at `t`, turned as Controllers/CarDoor turns the control.
local function controlPoint(touch, t: number): Vector
	local move = assert(moveOf(touch.control), `no start-up move for {touch.control}`)
	local hinge = CONTROLS[touch.control]
	local angle = Hinge.angle(CarEntryRules.controlOpenness(move, RUNNING, t), move.angle)
	return Hinge.rotate(touch.point, inSeat(hinge.pivot), Hinge.chassis(hinge.axis), angle)
end

local function handPoint(offset: Vector, t: number): Vector
	return StartupArms.apply(StartupArms.sample(Paths.RIGHT.keys, t), offset)
end

describe("DR458 start-up hands: the controls the game turns", function()
	it("has the right hand work every control the start-up turns, each once", function()
		local worked: { [string]: number } = {}
		for _, touch in TOUCHES do
			worked[touch.control] = (worked[touch.control] or 0) + 1
			expect(moveOf(touch.control) ~= nil).toBe(true)
		end
		for _, move in Startup.moves do
			expect(worked[move.control]).toBe(1)
		end
	end)

	it("keeps the hand on each control, to 2 mm, the whole time the game turns it", function()
		for _, touch in TOUCHES do
			local move = assert(moveOf(touch.control), touch.control)
			local from = move.at - move.move
			local worst = 0
			for step = 0, 20 do
				local t = from + move.move * step / 20
				worst = math.max(worst, gap(handPoint(touch.tip, t), controlPoint(touch, t)))
			end
			expect(worst < TOUCH_GAP).toBe(true)
		end
	end)

	it("shows the hand the touch was keyed with while it works the control", function()
		for _, touch in TOUCHES do
			local move = assert(moveOf(touch.control), touch.control)
			for _, t in { move.at - move.move, move.at - move.move / 2, move.at } do
				expect(StartupArms.shape(Paths.RIGHT, t)).toBe(touch.shape)
			end
		end
	end)

	it("pushes ENGINE START to its face at the press, from a few millimetres off it", function()
		local button = Paths.BUTTON
		local function aboveButton(t: number): number
			local tip = handPoint(Paths.FINGERTIP, t)
			local top, normal = button.top, button.normal
			return (tip.x - top.x) * normal.x + (tip.y - top.y) * normal.y + (tip.z - top.z) * normal.z
		end
		expect(math.abs(aboveButton(Startup.pressAt)) < 0.001).toBe(true)
		expect(aboveButton(Startup.pressAt - 0.16) > button.depth * 0.8).toBe(true)
		expect(StartupArms.shape(Paths.RIGHT, Startup.pressAt)).toBe("Point")
	end)
end)

describe("DR458 start-up hands: the keyed paths", function()
	it("start resting, run in time order with unit rotations and end on the wheel when it says", function()
		for _, keyed in { Paths.RIGHT, Paths.LEFT } do
			local keys = keyed.keys
			expect(keys[1][1]).toBe(0)
			for index = 2, #keys do
				expect(keys[index][1] > keys[index - 1][1]).toBe(true)
			end
			for _, key in keys do
				expect(key[5] ^ 2 + key[6] ^ 2 + key[7] ^ 2 + key[8] ^ 2).toBeNear(1, 1e-3)
			end
			expect(keys[#keys][1] <= Startup.wheelAt + 1e-9).toBe(true)
			expect(keyed.gripFrom < keys[#keys][1]).toBe(true)
			expect(keyed.shapes[1].shape).toBe("Rest")
			expect(StartupArms.shape(keyed, keys[#keys][1])).toBe("Grip")
		end
		expect(Paths.RIGHT.keys[#Paths.RIGHT.keys][1]).toBeNear(Startup.wheelAt, 1e-9)
		expect(Paths.MESHES.Pinch ~= nil).toBe(true)
	end)
end)
