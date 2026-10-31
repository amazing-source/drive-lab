--!strict
--[[
	When a DR458 cockpit control's press takes effect, against its hand gesture's own timeline
	(Config/Cars/DR458/Gestures): the instant the hand works it, as Rig/WheelGestures settles it
	(Rules/HandGestures.step), never at the key.
]]
local Config = require("../src/shared/Config/DriverGestures")
local DR458 = require("../src/shared/Config/Cars/DR458")
local HandGestures = require("../src/shared/Rules/HandGestures")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local GESTURES = assert(DR458.driver.gestures, "the DR458 has hand gestures")
local DT = 1 / 60
-- The hand starts moving the frame after the press is seen (Rules/HandGestures.step).
local FRAMES = 2 * DT + 1e-9

type Rig = { hand: HandGestures.Hand, inputs: HandGestures.Inputs, down: { [string]: boolean }, now: number }

local function rig(): Rig
	local down: { [string]: boolean } = {}
	local shown: { [string]: string } = {}
	for _, gesture in GESTURES.list do
		if gesture.latch == "Mode" then
			shown[gesture.control] = DR458.physics.modeOrder[1]
		elseif gesture.latch == "Toggle" then
			shown[gesture.control] = "Off"
		end
	end
	return {
		hand = HandGestures.newHand(),
		down = down,
		now = 0,
		inputs = {
			held = function(control: string): boolean
				return down[control] == true
			end,
			shown = shown,
			after = function(g: Config.Gesture, from: string): string
				return HandGestures.after(g, DR458.physics.modeOrder, from)
			end,
		},
	}
end

-- Steps the hand for `seconds` at 60 FPS; each effect with its time and press count.
local function run(r: Rig, seconds: number): { { control: string, at: number, presses: number } }
	local found = {}
	for _ = 1, math.max(1, math.round(seconds / DT)) do
		r.now += DT
		local control, presses = HandGestures.step(r.hand, r.inputs, GESTURES.HOLD_MIN, r.now, DT)
		if control then
			table.insert(found, { control = control, at = r.now, presses = presses })
		end
	end
	return found
end

-- When the hand works the control on its track from `state`: the thumb at the button (the track's
-- end) or the knob or toggle at the end of its turn.
local function contactOf(gesture: Config.Gesture, state: string): number
	local track = assert(HandGestures.track(gesture, state), "a track from that state")
	local turn = track.turn
	if turn then
		return turn.finish
	end
	return track.keys[#track.keys][1]
end

local function gestureOf(control: string): Config.Gesture
	for _, gesture in GESTURES.list do
		if gesture.control == control then
			return gesture
		end
	end
	error(`no gesture on {control}`)
end

describe("Control timing on the DR458", function()
	it("acts on every gestured control as the hand works it, once, never at the key", function()
		for _, gesture in GESTURES.list do
			local r = rig()
			local state = if gesture.latch then r.inputs.shown[gesture.control] else "Press"
			local contact = contactOf(gesture, state)
			r.down[gesture.control] = true
			expect(HandGestures.press(r.hand, gesture, r.now)).toBe(true)
			-- The frame the press is seen: nothing yet.
			local first, presses = HandGestures.step(r.hand, r.inputs, GESTURES.HOLD_MIN, r.now, 0)
			expect(first == nil and presses == 0).toBe(true)
			r.down[gesture.control] = false
			local found = run(r, contact + 1)
			expect(#found).toBe(1)
			expect(found[1].control).toBe(gesture.control)
			expect(found[1].presses).toBe(1)
			expect(found[1].at > contact - 1e-9 and found[1].at <= contact + FRAMES).toBe(true)
			-- Well after the key: no gesture of the DR458 reaches its control within 50 ms.
			expect(found[1].at > 0.05).toBe(true)
		end
	end)

	it(
		"steps the wiper once per press: two presses on the thumb's way apply together at its contact",
		function()
			local r = rig()
			local wiper = gestureOf("WIPER")
			local contact = contactOf(wiper, "Press")
			HandGestures.press(r.hand, wiper, r.now)
			HandGestures.step(r.hand, r.inputs, GESTURES.HOLD_MIN, r.now, 0)
			local before = run(r, contact / 2)
			expect(#before).toBe(0)
			expect(HandGestures.press(r.hand, wiper, r.now)).toBe(true)
			local found = run(r, contact)
			expect(#found).toBe(1)
			expect(found[1].presses).toBe(2)
		end
	)

	it("a press while the thumb holds its button acts on the next frame", function()
		local r = rig()
		local wiper = gestureOf("WIPER")
		r.down.WIPER = true
		HandGestures.press(r.hand, wiper, r.now)
		HandGestures.step(r.hand, r.inputs, GESTURES.HOLD_MIN, r.now, 0)
		run(r, contactOf(wiper, "Press") + 0.1)
		expect(HandGestures.holding(r.hand)).toBe("WIPER")
		HandGestures.press(r.hand, wiper, r.now)
		local found = run(r, DT)
		expect(#found).toBe(1)
		expect(found[1].presses).toBe(1)
	end)

	it("a press of another control on the same hand waits its turn, then acts at its own contact", function()
		local r = rig()
		local washer, wiper = gestureOf("WASHER"), gestureOf("WIPER")
		expect(washer.side).toBe(wiper.side)
		HandGestures.press(r.hand, washer, r.now)
		HandGestures.step(r.hand, r.inputs, GESTURES.HOLD_MIN, r.now, 0)
		expect(HandGestures.press(r.hand, wiper, r.now)).toBe(true)
		local found = run(r, 3)
		expect(#found).toBe(2)
		expect(found[1].control).toBe("WASHER")
		expect(found[2].control).toBe("WIPER")
		-- The wiper's thumb reaches its button only after the washer's hand has gone back.
		expect(found[2].at > found[1].at + contactOf(wiper, "Press")).toBe(true)
	end)

	it(
		"runs the washer and the flasher while the thumb holds the button: from contact to the way back",
		function()
			for _, control in { "WASHER", "HIGH_BEAM" } do
				local r = rig()
				local gesture = gestureOf(control)
				local contact = contactOf(gesture, "Press")
				r.down[control] = true
				HandGestures.press(r.hand, gesture, r.now)
				HandGestures.step(r.hand, r.inputs, GESTURES.HOLD_MIN, r.now, 0)
				local heldFrom, heldUntil = nil, nil
				for _ = 1, math.round(1.5 / DT) do
					r.now += DT
					if r.now > 1 then
						r.down[control] = false
					end
					HandGestures.step(r.hand, r.inputs, GESTURES.HOLD_MIN, r.now, DT)
					local holding = HandGestures.holding(r.hand) == control
					if holding and heldFrom == nil then
						heldFrom = r.now
					elseif not holding and heldFrom and heldUntil == nil then
						heldUntil = r.now
					end
				end
				assert(heldFrom and heldUntil, "the button was held, then let go")
				expect(heldFrom > contact - 1e-9 and heldFrom <= contact + FRAMES).toBe(true)
				-- Let go of at 1 s, long after the hold's minimum: the thumb lifts the next frame.
				expect(heldUntil > 1 and heldUntil <= 1 + FRAMES).toBe(true)
			end
		end
	)

	it("turns the manettino one position per press, each at its own turn", function()
		local r = rig()
		local knob = gestureOf("DRIVING_MODE")
		for _ = 1, 2 do
			expect(HandGestures.press(r.hand, knob, r.now)).toBe(true)
		end
		HandGestures.step(r.hand, r.inputs, GESTURES.HOLD_MIN, r.now, 0)
		local found = run(r, 3)
		expect(#found).toBe(2)
		expect(found[1].presses).toBe(1)
		expect(found[2].presses).toBe(1)
		expect(found[2].at > found[1].at).toBe(true)
	end)
end)
