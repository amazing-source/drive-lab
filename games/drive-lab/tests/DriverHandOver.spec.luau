--!strict
local DR458 = require("../src/shared/Config/Cars/DR458")
local Rules = require("../src/shared/Rules/CarEntry")
local SVJ = require("../src/shared/Config/Cars/SVJ")
local StartupArms = require("../src/shared/Rules/StartupArms")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

type Pose = StartupArms.Pose
type Vector = StartupArms.Vector

local function gap(a: Vector, b: Vector): number
	return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
end

local function apart(a: StartupArms.Rotation, b: StartupArms.Rotation): number
	local dot = math.abs(a.w * b.w + a.x * b.x + a.y * b.y + a.z * b.z)
	return 2 * math.acos(math.min(dot, 1))
end

local function state(entry: Rules.EntryKind, entryAt: number): Rules.State
	return {
		entry = entry,
		entryAt = entryAt,
		entryDoorOpen = false,
		door = "Closed",
		doorAt = entryAt,
		engine = "Off",
		engineAt = 0,
	}
end

local FROM: Pose = { position = { x = 0, y = 0, z = 0 }, rotation = { w = 1, x = 0, y = 0, z = 0 } }
local half = math.sqrt(0.5)
local TO: Pose = { position = { x = 2, y = -1, z = 4 }, rotation = { w = half, x = 0, y = half, z = 0 } }

describe("Hand-over: easing the drawn hands between two poses", function()
	it("starts at the first pose, ends at the second, and turns half way at half way", function()
		local start, finish = StartupArms.settle(FROM, TO, 0), StartupArms.settle(FROM, TO, 1)
		expect(gap(start.position, FROM.position)).toBeNear(0, 1e-9)
		expect(apart(start.rotation, FROM.rotation)).toBeNear(0, 1e-6)
		expect(gap(finish.position, TO.position)).toBeNear(0, 1e-9)
		expect(apart(finish.rotation, TO.rotation)).toBeNear(0, 1e-6)
		local middle = StartupArms.settle(FROM, TO, 0.5)
		expect(gap(middle.position, { x = 1, y = -0.5, z = 2 })).toBeNear(0, 1e-9)
		expect(apart(middle.rotation, FROM.rotation)).toBeNear(math.pi / 4, 1e-6)
	end)

	it("holds its ends outside 0 to 1", function()
		expect(gap(StartupArms.settle(FROM, TO, -1).position, FROM.position)).toBeNear(0, 1e-9)
		expect(gap(StartupArms.settle(FROM, TO, 2).position, TO.position)).toBeNear(0, 1e-9)
	end)
end)

describe("Hand-over: when the drawn arms show and how far they have eased", function()
	local seconds = 0.6
	local enter = Rules.length(Rules.steps(SVJ, "Enter", false))

	it("runs 0 to 1 after the body sits, and is nil while it gets in", function()
		expect(Rules.handOverShare(SVJ, state("Enter", 0), enter - 0.1, seconds)).toBe(nil)
		expect(Rules.handOverShare(SVJ, state("Enter", 0), enter, seconds)).toBe(0)
		local share = Rules.handOverShare(SVJ, state("Enter", 100), 100 + enter + 0.3, seconds)
		expect(share :: number).toBeNear(0.5, 1e-9)
		expect(Rules.handOverShare(SVJ, state("Enter", 100), 100 + enter + 5, seconds)).toBe(1)
	end)

	it("runs back to 0 as an exit begins, then hands over to the body", function()
		local share = Rules.handOverShare(SVJ, state("Exit", 200), 200.15, seconds)
		expect(share :: number).toBeNear(0.75, 1e-9)
		expect(Rules.handOverShare(SVJ, state("Exit", 200), 200 + seconds + 1e-6, seconds)).toBe(nil)
		expect(Rules.handOverShare(SVJ, state("None", 0), 300, seconds)).toBe(nil)
	end)

	it("is 1 seated and nil getting out for a car without a hand-over, as before", function()
		expect(Rules.handOverShare(SVJ, state("Enter", 0), enter, nil)).toBe(1)
		expect(Rules.handOverShare(SVJ, state("Exit", 200), 200.1, nil)).toBe(nil)
	end)

	it("ignores a hand-over behind a direct door, which has no body clips to hand over from", function()
		local car = table.clone(SVJ) :: any
		car.door = table.clone(SVJ.door) :: any
		car.door.direct = true
		expect(Rules.handOverShare(car, state("Enter", 100), 100.01, seconds)).toBe(1)
	end)
end)

describe("Hand-over: the DR458's drawn hands", function()
	local handOver = assert(DR458.driver.handOver, "the DR458 hands over from its body's arms")
	local paths = DR458.driver.startupPaths

	-- One centimetre, in the keys' metres: the most a drawn hand may move between two frames.
	local STEP_LIMIT = 0.01
	local FRAME = 1 / 60

	for _, side in { "right", "left" } do
		it(`eases the {side} hand onto its first key with no jump above 1 cm a frame`, function()
			local from: Pose = (handOver :: any)[side]
			local key = (paths :: any)[if side == "right" then "RIGHT" else "LEFT"].keys[1]
			local rest: Pose = {
				position = { x = key[2], y = key[3], z = key[4] },
				rotation = { w = key[5], x = key[6], y = key[7], z = key[8] },
			}
			-- The hand keeps its resting turn throughout, so every point of it moves as the wrist does.
			for _, k in { "w", "x", "y", "z" } do
				expect((from.rotation :: any)[k]).toBeNear((rest.rotation :: any)[k], 1e-9)
			end
			expect(gap(StartupArms.settle(from, rest, 0).position, from.position)).toBeNear(0, 1e-9)
			local previous = from.position
			local worst = 0
			local t = FRAME
			while t <= handOver.seconds + FRAME do
				local now = StartupArms.settle(from, rest, t / handOver.seconds).position
				worst = math.max(worst, gap(now, previous))
				previous = now
				t += FRAME
			end
			expect(worst).toBeNear(0, STEP_LIMIT)
			expect(gap(previous, rest.position)).toBeNear(0, 1e-9)
		end)
	end
end)
