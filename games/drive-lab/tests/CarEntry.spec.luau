--!strict
local Config = require("../src/shared/Config/CarEntry")
local Hinge = require("../src/shared/Rules/Hinge")
local Rules = require("../src/shared/Rules/CarEntry")
local SVJ = require("../src/shared/Config/Cars/SVJ")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local STARTUP = SVJ.startup

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
	return Rules.length(Rules.steps(SVJ, "Enter", doorOpen))
end

-- Seated in a car whose sequence ended long ago, engine running and drivable.
local function driving(): Rules.State
	return state({ entry = "Enter", entryAt = 0, engine = "On", engineAt = 100 })
end

describe("Car entry sequences", function()
	it("opens a shut door first and skips that when it already stands open", function()
		expect(names(Rules.steps(SVJ, "Enter", false))).toBe("OutsideOpen,GetIn")
		expect(names(Rules.steps(SVJ, "Enter", true))).toBe("GetIn")
		expect(names(Rules.steps(SVJ, "Exit", false))).toBe("InsideOpen,GetOut,OutsideClose")
		expect(names(Rules.steps(SVJ, "Exit", true))).toBe("GetOut,OutsideClose")
		expect(#Rules.steps(SVJ, "None", false)).toBe(0)
	end)

	it("plays its clips back to back", function()
		local steps = Rules.steps(SVJ, "Enter", false)
		for index = 2, #steps do
			expect(steps[index].start).toBeNear(steps[index - 1].start + steps[index - 1].duration, 1e-9)
		end
		expect(Rules.length(steps)).toBeNear(
			SVJ.door.clips.OutsideOpen.duration + SVJ.door.clips.GetIn.duration,
			1e-9
		)
	end)

	it("finds the clip playing at a time and holds the last one at the end", function()
		local steps = Rules.steps(SVJ, "Enter", false)
		local step, into = Rules.stepAt(steps, SVJ.door.clips.OutsideOpen.duration + 0.5)
		expect(step and step.clip).toBe("GetIn")
		expect(into).toBeNear(0.5, 1e-9)
		local last, held = Rules.stepAt(steps, 1000)
		expect(last and last.clip).toBe("GetIn")
		expect(held).toBeNear(SVJ.door.clips.GetIn.duration, 1e-9)
	end)

	it("is entering until the sequence ends, then seated; exiting until the server lets go", function()
		local entering = state({ entry = "Enter", entryAt = 10 })
		expect(Rules.phase(SVJ, entering, 10)).toBe("Entering")
		expect(Rules.phase(SVJ, entering, 10 + enterLength(false) - 0.01)).toBe("Entering")
		expect(Rules.phase(SVJ, entering, 10 + enterLength(false) + 1e-6)).toBe("Seated")
		expect(Rules.phase(SVJ, state({ entry = "Exit", entryAt = 10 }), 1000)).toBe("Exiting")
		expect(Rules.phase(SVJ, state({}), 0)).toBe("Outside")
	end)
end)

describe("Car door", function()
	it("opens, stays open while sliding in, and is pulled shut by the end of the entry", function()
		local entering = state({ entry = "Enter", entryAt = 0, door = "Closed", doorAt = 0 })
		local open, getIn = SVJ.door.clips.OutsideOpen, SVJ.door.clips.GetIn
		expect(Rules.doorOpenness(SVJ, entering, 0)).toBe(0)
		expect(Rules.doorOpenness(SVJ, entering, open.duration)).toBe(1)
		expect(Rules.doorOpenness(SVJ, entering, open.duration + getIn.duration / 2)).toBe(1)
		expect(Rules.doorOpenness(SVJ, entering, enterLength(false) - 1e-3)).toBeNear(0, 1e-6)
		expect(Rules.doorOpenness(SVJ, entering, enterLength(false) + 5)).toBe(0)
	end)

	it("follows its own motion outside a sequence", function()
		local opening = state({ door = "OutsideOpen", doorAt = 20 })
		expect(Rules.doorOpenness(SVJ, opening, 19)).toBe(0)
		expect(Rules.doorIdle(SVJ, opening, 20.5)).toBe(false)
		local done = 20 + SVJ.door.clips.OutsideOpen.duration + 1e-6
		expect(Rules.doorOpenness(SVJ, opening, done)).toBe(1)
		expect(Rules.doorIdle(SVJ, opening, done)).toBe(true)
		expect(Rules.doorClosed(SVJ, opening, done)).toBe(false)
		expect(Rules.doorClosed(SVJ, state({}), 0)).toBe(true)
	end)

	it("picks the clip that moves the door from where it rests", function()
		expect(Rules.doorClip(SVJ, state({ door = "Open" }), 0, true)).toBe("InsideClose")
		expect(Rules.doorClip(SVJ, state({ door = "Closed" }), 0, true)).toBe("InsideOpen")
		expect(Rules.doorClip(SVJ, state({ door = "Open" }), 0, false)).toBe("OutsideClose")
		expect(Rules.doorClip(SVJ, state({ door = "Closed" }), 0, false)).toBe("OutsideOpen")
	end)

	it("settles a cut-short sequence at the nearer rest", function()
		local entering = state({ entry = "Enter", entryAt = 0 })
		expect(Rules.nearestRest(SVJ, entering, 0)).toBe("Closed")
		expect(Rules.nearestRest(SVJ, entering, SVJ.door.clips.OutsideOpen.duration + 0.1)).toBe("Open")
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
			local clip = (SVJ.door.clips :: any)[name] :: Config.Clip
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
		expect(Rules.startup(SVJ, state({}), 5).stage).toBe("Off")
		expect(Rules.startup(SVJ, on, STARTUP.pressAt - 0.01).stage).toBe("Reaching")
		expect(Rules.startup(SVJ, on, STARTUP.pressAt + 0.01).stage).toBe("Cranking")
		expect(Rules.startup(SVJ, on, STARTUP.pressAt + STARTUP.catchAfter + 0.01).stage).toBe("Running")
		expect(Rules.drivable(SVJ, on, STARTUP.drivableAt - 0.01)).toBe(false)
		expect(Rules.drivable(SVJ, on, STARTUP.drivableAt)).toBe(true)
	end)

	it("shows no revs before START, the start-up's revs while it runs, then the engine's", function()
		local on = state({ entry = "Enter", entryAt = -100, engine = "On", engineAt = 0 })
		expect(Rules.shownRpm(SVJ, state({}), 50, 950)).toBe(0)
		expect(Rules.shownRpm(SVJ, on, STARTUP.pressAt - 0.1, 950)).toBe(0)
		expect(Rules.shownRpm(SVJ, on, STARTUP.pressAt, 950)).toBe(STARTUP.rpm.values[1])
		local flare = STARTUP.pressAt + 1.3
		expect(Rules.shownRpm(SVJ, on, flare, 950)).toBeNear(1800, 1e-6)
		local afterDrivable = STARTUP.pressAt + 6.0
		expect(Rules.shownRpm(SVJ, on, afterDrivable, 950)).toBeNear(1080, 1e-6)
		expect(Rules.shownRpm(SVJ, on, afterDrivable, 5000)).toBe(5000)
		expect(Rules.shownRpm(SVJ, on, STARTUP.pressAt + 60, 950)).toBe(950)
	end)
end)

describe("Start-up flap and brake", function()
	it("lifts the flap before the press, holds it, and lets it fall after", function()
		local on = state({ entry = "Enter", entryAt = -100, engine = "On", engineAt = 0 })
		expect(Rules.flapOpenness(SVJ, state({}), 1)).toBe(0)
		expect(Rules.flapOpenness(SVJ, on, STARTUP.flapUpAt - STARTUP.flapMove - 0.01)).toBe(0)
		expect(Rules.flapOpenness(SVJ, on, STARTUP.flapUpAt - STARTUP.flapMove / 2)).toBeNear(0.5, 1e-6)
		expect(Rules.flapOpenness(SVJ, on, STARTUP.pressAt)).toBe(1)
		expect(Rules.flapOpenness(SVJ, on, STARTUP.flapDownAt + STARTUP.flapMove / 2)).toBeNear(0.5, 1e-6)
		expect(Rules.flapOpenness(SVJ, on, STARTUP.flapDownAt + STARTUP.flapMove + 0.01)).toBe(0)
	end)

	it("holds the brake from the key until driving unlocks", function()
		local on = state({ entry = "Enter", entryAt = -100, engine = "On", engineAt = 0 })
		expect(Rules.startupBrake(SVJ, state({}), 1)).toBe(nil)
		expect(Rules.startupBrake(SVJ, on, 0.1)).toBe(STARTUP.brake)
		expect(Rules.startupBrake(SVJ, on, STARTUP.drivableAt - 0.01)).toBe(STARTUP.brake)
		expect(Rules.startupBrake(SVJ, on, STARTUP.drivableAt + 0.01)).toBe(nil)
	end)
end)

describe("Car entry requests", function()
	it("lets one in from outside only with nothing moving", function()
		expect(Rules.canEnter(SVJ, state({}), 0)).toBe(true)
		expect(Rules.canEnter(SVJ, state({ door = "OutsideOpen", doorAt = 0 }), 0.5)).toBe(false)
		expect(Rules.canEnter(SVJ, state({ entry = "Enter", entryAt = 0 }), 1000)).toBe(false)
	end)

	it("drives only seated, started and shut in", function()
		expect(Rules.drivable(SVJ, driving(), 1000)).toBe(true)
		expect(Rules.drivable(SVJ, state({ entry = "Enter", entryAt = 0 }), 1000)).toBe(false)
		expect(
			Rules.drivable(
				SVJ,
				state({ entry = "Enter", entryAt = 0, engine = "On", engineAt = 100, door = "Open" }),
				1000
			)
		).toBe(false)
		expect(
			Rules.drivable(
				SVJ,
				state({ entry = "Enter", entryAt = 999, engine = "On", engineAt = 100 }),
				1000
			)
		).toBe(false)
	end)

	it("lets the driver out only stopped and not mid start-up", function()
		expect(Rules.canExit(SVJ, driving(), 1000, 0)).toBe(true)
		expect(Rules.canExit(SVJ, driving(), 1000, Config.EXIT_MAX_KMH + 1)).toBe(false)
		expect(
			Rules.canExit(
				SVJ,
				state({ entry = "Enter", entryAt = 0, engine = "On", engineAt = 999.5 }),
				1000,
				0
			)
		).toBe(false)
		expect(Rules.canExit(SVJ, state({ entry = "Enter", entryAt = 999 }), 1000, 0)).toBe(false)
	end)

	it("starts only seated, off and shut in", function()
		local seated = state({ entry = "Enter", entryAt = 0 })
		expect(Rules.canStart(SVJ, seated, 1000)).toBe(true)
		expect(Rules.canStart(SVJ, driving(), 1000)).toBe(false)
		expect(Rules.canStart(SVJ, state({ entry = "Enter", entryAt = 0, door = "Open" }), 1000)).toBe(false)
		expect(Rules.canStart(SVJ, state({ entry = "Enter", entryAt = 999 }), 1000)).toBe(false)
	end)

	it("moves the door from inside when seated and slow, from outside when nobody is in", function()
		local seated = state({ entry = "Enter", entryAt = 0 })
		expect(Rules.canMoveDoor(SVJ, seated, 1000, 0, true)).toBe(true)
		expect(Rules.canMoveDoor(SVJ, seated, 1000, Config.DOOR_MAX_KMH + 1, true)).toBe(false)
		expect(Rules.canMoveDoor(SVJ, seated, 1000, 0, false)).toBe(false)
		expect(Rules.canMoveDoor(SVJ, state({}), 0, 0, false)).toBe(true)
		expect(Rules.canMoveDoor(SVJ, state({}), 0, 0, true)).toBe(false)
	end)

	it("reads only the five actions", function()
		expect(Rules.parseAction("Enter")).toBe("Enter")
		expect(Rules.parseAction("Start")).toBe("Start")
		expect(Rules.parseAction("Cancel")).toBe("Cancel")
		expect(Rules.parseAction("Fly")).toBe(nil)
		expect(Rules.parseAction(3)).toBe(nil)
		expect(Rules.parseAction(nil)).toBe(nil)
	end)
end)

describe("Door from outside", function()
	it("plays the standing clip of the door the player moved, then finishes", function()
		local moved = state({ door = "OutsideOpen", doorAt = 10.2 })
		local playing = Rules.outsideRequest(SVJ, moved, 11, 10)
		expect(playing.clip).toBe("OutsideOpen")
		expect(playing.into).toBeNear(0.8, 1e-9)
		expect(playing.finished).toBe(false)
		local done = Rules.outsideRequest(SVJ, moved, 10.2 + SVJ.door.clips.OutsideOpen.duration + 1e-6, 10)
		expect(done.clip).toBe(nil)
		expect(done.finished).toBe(true)
	end)

	it("holds the clip's first frame until a start the server set ahead", function()
		local ahead = state({ door = "OutsideOpen", doorAt = 10.4 })
		local waiting = Rules.outsideRequest(SVJ, ahead, 10.1, 10)
		expect(waiting.clip).toBe("OutsideOpen")
		expect(waiting.into).toBe(0)
		expect(waiting.finished).toBe(false)
		expect(Rules.outsideRequest(SVJ, ahead, 10.5, 10).into).toBeNear(0.1, 1e-9)
	end)

	it("finishes a request the server never acted on, after the refusal time", function()
		local untouched = state({ door = "Closed", doorAt = 0 })
		expect(Rules.outsideRequest(SVJ, untouched, 10 + Config.REFUSED_SECONDS - 0.01, 10).finished).toBe(
			false
		)
		expect(Rules.outsideRequest(SVJ, untouched, 10 + Config.REFUSED_SECONDS + 0.01, 10).finished).toBe(
			true
		)
	end)

	it("ignores a motion that started before the request or from inside", function()
		local earlier = state({ door = "OutsideClose", doorAt = 10 - Config.REQUEST_SLACK - 0.5 })
		expect(Rules.outsideRequest(SVJ, earlier, 10.1, 10).clip).toBe(nil)
		local inside = state({ door = "InsideOpen", doorAt = 10.1 })
		expect(Rules.outsideRequest(SVJ, inside, 10.2, 10).clip).toBe(nil)
		expect(Rules.outsideRequest(SVJ, inside, 10 + Config.REFUSED_SECONDS + 0.01, 10).finished).toBe(true)
	end)
end)

describe("Getting out", function()
	it("ends in OutsideClose's stance clear of the car, before its walk back in to the mark", function()
		local close, finish = SVJ.door.clips.OutsideClose, SVJ.door.exitEnd.at
		expect(finish < close.duration).toBe(true)
		for _, doorOpen in { false, true } do
			local steps = Rules.steps(SVJ, "Exit", doorOpen)
			local last = steps[#steps]
			expect(last.clip).toBe("OutsideClose")
			expect(last.duration).toBeNear(finish, 1e-9)
			expect(Rules.length(steps)).toBeNear(last.start + finish, 1e-9)
			local held, into = Rules.stepAt(steps, 1000)
			expect(held and held.clip).toBe("OutsideClose")
			expect(into).toBeNear(finish, 1e-9)
		end
		expect(Rules.length(Rules.steps(SVJ, "Exit", false))).toBeNear(
			SVJ.door.clips.InsideOpen.duration + SVJ.door.clips.GetOut.duration + finish,
			1e-9
		)
	end)

	it("has shut the door before it ends, and stands further out than the mark", function()
		local curve = SVJ.door.clips.OutsideClose.door
		assert(curve, "OutsideClose has no door curve")
		expect(curve.times[#curve.times] <= SVJ.door.exitEnd.at).toBe(true)
		local exiting = state({ entry = "Exit", entryAt = 0 })
		expect(Rules.doorOpenness(SVJ, exiting, Rules.length(Rules.steps(SVJ, "Exit", false)) - 1e-3)).toBe(0)
		expect(SVJ.door.exitEnd.right < SVJ.door.mark.right).toBe(true)
	end)

	it("needs the exit key held, so a tap stays a gear change", function()
		expect(Rules.exitHeld(0.2)).toBe(false)
		expect(Rules.exitHeld(0.34)).toBe(false)
		expect(Rules.exitHeld(0.35)).toBe(true)
		expect(Rules.exitHeld(2)).toBe(true)
	end)
end)

local FRAME = 1 / 60
local INSIDE_CLIPS: { Config.ClipName } = { "InsideOpen", "InsideClose" }
-- Config/CarDoor.LEAD: the door's sounds play on its openness this far ahead. That module needs
-- Roblox types, so the value is copied.
local SOUND_LEAD = 0.1

-- Seated long before time 0 with the engine running, the door on its own motion from `doorAt`; an
-- inside clip starts from the rest it ends opposite to.
local function seatedWithDoor(door: Config.DoorMotion, doorAt: number): Rules.State
	return state({
		entry = "Enter",
		entryAt = -100,
		engine = "On",
		engineAt = -50,
		door = door,
		doorAt = doorAt,
	})
end

-- Services/CarEntry's exit: the state it writes once it has allowed one (copied, as that module
-- needs Roblox).
local function exitWrite(before: Rules.State, at: number, oneWay: number): Rules.State
	local startAt = Rules.entryStart(at, nil, oneWay)
	return {
		entry = "Exit",
		entryAt = startAt,
		entryDoorOpen = Rules.doorOpenness(SVJ, before, at) >= 0.5,
		door = "Closed",
		doorAt = startAt,
		engine = "Off",
		engineAt = at,
	}
end

-- Frames of a client holding the exit key from `pressedAt`, its state `stateAt(at)`; the times it
-- asked the server to get out.
local function holdTimeline(stateAt: (number) -> Rules.State, pressedAt: number, untilAt: number): { number }
	local asks: { number } = {}
	local asked = false
	for frame = 0, math.floor((untilAt - pressedAt) / FRAME) do
		local at = pressedAt + frame * FRAME
		local ask
		ask, asked = Rules.heldExit(SVJ, stateAt(at), at, at - pressedAt, asked)
		if ask then
			table.insert(asks, at)
		end
	end
	return asks
end

describe("Getting out while the door moves", function()
	it("is refused from the door's request until its clip ends, then allowed", function()
		for _, clip in INSIDE_CLIPS do
			local doorAt, duration = 1000, SVJ.door.clips[clip].duration
			-- The server starts a clip from inside ahead of its request (Rules.entryStart).
			for frame = -30, math.floor(duration / FRAME) - 1 do
				local at = doorAt + frame * FRAME
				if Rules.canExit(SVJ, seatedWithDoor(clip, doorAt), at, 0) then
					error(
						`exit allowed {string.format("%.3f", at - doorAt)} s into {clip}, the door still moving`
					)
				end
			end
			expect(Rules.canExit(SVJ, seatedWithDoor(clip, doorAt), doorAt + duration + 1e-6, 0)).toBe(true)
		end
	end)

	it("starts every exit it allows from the door where it stood, with no shut sound", function()
		for _, clip in INSIDE_CLIPS do
			local doorAt, duration = 1000, SVJ.door.clips[clip].duration
			local allowed = 0
			for frame = -30, math.floor((duration + 0.5) / FRAME) do
				local at = doorAt + frame * FRAME
				local before = seatedWithDoor(clip, doorAt)
				if Rules.canExit(SVJ, before, at, 0) then
					allowed += 1
					local after = exitWrite(before, at, 0.2)
					local was, now =
						Rules.doorOpenness(SVJ, before, at), Rules.doorOpenness(SVJ, after, at + FRAME)
					if math.abs(now - was) > 0.05 then
						error(
							`{clip} exit at {string.format("%.3f", at - doorAt)} s: door {was} -> {now} in one frame`
						)
					end
					local sound = Hinge.sound(
						Rules.doorOpenness(SVJ, before, at + SOUND_LEAD),
						Rules.doorOpenness(SVJ, after, at + FRAME + SOUND_LEAD)
					)
					expect(sound).toBe(nil)
				end
			end
			-- Every frame from the clip's end on: the check above is never vacuous.
			expect(allowed > 0).toBe(true)
		end
	end)

	it("waits for the door to stop, then asks once while the key is still held", function()
		for _, clip in INSIDE_CLIPS do
			local rest: Config.DoorMotion = if clip == "InsideOpen" then "Closed" else "Open"
			-- F at 10; the door's state reaches the client at 10.05 for a start at 10.2; E from 10.1.
			local doorAt = 10.2
			local asks = holdTimeline(function(at: number): Rules.State
				return if at < 10.05 then seatedWithDoor(rest, 0) else seatedWithDoor(clip, doorAt)
			end, 10.1, 15)
			expect(#asks).toBe(1)
			local stopped = doorAt + SVJ.door.clips[clip].duration
			-- On the first frame with the door at rest (a frame's float rounding either side).
			expect(asks[1] >= stopped - 1e-9).toBe(true)
			expect(asks[1] - stopped <= FRAME + 1e-9).toBe(true)
			expect(Rules.canExit(SVJ, seatedWithDoor(clip, doorAt), asks[1], 0)).toBe(true)
		end
	end)

	it("asks again once the door stops when the door's request reached the server first", function()
		-- Held from 0 with the door at rest: it asks at the hold time. The server had the door's
		-- request already and refused the exit; the door's state reaches the client at 0.4.
		local doorAt = 0.45
		local asks = holdTimeline(function(at: number): Rules.State
			return if at < 0.4 then seatedWithDoor("Closed", 0) else seatedWithDoor("InsideOpen", doorAt)
		end, 0, 4)
		expect(#asks).toBe(2)
		expect(asks[1]).toBeNear(Config.EXIT_HOLD_SECONDS, FRAME)
		expect(asks[2] >= doorAt + SVJ.door.clips.InsideOpen.duration).toBe(true)
	end)

	it(
		"asks on the hold time with the door at rest, never on a tap, and never while getting in or out",
		function()
			local resting = seatedWithDoor("Closed", 0)
			expect(holdTimeline(function(): Rules.State
				return resting
			end, 1000, 1000 + Config.EXIT_HOLD_SECONDS - 2 * FRAME)[1]).toBe(nil)
			local asks = holdTimeline(function(): Rules.State
				return resting
			end, 1000, 1002)
			expect(#asks).toBe(1)
			expect(asks[1] - 1000).toBeNear(Config.EXIT_HOLD_SECONDS, FRAME)
			for _, moving in
				{ state({ entry = "Enter", entryAt = 999 }), state({ entry = "Exit", entryAt = 999 }) }
			do
				local ask, asked = Rules.heldExit(SVJ, moving, 1000, 2, false)
				expect(ask).toBe(false)
				expect(asked).toBe(true)
			end
		end
	)
end)

describe("Walking to the mark", function()
	it("places, walks straight in, or goes round to the front of the mark first", function()
		local approach = Config.APPROACH
		local slope = math.tan(approach.lineUpAngle)
		expect(Rules.approachPlan(0, approach.arrived * 0.5, math.pi)).toBe("Settle")
		expect(Rules.approachPlan(0, 3, math.pi)).toBe("Straight")
		expect(Rules.approachPlan(3 * slope * 0.9, 3, 0)).toBe("Straight")
		expect(Rules.approachPlan(3 * slope * 1.1, 3, 0)).toBe("LineUp")
		expect(Rules.approachPlan(-3 * slope * 1.1, 3, 0)).toBe("LineUp")
		expect(Rules.approachPlan(0, approach.lineUp * 0.5, 0)).toBe("Straight")
		expect(Rules.approachPlan(0, approach.lineUp * 0.5, math.rad(90))).toBe("LineUp")
		expect(Rules.approachPlan(4, 0.2, 0)).toBe("LineUp")
		expect(Rules.approachPlan(0.5, -0.4, 0)).toBe("LineUp")
	end)

	it("places the body on the mark at walking and turning pace, never longer than the cap", function()
		local approach = Config.APPROACH
		expect(Rules.settleSeconds(0, 0)).toBe(0)
		expect(Rules.settleSeconds(0.1, 0)).toBeNear(0.1 / approach.settleSpeed, 1e-9)
		expect(Rules.settleSeconds(0, math.rad(20))).toBeNear(math.rad(20) / approach.turnSpeed, 1e-9)
		expect(Rules.settleSeconds(0, -math.rad(20))).toBeNear(math.rad(20) / approach.turnSpeed, 1e-9)
		expect(Rules.settleSeconds(approach.reach, math.pi)).toBe(approach.settleSeconds)
		expect(approach.settleSeconds <= 0.2).toBe(true)
	end)

	it("stops the walk in short of the mark by a frame of sprinting, within the placing's reach", function()
		local approach = Config.APPROACH
		-- Halted, the body can still cover one frame: sprinting, at 30 frames a second. That is
		-- Config/Movement's SPRINT_SPEED, which Lune cannot load (it names Enum values).
		local sprintSpeed = 26
		expect(approach.short > sprintSpeed / 30).toBe(true)
		expect(approach.short + approach.arrived < approach.reach).toBe(true)
		expect(approach.short < approach.lineUp).toBe(true)
	end)

	it("eases the placing from its start to the mark", function()
		expect(Rules.settleShare(0, 0.2)).toBe(0)
		expect(Rules.settleShare(0.05, 0.2)).toBeNear(0.15625, 1e-9)
		expect(Rules.settleShare(0.1, 0.2)).toBeNear(0.5, 1e-9)
		expect(Rules.settleShare(0.2, 0.2)).toBe(1)
		expect(Rules.settleShare(5, 0.2)).toBe(1)
		expect(Rules.settleShare(0, 0)).toBe(1)
		local previous = 0
		for step = 1, 20 do
			local value = Rules.settleShare(0.2 * step / 20, 0.2)
			expect(value >= previous).toBe(true)
			previous = value
		end
	end)

	it("starts an entry when the client asked, never in the past nor too far ahead", function()
		expect(Rules.entryStart(10, 10.1, 0)).toBeNear(10.1, 1e-9)
		expect(Rules.entryStart(10, 9, 0)).toBe(10)
		expect(Rules.entryStart(10, 50, 0)).toBeNear(10 + Config.ENTRY_LEAD, 1e-9)
		expect(Rules.entryStart(10, 0 / 0, 0)).toBe(10)
		expect(Rules.entryStart(10, math.huge, 0)).toBe(10)
		expect(Rules.entryStart(10, "soon", 0)).toBe(10)
		expect(Rules.entryStart(10, nil, 0)).toBe(10)
		expect(Config.ENTRY_LEAD >= Config.APPROACH.settleSeconds).toBe(true)
	end)

	it("starts no sooner than the state can reach the client that asked", function()
		expect(Rules.entryStart(10, 9, 0.2)).toBeNear(10.2, 1e-9)
		expect(Rules.entryStart(10, 10.1, 0.2)).toBeNear(10.2, 1e-9)
		expect(Rules.entryStart(10, 10.35, 0.2)).toBeNear(10.35, 1e-9)
		expect(Rules.entryStart(10, 50, 0.2)).toBeNear(10.2 + Config.ENTRY_LEAD, 1e-9)
		expect(Rules.entryStart(10, nil, 0.2)).toBeNear(10.2, 1e-9)
		-- A delay out of bounds or unusable is bounded, never trusted as given.
		expect(Rules.entryStart(10, 10.1, 30)).toBeNear(10 + Config.MAX_ONE_WAY, 1e-9)
		expect(Rules.entryStart(10, 10.1, -1)).toBeNear(10.1, 1e-9)
		expect(Rules.entryStart(10, 10.1, 0 / 0)).toBeNear(10.1, 1e-9)
		expect(Rules.entryStart(10, 10.1, "slow")).toBeNear(10.1, 1e-9)
	end)
end)

-- A second car: its clips and door curves run twice as fast, it gets out at its own stance, and
-- its start-up presses START and unlocks driving later than the SVJ's.
local function otherCar(): Rules.Car
	local function copy(value: any): any
		if type(value) ~= "table" then
			return value
		end
		local out = {}
		for key, child in value do
			out[key] = copy(child)
		end
		return out
	end
	local car = copy({ door = SVJ.door, startup = SVJ.startup })
	for _, clip in car.door.clips do
		clip.duration /= 2
		if clip.door then
			for index, time in clip.door.times do
				clip.door.times[index] = time / 2
			end
		end
	end
	car.door.exitEnd.at /= 2
	car.startup.pressAt += 0.5
	car.startup.drivableAt += 1
	return car
end

describe("Car entry, per car", function()
	local other = otherCar()

	it("times each sequence by the car's own clips", function()
		local svj, fast = enterLength(false), Rules.length(Rules.steps(other, "Enter", false))
		expect(fast).toBeNear(svj / 2, 1e-9)
		local entering = state({ entry = "Enter", entryAt = 0 })
		expect(Rules.phase(SVJ, entering, svj * 0.75)).toBe("Entering")
		expect(Rules.phase(other, entering, svj * 0.75)).toBe("Seated")
	end)

	it("moves the door on the car's own curve", function()
		local opening = state({ door = "OutsideOpen", doorAt = 0 })
		for _, t in { 1.0, 1.5, 2.0, 2.5 } do
			expect(Rules.doorOpenness(other, opening, t / 2)).toBeNear(
				Rules.doorOpenness(SVJ, opening, t),
				1e-9
			)
		end
	end)

	it("ends getting out at the car's own stance", function()
		local last = Rules.steps(other, "Exit", true)[2]
		expect(last.clip).toBe("OutsideClose")
		expect(last.duration).toBeNear(SVJ.door.exitEnd.at / 2, 1e-9)
	end)

	it("cranks and unlocks driving on the car's own start-up", function()
		local on = state({ entry = "Enter", entryAt = -100, engine = "On", engineAt = 0 })
		expect(Rules.startup(SVJ, on, STARTUP.pressAt + 0.1).stage).toBe("Cranking")
		expect(Rules.startup(other, on, STARTUP.pressAt + 0.1).stage).toBe("Reaching")
		expect(Rules.drivable(SVJ, on, STARTUP.drivableAt)).toBe(true)
		expect(Rules.drivable(other, on, STARTUP.drivableAt)).toBe(false)
		expect(Rules.drivable(other, on, STARTUP.drivableAt + 1)).toBe(true)
	end)
end)
