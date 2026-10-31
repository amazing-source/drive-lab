--!strict
local CarEntryRules = require("../src/shared/Rules/CarEntry")
local SVJ = require("../src/shared/Config/Cars/SVJ")
local StartupArms = require("../src/shared/Rules/StartupArms")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

type Pose = StartupArms.Pose
type Vector = StartupArms.Vector

local STARTUP = SVJ.startup
-- The SVJ's START flap, the one cabin control its start-up moves.
local FLAP = STARTUP.moves[1]
local Config = SVJ.driver.startupPaths
local FLAP_LINE = assert(Config.FLAP, "the SVJ's paths carry its flap")

local function gap(a: Vector, b: Vector): number
	return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
end

-- The angle between two rotations, radians.
local function apart(a: StartupArms.Rotation, b: StartupArms.Rotation): number
	local dot = math.abs(a.w * b.w + a.x * b.x + a.y * b.y + a.z * b.z)
	return 2 * math.acos(math.min(dot, 1))
end

-- A quarter turn about y between keys, the wrist moving along x then up.
local half = math.sqrt(0.5)
local KEYS: { Config.Key } = {
	{ 0.0, 0, 0, 0, 1, 0, 0, 0 },
	{ 0.5, 1, 0, 0, half, 0, half, 0 },
	{ 1.0, 2, 1, 0, 0, 0, 1, 0 },
	{ 2.0, 2, 3, -1, 0, 0, 1, 0 },
}

local function track(gripFrom: number): Config.Track
	return {
		keys = KEYS,
		shapes = { { at = 0, shape = "Rest" }, { at = 0.4, shape = "Point" }, { at = 1.5, shape = "Grip" } },
		gripFrom = gripFrom,
	}
end

describe("Start-up arms: sampling a keyed wrist path", function()
	it("passes through every key, position and rotation", function()
		for _, key in KEYS do
			local pose = StartupArms.sample(KEYS, key[1])
			expect(gap(pose.position, { x = key[2], y = key[3], z = key[4] })).toBeNear(0, 1e-9)
			expect(apart(pose.rotation, { w = key[5], x = key[6], y = key[7], z = key[8] })).toBeNear(0, 1e-6)
		end
	end)

	it("holds the first and last key outside the path", function()
		expect(gap(StartupArms.sample(KEYS, -3).position, { x = 0, y = 0, z = 0 })).toBe(0)
		expect(gap(StartupArms.sample(KEYS, 9).position, { x = 2, y = 3, z = -1 })).toBe(0)
	end)

	it("carries its speed through a key instead of stopping or kinking there", function()
		local h = 1e-4
		local function velocity(t: number): Vector
			local a, b = StartupArms.sample(KEYS, t - h).position, StartupArms.sample(KEYS, t + h).position
			return { x = (b.x - a.x) / (2 * h), y = (b.y - a.y) / (2 * h), z = (b.z - a.z) / (2 * h) }
		end
		local before, after = velocity(1.0 - 2 * h), velocity(1.0 + 2 * h)
		expect(gap(before, after) < 0.01).toBe(true)
		expect(math.sqrt(before.x ^ 2 + before.y ^ 2 + before.z ^ 2) > 0.5).toBe(true)
	end)

	it("turns at an even rate the short way between keys, staying a unit rotation", function()
		local q = StartupArms.sample(KEYS, 0.25).rotation
		expect(q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z).toBeNear(1, 1e-9)
		expect(apart(q, { w = 1, x = 0, y = 0, z = 0 })).toBeNear(math.pi / 4, 1e-6)
		local flipped = StartupArms.slerp(
			{ w = 1, x = 0, y = 0, z = 0 },
			{ w = -half, x = 0, y = -half, z = 0 },
			0.5
		)
		expect(apart(flipped, { w = 1, x = 0, y = 0, z = 0 })).toBeNear(math.pi / 4, 1e-6)
	end)

	it("bends a pose toward a moved target by the given share", function()
		local from: Pose = { position = { x = 1, y = 1, z = 1 }, rotation = { w = 1, x = 0, y = 0, z = 0 } }
		local to: Pose =
			{ position = { x = 2, y = 3, z = 0 }, rotation = { w = half, x = half, y = 0, z = 0 } }
		local untouched = StartupArms.retarget(from, from, to, 0)
		expect(gap(untouched.position, from.position)).toBe(0)
		local landed = StartupArms.retarget(from, from, to, 1)
		expect(gap(landed.position, to.position)).toBeNear(0, 1e-9)
		expect(apart(landed.rotation, to.rotation)).toBeNear(0, 1e-6)
	end)
end)

describe("Start-up arms: which hand shows when", function()
	it("rests while the engine is off and hands over to the grip at the last key", function()
		local resting = StartupArms.hand(track(1.5), nil)
		assert(resting, "a resting hand")
		expect(resting.shape).toBe("Rest")
		expect(resting.toGrip).toBe(0)
		expect(gap(resting.pose.position, { x = 0, y = 0, z = 0 })).toBe(0)
		expect(StartupArms.hand(track(1.5), 2.0)).toBe(nil)
		expect(StartupArms.hand(track(1.5), 50)).toBe(nil)
	end)

	it("swaps the hand's shape at its keyed moments", function()
		expect(StartupArms.shape(track(1.5), 0.39)).toBe("Rest")
		expect(StartupArms.shape(track(1.5), 0.4)).toBe("Point")
		expect(StartupArms.shape(track(1.5), 1.6)).toBe("Grip")
	end)

	it("bends toward the live grip only over the final approach", function()
		local before = StartupArms.hand(track(1.5), 1.4)
		local during = StartupArms.hand(track(1.5), 1.75)
		local almost = StartupArms.hand(track(1.5), 1.999)
		assert(before and during and almost, "hands during the start-up")
		expect(before.toGrip).toBe(0)
		expect(during.toGrip).toBeNear(0.5, 1e-9)
		expect(almost.toGrip > 0.99).toBe(true)
	end)
end)

describe("Start-up arms: turning a point with the wrist", function()
	it("rotates by the pose's rotation, then moves by its position", function()
		local quarter: Pose = {
			position = { x = 1, y = 2, z = 3 },
			rotation = { w = half, x = 0, y = half, z = 0 },
		}
		-- A quarter turn about y takes +x to -z.
		local moved = StartupArms.apply(quarter, { x = 1, y = 0, z = 0 })
		expect(gap(moved, { x = 1, y = 2, z = 2 })).toBeNear(0, 1e-9)
	end)
end)

-- The flap's free edge at a start-up time, turned as Rules/CarEntry opens it.
local function flapEdge(t: number): Vector
	local state: CarEntryRules.State = {
		entry = "Enter",
		entryAt = -100,
		entryDoorOpen = false,
		door = "Closed",
		doorAt = 0,
		engine = "On",
		engineAt = 0,
	}
	local angle = -FLAP.angle * CarEntryRules.controlOpenness(FLAP, state, t)
	local hinge, edge = FLAP_LINE.hinge, FLAP_LINE.edge
	local y, z = edge.y - hinge.y, edge.z - hinge.z
	return {
		x = edge.x,
		y = hinge.y + y * math.cos(angle) - z * math.sin(angle),
		z = hinge.z + y * math.sin(angle) + z * math.cos(angle),
	}
end

local function rightTip(t: number): Vector
	return StartupArms.apply(StartupArms.sample(Config.RIGHT.keys, t), Config.FINGERTIP)
end

describe("Start-up arms: the right hand works the START flap in time", function()
	it("rides the flap's free edge, to the millimetre, while Rules/CarEntry lifts it", function()
		local from = FLAP.at - FLAP.move
		for step = 0, 10 do
			local t = from + FLAP.move * step / 10
			expect(gap(rightTip(t), flapEdge(t)) < 0.002).toBe(true)
		end
	end)

	it("pushes START down to its face at the press, from a few millimetres above it", function()
		local function aboveButton(t: number): number
			local tip, top, normal = rightTip(t), Config.BUTTON.top, Config.BUTTON.normal
			return (tip.x - top.x) * normal.x + (tip.y - top.y) * normal.y + (tip.z - top.z) * normal.z
		end
		expect(math.abs(aboveButton(STARTUP.pressAt)) < 0.001).toBe(true)
		expect(aboveButton(STARTUP.pressAt - 0.16) > Config.BUTTON.depth * 0.8).toBe(true)
		expect(StartupArms.shape(Config.RIGHT, STARTUP.pressAt)).toBe("Point")
	end)
end)

describe("Start-up arms: the SVJ's keyed paths", function()
	it("are keyed in time order with unit rotations, and end on the wheel when it says", function()
		for name, keyed in { RIGHT = Config.RIGHT, LEFT = Config.LEFT } do
			local keys = keyed.keys
			expect(keys[1][1]).toBe(0)
			for index = 2, #keys do
				expect(keys[index][1] > keys[index - 1][1]).toBe(true)
			end
			for _, key in keys do
				expect(key[5] ^ 2 + key[6] ^ 2 + key[7] ^ 2 + key[8] ^ 2).toBeNear(1, 1e-3)
			end
			expect(keys[#keys][1] <= STARTUP.wheelAt + 1e-9).toBe(true)
			expect(keyed.gripFrom < keys[#keys][1]).toBe(true)
			expect(StartupArms.shape(keyed, keys[#keys][1])).toBe("Grip")
			expect(keyed.shapes[1].shape).toBe("Rest")
			expect(#name > 0).toBe(true)
		end
		expect(Config.RIGHT.keys[#Config.RIGHT.keys][1]).toBeNear(STARTUP.wheelAt, 1e-9)
	end)
end)
