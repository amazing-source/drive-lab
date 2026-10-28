--!strict
local Config = require("../src/shared/Config/CarEntry")
local Rules = require("../src/shared/Rules/CarEntry")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local STARTUP = Config.STARTUP

local function state(overrides: { [string]: any }): Rules.State
	local base: { [string]: any } = {
		entry = "None",
		entryAt = 0,
		entryDoorOpen = false,
		door = "Closed",
		doorAt = 0,
		engine = "Off",
		engineAt = 0,
	}
	for key, value in overrides do
		base[key] = value
	end
	return (base :: any) :: Rules.State
end

local function names(steps: { Rules.Step }): string
	local out = {}
	for _, step in steps do
		table.insert(out, step.clip)
	end
	return table.concat(out, ",")
end

local function enterLength(doorOpen: boolean): number
	return Rules.length(Rules.steps("Enter", doorOpen))
end

-- Seated in a car whose sequence ended long ago, engine running and drivable.
local function driving(): Rules.State
	return state({ entry = "Enter", entryAt = 0, engine = "On", engineAt = 100 })
end

describe("Car entry sequences", function()
	it("opens a shut door first and skips that when it already stands open", function()
		expect(names(Rules.steps("Enter", false))).toBe("OutsideOpen,GetIn")
		expect(names(Rules.steps("Enter", true))).toBe("GetIn")
		expect(names(Rules.steps("Exit", false))).toBe("InsideOpen,GetOut,OutsideClose")
		expect(names(Rules.steps("Exit", true))).toBe("GetOut,OutsideClose")
		expect(#Rules.steps("None", false)).toBe(0)
	end)

	it("plays its clips back to back", function()
		local steps = Rules.steps("Enter", false)
		for index = 2, #steps do
			expect(steps[index].start).toBeNear(steps[index - 1].start + steps[index - 1].duration, 1e-9)
		end
		expect(Rules.length(steps)).toBeNear(
			Config.CLIPS.OutsideOpen.duration + Config.CLIPS.GetIn.duration,
			1e-9
		)
	end)

	it("finds the clip playing at a time and holds the last one at the end", function()
		local steps = Rules.steps("Enter", false)
		local step, into = Rules.stepAt(steps, Config.CLIPS.OutsideOpen.duration + 0.5)
		expect(step and step.clip).toBe("GetIn")
		expect(into).toBeNear(0.5, 1e-9)
		local last, held = Rules.stepAt(steps, 1000)
		expect(last and last.clip).toBe("GetIn")
		expect(held).toBeNear(Config.CLIPS.GetIn.duration, 1e-9)
	end)

	it("is entering until the sequence ends, then seated; exiting until the server lets go", function()
		local entering = state({ entry = "Enter", entryAt = 10 })
		expect(Rules.phase(entering, 10)).toBe("Entering")
		expect(Rules.phase(entering, 10 + enterLength(false) - 0.01)).toBe("Entering")
		expect(Rules.phase(entering, 10 + enterLength(false) + 1e-6)).toBe("Seated")
		expect(Rules.phase(state({ entry = "Exit", entryAt = 10 }), 1000)).toBe("Exiting")
		expect(Rules.phase(state({}), 0)).toBe("Outside")
	end)
end)

describe("Car door", function()
	it("opens, stays open while sliding in, and is pulled shut by the end of the entry", function()
		local entering = state({ entry = "Enter", entryAt = 0, door = "Closed", doorAt = 0 })
		local open, getIn = Config.CLIPS.OutsideOpen, Config.CLIPS.GetIn
		expect(Rules.doorOpenness(entering, 0)).toBe(0)
		expect(Rules.doorOpenness(entering, open.duration)).toBe(1)
		expect(Rules.doorOpenness(entering, open.duration + getIn.duration / 2)).toBe(1)
		expect(Rules.doorOpenness(entering, enterLength(false) - 1e-3)).toBeNear(0, 1e-6)
		expect(Rules.doorOpenness(entering, enterLength(false) + 5)).toBe(0)
	end)

	it("follows its own motion outside a sequence", function()
		local opening = state({ door = "OutsideOpen", doorAt = 20 })
		expect(Rules.doorOpenness(opening, 19)).toBe(0)
		expect(Rules.doorIdle(opening, 20.5)).toBe(false)
		local done = 20 + Config.CLIPS.OutsideOpen.duration + 1e-6
		expect(Rules.doorOpenness(opening, done)).toBe(1)
		expect(Rules.doorIdle(opening, done)).toBe(true)
		expect(Rules.doorClosed(opening, done)).toBe(false)
		expect(Rules.doorClosed(state({}), 0)).toBe(true)
	end)

	it("picks the clip that moves the door from where it rests", function()
		expect(Rules.doorClip(state({ door = "Open" }), 0, true)).toBe("InsideClose")
		expect(Rules.doorClip(state({ door = "Closed" }), 0, true)).toBe("InsideOpen")
		expect(Rules.doorClip(state({ door = "Open" }), 0, false)).toBe("OutsideClose")
		expect(Rules.doorClip(state({ door = "Closed" }), 0, false)).toBe("OutsideOpen")
	end)

	it("settles a cut-short sequence at the nearer rest", function()
		local entering = state({ entry = "Enter", entryAt = 0 })
		expect(Rules.nearestRest(entering, 0)).toBe("Closed")
		expect(Rules.nearestRest(entering, Config.CLIPS.OutsideOpen.duration + 0.1)).toBe("Open")
	end)

	it("has curves that start and end where the clips need them", function()
		local ends: { [string]: { number } } = {
			OutsideOpen = { 0, 1 },
			GetIn = { 1, 0 },
			InsideOpen = { 0, 1 },
			InsideClose = { 1, 0 },
			OutsideClose = { 1, 0 },
		}
		for name, expected in ends do
			local clip = (Config.CLIPS :: any)[name] :: Config.Clip
			local curve = clip.door
			assert(curve, `{name} has no door curve`)
			expect(curve.values[1]).toBe(expected[1])
			expect(curve.values[#curve.values]).toBe(expected[2])
			expect(curve.times[#curve.times] <= clip.duration).toBe(true)
			for index = 2, #curve.times do
				expect(curve.times[index] > curve.times[index - 1]).toBe(true)
			end
			for _, value in curve.values do
				expect(value >= 0 and value <= 1).toBe(true)
			end
		end
	end)
end)

describe("Car start-up", function()
	it("runs its moments in order", function()
		expect(STARTUP.flapUpAt < STARTUP.pressAt).toBe(true)
		expect(STARTUP.pressAt < STARTUP.flapDownAt).toBe(true)
		expect(STARTUP.flapDownAt < STARTUP.wheelAt).toBe(true)
		expect(STARTUP.wheelAt <= STARTUP.drivableAt).toBe(true)
		for index = 2, #STARTUP.rpm.times do
			expect(STARTUP.rpm.times[index] > STARTUP.rpm.times[index - 1]).toBe(true)
		end
	end)

	it("reaches, cranks, then runs, and drives only once the hands are back", function()
		local on = state({ entry = "Enter", entryAt = -100, engine = "On", engineAt = 0 })
		expect(Rules.startup(state({}), 5).stage).toBe("Off")
		expect(Rules.startup(on, STARTUP.pressAt - 0.01).stage).toBe("Reaching")
		expect(Rules.startup(on, STARTUP.pressAt + 0.01).stage).toBe("Cranking")
		expect(Rules.startup(on, STARTUP.pressAt + STARTUP.catchAfter + 0.01).stage).toBe("Running")
		expect(Rules.drivable(on, STARTUP.drivableAt - 0.01)).toBe(false)
		expect(Rules.drivable(on, STARTUP.drivableAt)).toBe(true)
	end)

	it("shows no revs before START, the start-up's revs while it runs, then the engine's", function()
		local on = state({ entry = "Enter", entryAt = -100, engine = "On", engineAt = 0 })
		expect(Rules.shownRpm(state({}), 50, 950)).toBe(0)
		expect(Rules.shownRpm(on, STARTUP.pressAt - 0.1, 950)).toBe(0)
		expect(Rules.shownRpm(on, STARTUP.pressAt, 950)).toBe(STARTUP.rpm.values[1])
		local flare = STARTUP.pressAt + 1.3
		expect(Rules.shownRpm(on, flare, 950)).toBeNear(1800, 1e-6)
		local afterDrivable = STARTUP.pressAt + 6.0
		expect(Rules.shownRpm(on, afterDrivable, 950)).toBeNear(1080, 1e-6)
		expect(Rules.shownRpm(on, afterDrivable, 5000)).toBe(5000)
		expect(Rules.shownRpm(on, STARTUP.pressAt + 60, 950)).toBe(950)
	end)
end)

describe("Start-up flap and brake", function()
	it("lifts the flap before the press, holds it, and lets it fall after", function()
		local on = state({ entry = "Enter", entryAt = -100, engine = "On", engineAt = 0 })
		expect(Rules.flapOpenness(state({}), 1)).toBe(0)
		expect(Rules.flapOpenness(on, STARTUP.flapUpAt - STARTUP.flapMove - 0.01)).toBe(0)
		expect(Rules.flapOpenness(on, STARTUP.flapUpAt - STARTUP.flapMove / 2)).toBeNear(0.5, 1e-6)
		expect(Rules.flapOpenness(on, STARTUP.pressAt)).toBe(1)
		expect(Rules.flapOpenness(on, STARTUP.flapDownAt + STARTUP.flapMove / 2)).toBeNear(0.5, 1e-6)
		expect(Rules.flapOpenness(on, STARTUP.flapDownAt + STARTUP.flapMove + 0.01)).toBe(0)
	end)

	it("holds the brake from the key until driving unlocks", function()
		local on = state({ entry = "Enter", entryAt = -100, engine = "On", engineAt = 0 })
		expect(Rules.startupBrake(state({}), 1)).toBe(nil)
		expect(Rules.startupBrake(on, 0.1)).toBe(STARTUP.brake)
		expect(Rules.startupBrake(on, STARTUP.drivableAt - 0.01)).toBe(STARTUP.brake)
		expect(Rules.startupBrake(on, STARTUP.drivableAt + 0.01)).toBe(nil)
	end)
end)

describe("Car entry requests", function()
	it("lets one in from outside only with nothing moving", function()
		expect(Rules.canEnter(state({}), 0)).toBe(true)
		expect(Rules.canEnter(state({ door = "OutsideOpen", doorAt = 0 }), 0.5)).toBe(false)
		expect(Rules.canEnter(state({ entry = "Enter", entryAt = 0 }), 1000)).toBe(false)
	end)

	it("drives only seated, started and shut in", function()
		expect(Rules.drivable(driving(), 1000)).toBe(true)
		expect(Rules.drivable(state({ entry = "Enter", entryAt = 0 }), 1000)).toBe(false)
		expect(
			Rules.drivable(
				state({ entry = "Enter", entryAt = 0, engine = "On", engineAt = 100, door = "Open" }),
				1000
			)
		).toBe(false)
		expect(Rules.drivable(state({ entry = "Enter", entryAt = 999, engine = "On", engineAt = 100 }), 1000)).toBe(
			false
		)
	end)

	it("lets the driver out only stopped and not mid start-up", function()
		expect(Rules.canExit(driving(), 1000, 0)).toBe(true)
		expect(Rules.canExit(driving(), 1000, Config.EXIT_MAX_KMH + 1)).toBe(false)
		expect(
			Rules.canExit(state({ entry = "Enter", entryAt = 0, engine = "On", engineAt = 999.5 }), 1000, 0)
		).toBe(false)
		expect(Rules.canExit(state({ entry = "Enter", entryAt = 999 }), 1000, 0)).toBe(false)
	end)

	it("starts only seated, off and shut in", function()
		local seated = state({ entry = "Enter", entryAt = 0 })
		expect(Rules.canStart(seated, 1000)).toBe(true)
		expect(Rules.canStart(driving(), 1000)).toBe(false)
		expect(Rules.canStart(state({ entry = "Enter", entryAt = 0, door = "Open" }), 1000)).toBe(false)
		expect(Rules.canStart(state({ entry = "Enter", entryAt = 999 }), 1000)).toBe(false)
	end)

	it("moves the door from inside when seated and slow, from outside when nobody is in", function()
		local seated = state({ entry = "Enter", entryAt = 0 })
		expect(Rules.canMoveDoor(seated, 1000, 0, true)).toBe(true)
		expect(Rules.canMoveDoor(seated, 1000, Config.DOOR_MAX_KMH + 1, true)).toBe(false)
		expect(Rules.canMoveDoor(seated, 1000, 0, false)).toBe(false)
		expect(Rules.canMoveDoor(state({}), 0, 0, false)).toBe(true)
		expect(Rules.canMoveDoor(state({}), 0, 0, true)).toBe(false)
	end)

	it("reads only the four actions", function()
		expect(Rules.parseAction("Enter")).toBe("Enter")
		expect(Rules.parseAction("Start")).toBe("Start")
		expect(Rules.parseAction("Fly")).toBe(nil)
		expect(Rules.parseAction(3)).toBe(nil)
		expect(Rules.parseAction(nil)).toBe(nil)
	end)
end)

describe("Door from outside", function()
	it("plays the standing clip of the door the player moved, then finishes", function()
		local moved = state({ door = "OutsideOpen", doorAt = 10.2 })
		local playing = Rules.outsideRequest(moved, 11, 10)
		expect(playing.clip).toBe("OutsideOpen")
		expect(playing.into).toBeNear(0.8, 1e-9)
		expect(playing.finished).toBe(false)
		local done = Rules.outsideRequest(moved, 10.2 + Config.CLIPS.OutsideOpen.duration + 1e-6, 10)
		expect(done.clip).toBe(nil)
		expect(done.finished).toBe(true)
	end)

	it("finishes a request the server never acted on, after the refusal time", function()
		local untouched = state({ door = "Closed", doorAt = 0 })
		expect(Rules.outsideRequest(untouched, 10 + Config.REFUSED_SECONDS - 0.01, 10).finished).toBe(false)
		expect(Rules.outsideRequest(untouched, 10 + Config.REFUSED_SECONDS + 0.01, 10).finished).toBe(true)
	end)

	it("ignores a motion that started before the request or from inside", function()
		local earlier = state({ door = "OutsideClose", doorAt = 10 - Config.REQUEST_SLACK - 0.5 })
		expect(Rules.outsideRequest(earlier, 10.1, 10).clip).toBe(nil)
		local inside = state({ door = "InsideOpen", doorAt = 10.1 })
		expect(Rules.outsideRequest(inside, 10.2, 10).clip).toBe(nil)
		expect(Rules.outsideRequest(inside, 10 + Config.REFUSED_SECONDS + 0.01, 10).finished).toBe(true)
	end)
end)

describe("Driver scale", function()
	it("eases from one size to the other over the configured time", function()
		expect(Rules.scale(1, 0.8, 0)).toBe(1)
		expect(Rules.scale(1, 0.8, Config.SCALE_SECONDS / 2)).toBeNear(0.9, 1e-9)
		expect(Rules.scale(1, 0.8, Config.SCALE_SECONDS)).toBeNear(0.8, 1e-9)
		expect(Rules.scale(1, 0.8, Config.SCALE_SECONDS * 3)).toBeNear(0.8, 1e-9)
		local previous = 1
		for step = 1, 20 do
			local value = Rules.scale(1, 0.8, Config.SCALE_SECONDS * step / 20)
			expect(value <= previous).toBe(true)
			previous = value
		end
	end)
end)
