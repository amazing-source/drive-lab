--!strict
local Config = require("../src/shared/Config/DriverGestures")
local HandGestures = require("../src/shared/Rules/HandGestures")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local DT = 1 / 60
local HOLD = 0.12

local function key(t: number, x: number): { number }
	return { t, x, 0, 0, 1, 0, 0, 0 }
end

local function track(finish: number, turn: Config.Turn?): Config.Track
	return {
		keys = { key(0, 0), key(finish / 2, 0.05), key(finish, 0.1) },
		shapes = { { at = 0, shape = "Grip" }, { at = finish - 0.02, shape = "Pressed" } },
		turn = turn,
		tip = { x = 0, y = 0, z = 0 },
		target = { x = 0, y = 0, z = 0 },
	}
end

local BUTTON: Config.Gesture =
	{ control = "PIT_LIMITER", side = -1, frame = "Wheel", latch = nil, tracks = { Press = track(0.2) } }
local OTHER: Config.Gesture =
	{ control = "HIGH_BEAM", side = -1, frame = "Wheel", latch = nil, tracks = { Press = track(0.1) } }
local KNOB_TURN: Config.Turn = { control = "Knob", start = 0.1, finish = 0.2 }
local KNOB: Config.Gesture = {
	control = "DRIVING_MODE",
	side = 1,
	frame = "Wheel",
	latch = "Mode",
	tracks = { ["1"] = track(0.25, KNOB_TURN), ["2"] = track(0.25, KNOB_TURN), OFF = track(0.25, KNOB_TURN) },
}
local ORDER = { "1", "2", "OFF" }

type Rig = { hand: HandGestures.Hand, inputs: HandGestures.Inputs, down: { [string]: boolean }, now: number }

local function rig(shown: { [string]: string }?): Rig
	local down: { [string]: boolean } = {}
	return {
		hand = HandGestures.newHand(),
		down = down,
		now = 0,
		inputs = {
			held = function(control: string): boolean
				return down[control] == true
			end,
			shown = shown or {},
			after = function(gesture: Config.Gesture, from: string): string
				return HandGestures.after(gesture, ORDER, from)
			end,
		},
	}
end

local function step(r: Rig, seconds: number)
	local frames = math.max(1, math.round(seconds / DT))
	for _ = 1, frames do
		r.now += DT
		HandGestures.step(r.hand, r.inputs, HOLD, r.now, DT)
	end
end

local function progress(r: Rig): number
	local playing = r.hand.playing
	return if playing then playing.progress else 0
end

describe("Hand gestures: when the hand leaves the grip and comes back", function()
	it("plays a tap all the way to the held pose, holds it HOLD_MIN, and goes back the same way", function()
		local r = rig()
		HandGestures.press(r.hand, BUTTON, r.now)
		local reachedAt, backAt = nil, nil
		for _ = 1, 120 do
			step(r, DT)
			local playing = r.hand.playing
			if playing and playing.progress >= playing.finish and reachedAt == nil then
				reachedAt = r.now
			end
			if reachedAt and r.hand.playing == nil and backAt == nil then
				backAt = r.now
			end
		end
		assert(reachedAt and backAt, "the tap reached its pose and came back")
		-- Started in the frame the press was seen: 0.2 s of keys, 0.12 s held, 0.2 s back.
		expect(math.abs(reachedAt - 0.2) <= DT + 1e-9).toBe(true)
		expect(math.abs(backAt - reachedAt - (HOLD + 0.2)) <= 2 * DT + 1e-9).toBe(true)
	end)

	it("holds the pose for as long as the input is held, then lets go", function()
		local r = rig()
		r.down.PIT_LIMITER = true
		HandGestures.press(r.hand, BUTTON, r.now)
		step(r, 1.5)
		local _, shape = HandGestures.pose(r.hand)
		expect(progress(r)).toBe(0.2)
		expect(shape).toBe("Pressed")
		r.down.PIT_LIMITER = false
		step(r, 0.1)
		expect(math.abs(progress(r) - 0.1) < 1e-6).toBe(true)
		step(r, 0.12)
		expect(r.hand.playing).toBe(nil)
		local pose, gripShape = HandGestures.pose(r.hand)
		expect(pose).toBe(nil)
		expect(gripShape).toBe("Grip")
	end)

	it("runs forward again from where it is when the same button is pressed on the way back", function()
		local r = rig()
		HandGestures.press(r.hand, BUTTON, r.now)
		step(r, 0.2 + HOLD + 0.05)
		local before = progress(r)
		expect(before < 0.2 and before > 0).toBe(true)
		HandGestures.press(r.hand, BUTTON, r.now)
		step(r, DT)
		-- No jump: one frame on from where it was, forward.
		expect(math.abs(progress(r) - (before + DT)) < 1e-6).toBe(true)
	end)

	it("makes another control on the same hand wait until the first is back on the grip", function()
		local r = rig()
		HandGestures.press(r.hand, BUTTON, r.now)
		step(r, 0.05)
		HandGestures.press(r.hand, OTHER, r.now)
		local switchedAt = nil
		for _ = 1, 60 do
			step(r, DT)
			local playing = r.hand.playing
			if playing and playing.gesture == OTHER and switchedAt == nil then
				switchedAt = r.now
				-- It starts from the grip, not mid-way.
				expect(playing.progress).toBe(0)
			end
		end
		assert(switchedAt, "the waiting gesture played")
		expect(switchedAt >= 0.2 + HOLD + 0.2 - 1e-9).toBe(true)
	end)

	it("shows the control's shape only from the shape change on, the grip before it", function()
		local r = rig()
		r.down.PIT_LIMITER = true
		HandGestures.press(r.hand, BUTTON, r.now)
		step(r, 0.1)
		local _, early = HandGestures.pose(r.hand)
		expect(early).toBe("Grip")
		step(r, 0.1)
		local _, late = HandGestures.pose(r.hand)
		expect(late).toBe("Pressed")
	end)

	it(
		"turns a latching control from its shown state to the next, and keeps it turned on the way back",
		function()
			local r = rig({ DRIVING_MODE = "1" })
			HandGestures.press(r.hand, KNOB, r.now)
			step(r, 0.05)
			local control, from, to, share = HandGestures.turn(r.hand)
			expect(control).toBe("Knob")
			expect(from).toBe("1")
			expect(to).toBe("2")
			expect(share).toBe(0)
			step(r, 0.1)
			local _, _, _, mid = HandGestures.turn(r.hand)
			expect(mid > 0 and mid < 1).toBe(true)
			step(r, 0.1 + HOLD + 0.1)
			local _, _, _, after = HandGestures.turn(r.hand)
			expect(after).toBe(1)
			expect(r.inputs.shown.DRIVING_MODE).toBe("2")
		end
	)

	it("steps the knob once per press, in order, when the presses come faster than the finger", function()
		local r = rig({ DRIVING_MODE = "1" })
		local seen: { string } = {}
		for _ = 1, 3 do
			HandGestures.press(r.hand, KNOB, r.now)
		end
		for _ = 1, 200 do
			step(r, DT)
			local playing = r.hand.playing
			if playing and playing.progress == 0 then
				table.insert(seen, `{playing.from}>{playing.to}`)
			end
		end
		expect(table.concat(seen, " ")).toBe("1>2 2>OFF OFF>1")
		expect(r.inputs.shown.DRIVING_MODE).toBe("1")
	end)

	it(
		"moves a seat-frame track fully onto the live grip at its ends and not at all past its blend",
		function()
			local seatTrack = track(0.4)
			seatTrack.gripBlend = 0.2
			local toggle: Config.Gesture = {
				control = "RAIN_LIGHT",
				side = 1,
				frame = "Seat",
				latch = "Toggle",
				tracks = { Off = seatTrack, On = seatTrack },
			}
			local r = rig({ RAIN_LIGHT = "Off" })
			r.down.RAIN_LIGHT = true
			HandGestures.press(r.hand, toggle, r.now)
			HandGestures.step(r.hand, r.inputs, HOLD, r.now, 0)
			expect(HandGestures.gripShare(r.hand)).toBe(1)
			step(r, 0.1)
			local mid = HandGestures.gripShare(r.hand)
			expect(mid > 0 and mid < 1).toBe(true)
			step(r, 0.2)
			expect(HandGestures.gripShare(r.hand)).toBe(0)
		end
	)
end)

-- Steps for `seconds`, returning each control the hand worked with the time it did.
local function worked(r: Rig, seconds: number): { { control: string, at: number } }
	local found = {}
	for _ = 1, math.max(1, math.round(seconds / DT)) do
		r.now += DT
		local control = HandGestures.step(r.hand, r.inputs, HOLD, r.now, DT)
		if control then
			table.insert(found, { control = control, at = r.now })
		end
	end
	return found
end

describe("Hand gestures: the instant the hand works its control", function()
	it("reports a button once, as the thumb reaches it, and again on a press while it is held", function()
		local r = rig()
		r.down.PIT_LIMITER = true
		HandGestures.press(r.hand, BUTTON, r.now)
		local first = worked(r, 0.5)
		expect(#first).toBe(1)
		expect(first[1].control).toBe("PIT_LIMITER")
		-- The thumb reaches the button at the track's end, 0.2 s in (the hand starts the frame after
		-- the press is seen).
		expect(first[1].at > 0.2 and first[1].at <= 0.2 + 2 * DT + 1e-9).toBe(true)
		HandGestures.press(r.hand, BUTTON, r.now)
		local again = worked(r, 0.1)
		expect(#again).toBe(1)
		r.down.PIT_LIMITER = false
		expect(#worked(r, 1)).toBe(0)
	end)

	it("reports a knob as its turn completes, not when the hand reaches its end", function()
		local r = rig({ DRIVING_MODE = "1" })
		HandGestures.press(r.hand, KNOB, r.now)
		local found = worked(r, 1)
		expect(#found).toBe(1)
		expect(found[1].control).toBe("DRIVING_MODE")
		-- The frame the press is seen, the hand does not move; the turn completes within two frames of
		-- its time on the track.
		expect(found[1].at > KNOB_TURN.finish and found[1].at <= KNOB_TURN.finish + 2 * DT + 1e-9).toBe(true)
	end)
end)
