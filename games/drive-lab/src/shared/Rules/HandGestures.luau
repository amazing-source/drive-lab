--!strict
--[[
	A hand's gestures on the wheel's buttons and the panel's switches (Config/DriverGestures): which
	gesture plays, how far along its track the hand is, and how far the control it turns has
	turned. The hand runs forward while the input is held (and until it has held the pose for
	HOLD_MIN after the last press), then back the same way to the grip; a press of another control
	on the same hand waits for it. Plain numbers, so Lune can test it.
]]
local Binding = require("../Config/Cars/Binding")
local Config = require("../Config/DriverGestures")
local DriveModes = require("./DriveModes")
local Hinge = require("./Hinge")
local StartupArms = require("./StartupArms")

export type Play = {
	gesture: Config.Gesture,
	track: Config.Track,
	-- The control's state before and after the press (both "Press" for a button).
	from: string,
	to: string,
	progress: number,
	finish: number,
	pressedAt: number,
	-- When the held pose was reached since the last press; nil until then.
	reachedAt: number?,
	-- Whether the control's turn has finished: it stays turned while the hand goes back.
	turned: boolean,
	-- The presses this gesture owes its control: they take effect when the hand works it.
	presses: number,
}

-- `queue` holds one gesture per press waiting its turn; `skipped`, the controls of presses whose
-- gesture could not play (no track from the control's state), which are owed at once.
export type Hand = {
	playing: Play?,
	queue: { Config.Gesture },
	skipped: { string },
}

-- What the caller knows each step: whether a control's input is held, and the state a latching
-- control shows (the knob's mode, the toggle's Off / On), which `step` moves on as it turns it.
export type Inputs = {
	held: (control: string) -> boolean,
	shown: { [string]: string },
	-- The state after `state` for a latching gesture: the next drive mode, or the toggle flipped.
	after: (gesture: Config.Gesture, state: string) -> string,
}

local QUEUE_LIMIT = 3

local HandGestures = {}

function HandGestures.newHand(): Hand
	return { playing = nil, queue = {}, skipped = {} }
end

-- The track for a press from `state`.
function HandGestures.track(gesture: Config.Gesture, state: string): Config.Track?
	return gesture.tracks[if gesture.latch then state else "Press"]
end

-- The input of `gesture`'s control began. The same button pressed again while its gesture plays
-- runs it forward again and is owed with it; anything else waits its turn. Returns whether the
-- hand took the press: false when its queue is full, and the press is then the caller's at once.
function HandGestures.press(hand: Hand, gesture: Config.Gesture, now: number): boolean
	local playing = hand.playing
	if playing and playing.gesture == gesture and gesture.latch == nil then
		playing.pressedAt = now
		playing.reachedAt = nil
		playing.presses += 1
		return true
	end
	if #hand.queue < QUEUE_LIMIT then
		table.insert(hand.queue, gesture)
		return true
	end
	return false
end

local function start(hand: Hand, inputs: Inputs, now: number): Play?
	while #hand.queue > 0 do
		local gesture = table.remove(hand.queue, 1) :: Config.Gesture
		local from = if gesture.latch then inputs.shown[gesture.control] else "Press"
		local track = from and HandGestures.track(gesture, from)
		if from and track then
			local keys = track.keys
			return {
				gesture = gesture,
				track = track,
				from = from,
				to = if gesture.latch then inputs.after(gesture, from) else from,
				progress = 0,
				finish = keys[#keys][1],
				pressedAt = now,
				reachedAt = nil,
				turned = false,
				presses = 1,
			}
		end
		table.insert(hand.skipped, gesture.control)
	end
	return nil
end

-- Moves the hand on by `dt` seconds, ending at `now`. Returns the control the hand worked in this
-- step, if it did, and how many presses take effect then: a button as the thumb reaches it (every
-- press made while the thumb was on its way, and again on each press while it holds the button),
-- a knob or a toggle as its turn completes (one press: each has its own turn).
function HandGestures.step(
	hand: Hand,
	inputs: Inputs,
	holdMin: number,
	now: number,
	dt: number
): (string?, number)
	local current = hand.playing
	if current == nil then
		current = start(hand, inputs, now)
		hand.playing = current
		-- A press starts moving in the frame it is seen.
		dt = 0
	end
	if current == nil then
		return nil, 0
	end
	local playing: Play = current
	local control = playing.gesture.control
	local turn = playing.track.turn
	local worked: string? = nil
	local reachedAt = playing.reachedAt
	local wanted = inputs.held(control) or reachedAt == nil or now - reachedAt < holdMin
	if wanted then
		-- Frame times summed in floating point land a hair short of the end: that is the end.
		local next = playing.progress + dt
		playing.progress = if next >= playing.finish - 1e-9 then playing.finish else next
		if playing.progress >= playing.finish and playing.reachedAt == nil then
			playing.reachedAt = now
			if turn == nil then
				worked = control
			end
		end
	else
		local next = playing.progress - dt
		playing.progress = if next <= 1e-9 then 0 else next
	end
	if turn and not playing.turned and playing.progress >= turn.finish then
		playing.turned = true
		inputs.shown[control] = playing.to
		worked = control
	end
	if playing.progress <= 0 and not wanted then
		hand.playing = nil
	end
	if worked == nil then
		return nil, 0
	end
	local presses = playing.presses
	playing.presses = 0
	return worked, presses
end

-- The button the thumb holds down this instant, if any: from the instant it reaches it until the
-- hand starts back. A knob or a toggle is worked once, never held.
function HandGestures.holding(hand: Hand): string?
	local playing = hand.playing
	if playing and playing.gesture.latch == nil and playing.progress >= playing.finish then
		return playing.gesture.control
	end
	return nil
end

-- The buttons held down this instant: each a thumb holds, and each whose press the hands could not
-- take (`atKey`), for as long as its key stays held; one let go of leaves `atKey`.
function HandGestures.heldButtons(
	hands: { [number]: Hand },
	atKey: { [string]: true },
	held: (control: string) -> boolean
): { [string]: true }
	local buttons: { [string]: true } = {}
	for _, hand in hands do
		local button = HandGestures.holding(hand)
		if button then
			buttons[button] = true
		end
	end
	for control in atKey do
		if held(control) then
			buttons[control] = true
		else
			atKey[control] = nil
		end
	end
	return buttons
end

-- The presses whose gesture could not play, by control, which are the caller's at once.
function HandGestures.unplayed(hand: Hand): { [string]: number }
	local owed: { [string]: number } = {}
	for _, control in hand.skipped do
		owed[control] = (owed[control] or 0) + 1
	end
	table.clear(hand.skipped)
	return owed
end

-- The hand leaves the wheel (the driver is busy elsewhere): the presses it still owed, by control,
-- which are the caller's at once, and nothing left playing or waiting.
function HandGestures.drop(hand: Hand): { [string]: number }
	local owed = HandGestures.unplayed(hand)
	local playing = hand.playing
	if playing and playing.presses > 0 then
		owed[playing.gesture.control] = (owed[playing.gesture.control] or 0) + playing.presses
	end
	for _, gesture in hand.queue do
		owed[gesture.control] = (owed[gesture.control] or 0) + 1
	end
	hand.playing = nil
	table.clear(hand.queue)
	return owed
end

-- The wrist's pose in the gesture's frame and the shape to draw, or nil when the hand grips.
function HandGestures.pose(hand: Hand): (StartupArms.Pose?, string)
	local playing = hand.playing
	if playing == nil then
		return nil, "Grip"
	end
	local track = playing.track
	local shape = track.shapes[1].shape
	for _, change in track.shapes do
		if playing.progress >= change.at then
			shape = change.shape
		end
	end
	return StartupArms.sample(track.keys, playing.progress), shape
end

local function smooth(share: number): number
	return share * share * (3 - 2 * share)
end

local function compose(a: StartupArms.Pose, b: StartupArms.Pose): StartupArms.Pose
	return {
		position = StartupArms.apply(a, b.position),
		rotation = StartupArms.multiply(a.rotation, b.rotation),
	}
end

-- The wrist's pose in the seat frame (metres) and the shape to draw, or nil when the hand grips.
-- `wheel` is the steering wheel's frame in the seat frame as the arms follow it, so a "Wheel"
-- gesture turns with it; a "Seat" gesture's keys are moved onto `grip` (the hand's live grip in
-- the seat frame) near their ends, wherever the wheel is.
function HandGestures.inSeat(
	hand: Hand,
	wheel: StartupArms.Pose,
	grip: StartupArms.Pose
): (StartupArms.Pose?, string)
	local pose, shape = HandGestures.pose(hand)
	local playing = hand.playing
	if pose == nil or playing == nil then
		return nil, "Grip"
	end
	if playing.gesture.frame == "Wheel" then
		return compose(wheel, pose), shape
	end
	local share = HandGestures.gripShare(hand)
	if share <= 0 then
		return pose, shape
	end
	local first = playing.track.keys[1]
	local keyed = {
		position = { x = first[2], y = first[3], z = first[4] },
		rotation = { w = first[5], x = first[6], y = first[7], z = first[8] },
	}
	return StartupArms.retarget(pose, keyed, grip, share), shape
end

-- The control the playing gesture turns, its states before and after the press, and how far it
-- has turned from one to the other (0 to 1, eased as a finger pushes it); nil when it turns none.
function HandGestures.turn(hand: Hand): (string?, string, string, number)
	local playing = hand.playing
	local turn = playing and playing.track.turn
	if playing == nil or turn == nil then
		return nil, "", "", 0
	end
	if playing.turned then
		return turn.control, playing.from, playing.to, 1
	end
	local share = math.clamp((playing.progress - turn.start) / (turn.finish - turn.start), 0, 1)
	return turn.control, playing.from, playing.to, smooth(share)
end

-- For a "Seat" gesture, 0 to 1: how much of the way from the keyed grip to the live one (the
-- wheel turned since the keys were made) the pose takes, all of it at the grip, none past the
-- track's gripBlend.
function HandGestures.gripShare(hand: Hand): number
	local playing = hand.playing
	local blend = playing and playing.track.gripBlend
	if playing == nil or blend == nil then
		return 0
	end
	return 1 - smooth(math.clamp(playing.progress / blend, 0, 1))
end

-- The state after `from` for a latching gesture: the car's next drive mode (`order`), or the toggle
-- flipped.
function HandGestures.after(gesture: Config.Gesture, order: { string }, from: string): string
	if gesture.latch == "Mode" then
		return DriveModes.after(order, from)
	end
	return if from == "On" then "Off" else "On"
end

-- The angle, from its rig weld's rest, at which each state puts the control a latching gesture
-- turns: the knob's position for each mode, or a toggle's travel when on. Nil when the binding
-- does not hinge `control` for that gesture.
function HandGestures.controlAngles(
	model: Binding.CarModel,
	gesture: Config.Gesture,
	control: string
): { [string]: number }?
	if gesture.latch == "Mode" then
		local knob = model.modeKnob
		if knob == nil or knob.hinge.part ~= control then
			return nil
		end
		local rest = Hinge.restAngle(knob.hinge)
		local found = {}
		for mode, angle in knob.positions do
			found[mode] = angle - rest
		end
		return found
	end
	local hinge = model.controls and model.controls[control]
	return if gesture.latch == "Toggle"
			and hinge
			and hinge.travel
		then { Off = 0, On = hinge.travel }
		else nil
end

-- Whether the hand has nothing playing or waiting: the controls it turns may show the car's state.
function HandGestures.idle(hand: Hand): boolean
	return hand.playing == nil and #hand.queue == 0
end

return table.freeze(HandGestures)
