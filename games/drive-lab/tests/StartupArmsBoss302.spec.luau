--!strict
local Binding = require("../src/shared/Config/Cars/Binding")
local CarEntryRules = require("../src/shared/Rules/CarEntry")
local Hinge = require("../src/shared/Rules/Hinge")
local Model = require("../src/shared/Config/Cars/Boss302/Model")
local Paths = require("../src/shared/Config/Cars/Boss302/StartupPaths")
local Startup = require("../src/shared/Config/Cars/Boss302/Startup")
local StartupArms = require("../src/shared/Rules/StartupArms")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

type Vector = StartupArms.Vector

-- How close the pinch stays to the key while the game turns it, metres (as the DR458's).
local TOUCH_GAP = 0.002
-- By the time the key springs back, the pinch has left its grip by at least this, metres.
local LET_GO = 0.008
-- The least cosine between the palm and the way to the column's axis while the key is held.
local PALM_TOWARD_COLUMN = 0.5
local TOUCHES = assert(Paths.TOUCHES, "the Boss's paths list the controls the hand works")
local CONTROLS = assert(Model.controls, "the Boss's binding hinges its key")
local HUB = assert(Model.steeringHub, "the Boss's binding places its steering hub")

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

local function inSeat(point: Binding.CarPoint): Vector
	local p, s = Hinge.chassis(point), Hinge.chassis(Model.seat)
	return { x = p.x - s.x, y = p.y - s.y, z = p.z - s.z }
end

local function movesOf(control: string)
	local found = {}
	for _, move in Startup.moves do
		if move.control == control then
			table.insert(found, move)
		end
	end
	return found
end

-- Where a touched point of the key is at `t`: its moves add up, as Controllers/CarDoor turns it.
local function controlPoint(touch, t: number): Vector
	local hinge = CONTROLS[touch.control]
	local angle = 0
	for _, move in movesOf(touch.control) do
		angle += Hinge.angle(CarEntryRules.controlOpenness(move, RUNNING, t), move.angle)
	end
	return Hinge.rotate(touch.point, inSeat(hinge.pivot), Hinge.chassis(hinge.axis), angle)
end

local function handPoint(offset: Vector, t: number): Vector
	return StartupArms.apply(StartupArms.sample(Paths.RIGHT.keys, t), offset)
end

local KEY = TOUCHES[1]
local MOVES = movesOf(KEY.control)
local FIRST, LAST = MOVES[1], MOVES[#MOVES]
local SPRING = assert(LAST.back, "the key springs back from START")

describe("Boss 302 start-up hands: the key", function()
	it("turns one key, to ON and then on to START, the START landing on the press", function()
		expect(#TOUCHES).toBe(1)
		expect(KEY.control).toBe("Key_Ignition")
		expect(KEY.shape).toBe("KeyPinch")
		expect(Paths.MESHES.KeyPinch ~= nil).toBe(true)
		expect(#MOVES).toBe(2)
		expect(LAST.at).toBeNear(Startup.pressAt, 1e-9)
		expect(Paths.BUTTON).toBe(nil)
	end)

	it("pinches the key, to 2 mm, from before it leaves OFF until the press and through the crank", function()
		local from, to = FIRST.at - FIRST.move, SPRING - 0.07
		local worst = 0
		for step = 0, 60 do
			local t = from + (to - from) * step / 60
			worst = math.max(worst, gap(handPoint(KEY.tip, t), controlPoint(KEY, t)))
		end
		expect(worst < TOUCH_GAP).toBe(true)
	end)

	it("turns the hand with the key, to 3 degrees, through ON and START", function()
		-- The pinch sits on the key's axis, so the turn is read from the hand's rotation about it.
		local hinge = CONTROLS[KEY.control]
		local axis = Hinge.chassis(hinge.axis)
		local length = math.sqrt(axis.x ^ 2 + axis.y ^ 2 + axis.z ^ 2)
		axis = { x = axis.x / length, y = axis.y / length, z = axis.z / length }
		local function dot(a: Vector, b: Vector): number
			return a.x * b.x + a.y * b.y + a.z * b.z
		end
		local function flat(v: Vector): Vector
			local along = dot(v, axis)
			return { x = v.x - axis.x * along, y = v.y - axis.y * along, z = v.z - axis.z * along }
		end
		local function keyAngle(t: number): number
			local angle = 0
			for _, move in MOVES do
				angle += Hinge.angle(CarEntryRules.controlOpenness(move, RUNNING, t), move.angle)
			end
			return angle
		end
		local origin = { x = 0, y = 0, z = 0 }
		local function handVector(t: number, local_: Vector): Vector
			return StartupArms.apply(
				{ position = origin, rotation = StartupArms.sample(Paths.RIGHT.keys, t).rotation },
				local_
			)
		end
		local from, to = FIRST.at - FIRST.move, SPRING - 0.07
		-- The hand's own axis that lies most across the key's at OFF, so its turn is well defined.
		local probe, best = { x = 1, y = 0, z = 0 }, -1
		for _, candidate in { { x = 1, y = 0, z = 0 }, { x = 0, y = 1, z = 0 }, { x = 0, y = 0, z = 1 } } do
			local across = flat(handVector(from, candidate))
			local size = dot(across, across)
			if size > best then
				probe, best = candidate, size
			end
		end
		local start = flat(handVector(from, probe))
		local worst = 0
		for step = 0, 60 do
			local t = from + (to - from) * step / 60
			local now = flat(handVector(t, probe))
			local cross = {
				x = start.y * now.z - start.z * now.y,
				y = start.z * now.x - start.x * now.z,
				z = start.x * now.y - start.y * now.x,
			}
			local turned = math.atan2(dot(cross, axis), dot(start, now))
			worst = math.max(worst, math.abs(math.deg(turned - (keyAngle(t) - keyAngle(from)))))
		end
		expect(worst < 3).toBe(true)
	end)

	it("shows the KeyPinch hand while it holds the key", function()
		for _, t in { FIRST.at - FIRST.move, FIRST.at, (FIRST.at + LAST.at) / 2, LAST.at, SPRING - 0.07 } do
			expect(StartupArms.shape(Paths.RIGHT, t)).toBe("KeyPinch")
		end
	end)

	it("holds the key with the palm toward the column, from OFF until it lets go", function()
		-- The palm is the wrist frame's -y (y runs out of the back of the hand).
		local pivot = inSeat(HUB.pivot)
		local axis = Hinge.chassis(HUB.axis)
		local size = math.sqrt(axis.x ^ 2 + axis.y ^ 2 + axis.z ^ 2)
		axis = { x = axis.x / size, y = axis.y / size, z = axis.z / size }
		local origin = { x = 0, y = 0, z = 0 }
		local from, to = FIRST.at - FIRST.move, SPRING - 0.07
		local least = math.huge
		for step = 0, 60 do
			local t = from + (to - from) * step / 60
			local pose = StartupArms.sample(Paths.RIGHT.keys, t)
			local palm = StartupArms.apply(
				{ position = origin, rotation = pose.rotation },
				{ x = 0, y = -1, z = 0 }
			)
			local pinch = handPoint(KEY.tip, t)
			local r = { x = pinch.x - pivot.x, y = pinch.y - pivot.y, z = pinch.z - pivot.z }
			local along = r.x * axis.x + r.y * axis.y + r.z * axis.z
			local toColumn = { x = axis.x * along - r.x, y = axis.y * along - r.y, z = axis.z * along - r.z }
			local length = math.sqrt(toColumn.x ^ 2 + toColumn.y ^ 2 + toColumn.z ^ 2)
			least =
				math.min(least, (palm.x * toColumn.x + palm.y * toColumn.y + palm.z * toColumn.z) / length)
		end
		expect(least > PALM_TOWARD_COLUMN).toBe(true)
	end)

	it("has let go of the key by the time it springs back from START", function()
		expect(gap(handPoint(KEY.tip, SPRING), controlPoint(KEY, SPRING)) > LET_GO).toBe(true)
	end)
end)

-- The rim's outer radius about the column's axis, metres (GEO_INT_STwheel_00 in the cockpit dump).
local RIM_RADIUS = 0.185

-- The radius from the column's axis at which a point of the right hand crosses the wheel's plane,
-- for every crossing between `from` and `to`.
local function rimCrossings(offset: Vector, from: number, to: number): { number }
	local pivot = inSeat(HUB.pivot)
	local axis = Hinge.chassis(HUB.axis)
	local size = math.sqrt(axis.x ^ 2 + axis.y ^ 2 + axis.z ^ 2)
	axis = { x = axis.x / size, y = axis.y / size, z = axis.z / size }
	local function relative(t: number): (Vector, number)
		local p = handPoint(offset, t)
		local r = { x = p.x - pivot.x, y = p.y - pivot.y, z = p.z - pivot.z }
		return r, r.x * axis.x + r.y * axis.y + r.z * axis.z
	end
	local radii = {}
	local steps = math.ceil((to - from) * 600)
	local before, beforeAlong = relative(from)
	for step = 1, steps do
		local now, along = relative(from + (to - from) * step / steps)
		if (beforeAlong > 0) ~= (along > 0) then
			local share = beforeAlong / (beforeAlong - along)
			local c = {
				x = before.x + (now.x - before.x) * share,
				y = before.y + (now.y - before.y) * share,
				z = before.z + (now.z - before.z) * share,
			}
			local across = c.x * axis.x + c.y * axis.y + c.z * axis.z
			table.insert(
				radii,
				math.sqrt(
					(c.x - axis.x * across) ^ 2 + (c.y - axis.y * across) ^ 2 + (c.z - axis.z * across) ^ 2
				)
			)
		end
		before, beforeAlong = now, along
	end
	return radii
end

describe("Boss 302 start-up hands: round the rim", function()
	it("goes round the rim's outside to the key and back, never through the wheel", function()
		-- The wrist, the key hand mesh's centre and the pinch: the hand passes the wheel outside its rim.
		local centre =
			assert((Paths.MESHES :: { [string]: Vector? })[KEY.shape], "the key hand's mesh centre")
		local POINTS = { { x = 0, y = 0, z = 0 }, centre, KEY.tip }
		local pinchEnd = SPRING
		while StartupArms.shape(Paths.RIGHT, pinchEnd) == KEY.shape do
			pinchEnd += 0.01
		end
		for _, window in { { 0, FIRST.at - FIRST.move }, { SPRING, pinchEnd } } do
			-- Behind the wheel at the key and in front of it at each window's other end: the pinch crosses.
			expect(#rimCrossings(KEY.tip, window[1], window[2]) > 0).toBe(true)
			for _, point in POINTS do
				for _, radius in rimCrossings(point, window[1], window[2]) do
					expect(radius >= RIM_RADIUS).toBe(true)
				end
			end
		end
	end)
end)

describe("Boss 302 start-up hands: the keyed paths", function()
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
	end)
end)
