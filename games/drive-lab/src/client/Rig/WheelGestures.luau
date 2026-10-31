--!strict
--[[
	The local driver's hand gestures (Config/DriverGestures, Rules/HandGestures): while the player
	works a wheel button or a panel switch the car has a gesture for, the hand on that side leaves
	its grip along the gesture's keys and comes back. The controls a gesture turns (the manettino's
	knob, a panel toggle) are turned with the finger, and otherwise show the car's state. The
	switch states are local to the driving client, like the steering readout, so only the driver's
	own client plays them; other clients keep the grip.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Catalog = require(ReplicatedStorage.Shared.Config.Cars.Catalog)
local Controls = require(ReplicatedStorage.Shared.Config.Controls)
local DriveModes = require(ReplicatedStorage.Shared.Rules.DriveModes)
local DriverGestures = require(ReplicatedStorage.Shared.Config.DriverGestures)
local HandGestures = require(ReplicatedStorage.Shared.Rules.HandGestures)
local StartupArms = require(ReplicatedStorage.Shared.Rules.StartupArms)
local Units = require(ReplicatedStorage.Shared.Units)

export type State = {
	entry: Catalog.Entry,
	model: Model,
	chassis: BasePart,
	gestures: DriverGestures.Gestures,
	-- By side, +1 then -1.
	hands: { [number]: HandGestures.Hand },
	inputs: HandGestures.Inputs,
	-- The welds of the controls the gestures turn, by part name, with their rest C0 and the angle
	-- from that rest each state puts them at.
	turned: { [string]: { weld: Weld, rest: CFrame, angles: { [string]: number } } },
	-- The latch state each turned control shows, so it is written only when it changes.
	written: { [string]: number },
}

local STUDS_PER_METRE = 1 / Units.METRES_PER_STUD

local held: { [string]: number } = {}
local pressed: { string } = {}
-- Drivers with gestures this client is drawing (its own car, at most): presses are kept only then.
local active = 0
-- The controls each key works (a key can work several, as E shifts up and gets out).
local byKey: { [Enum.KeyCode]: { string } }? = nil

-- Every control's input, counted while held and remembered when it begins; the gestures read
-- only the controls they play on.
local function listen()
	if byKey then
		return
	end
	local map: { [Enum.KeyCode]: { string } } = {}
	for name, keys in Controls :: { [string]: any } do
		if type(keys) == "table" then
			for _, key in keys do
				map[key] = map[key] or {}
				table.insert(map[key], name)
			end
		end
	end
	byKey = map
	UserInputService.InputBegan:Connect(function(input, processed)
		local controls: { string } = if processed then {} else map[input.KeyCode] or {}
		for _, control in controls do
			held[control] = (held[control] or 0) + 1
			if active > 0 then
				table.insert(pressed, control)
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local controls: { string } = map[input.KeyCode] or {}
		for _, control in controls do
			held[control] = math.max(0, (held[control] or 0) - 1)
		end
	end)
end

local function poseFrame(pose: StartupArms.Pose): CFrame
	local p, q = pose.position, pose.rotation
	local k = STUDS_PER_METRE
	return CFrame.new(p.x * k, p.y * k, p.z * k, q.x, q.y, q.z, q.w)
end

local function framePose(frame: CFrame): StartupArms.Pose
	local axis, angle = frame:ToAxisAngle()
	local sine = math.sin(angle / 2)
	local p = frame.Position / STUDS_PER_METRE
	return {
		position = { x = p.X, y = p.Y, z = p.Z },
		rotation = { w = math.cos(angle / 2), x = axis.X * sine, y = axis.Y * sine, z = axis.Z * sine },
	}
end

-- The state a latching gesture's control is in on the car.
local function actual(state: State, gesture: DriverGestures.Gesture): string
	if gesture.latch == "Mode" then
		local order = state.entry.physics.modeOrder
		return DriveModes.current(order, state.model:GetAttribute("DrivingMode"))
	end
	return if state.model:GetAttribute("RainLightOn") == true then "On" else "Off"
end

local WheelGestures = {}

-- The gestures of the car `model` for its local driver, or nil for a car without any.
function WheelGestures.new(entry: Catalog.Entry, model: Model, chassis: BasePart): State?
	local gestures = entry.driver.gestures
	if gestures == nil then
		return nil
	end
	listen()
	active += 1
	local state: State
	local inputs: HandGestures.Inputs = {
		held = function(control: string): boolean
			return (held[control] or 0) > 0
		end,
		shown = {},
		after = function(gesture: DriverGestures.Gesture, from: string): string
			return HandGestures.after(gesture, entry.physics.modeOrder, from)
		end,
	}
	state = {
		entry = entry,
		model = model,
		chassis = chassis,
		gestures = gestures,
		hands = { [1] = HandGestures.newHand(), [-1] = HandGestures.newHand() },
		inputs = inputs,
		turned = {},
		written = {},
	}
	table.clear(pressed)
	return state
end

-- Finds the welds of the controls the gestures turn (Car/CarRig), once each has streamed in.
local function findTurned(state: State)
	for _, gesture in state.gestures.list do
		for _, track in gesture.tracks do
			local turn = track.turn
			if turn and state.turned[turn.control] == nil then
				local weld = state.chassis:FindFirstChild(turn.control)
				local rest = weld and weld:GetAttribute("RestC0")
				local found = HandGestures.controlAngles(state.entry.model, gesture, turn.control)
				if weld and weld:IsA("Weld") and typeof(rest) == "CFrame" and found then
					state.turned[turn.control] = { weld = weld, rest = rest, angles = found }
				end
			end
		end
	end
end

-- One frame: presses since the last, then each hand moved on. `ready[side]` says whether that
-- hand is on the wheel (the start-up done); a hand that is not drops its gestures.
function WheelGestures.step(state: State, ready: { [number]: boolean }, now: number, dt: number)
	for _, control in pressed do
		for _, gesture in state.gestures.list do
			if gesture.control == control and ready[gesture.side] then
				HandGestures.press(state.hands[gesture.side], gesture, now)
			end
		end
	end
	table.clear(pressed)
	for side, hand in state.hands do
		if ready[side] then
			HandGestures.step(hand, state.inputs, state.gestures.HOLD_MIN, now, dt)
		else
			hand.playing = nil
			table.clear(hand.queue)
		end
	end
	-- A latching control with nothing playing or waiting on its hand shows the car's state.
	for _, gesture in state.gestures.list do
		if gesture.latch and HandGestures.idle(state.hands[gesture.side]) then
			state.inputs.shown[gesture.control] = actual(state, gesture)
		end
	end
end

-- The wrist frame and the shape a side's gesture draws this frame, or nil while it grips.
-- `wheel` is the steering wheel's frame as the arms follow it, `grip` the side's grip wrist in it.
function WheelGestures.wrist(
	state: State,
	side: number,
	wheel: CFrame,
	seat: CFrame,
	grip: CFrame
): (CFrame?, string)
	local hand = state.hands[side]
	if hand.playing == nil then
		return nil, "Grip"
	end
	local pose, shape = HandGestures.inSeat(
		hand,
		framePose(seat:ToObjectSpace(wheel)),
		framePose(seat:ToObjectSpace(wheel * grip))
	)
	if pose == nil then
		return nil, "Grip"
	end
	return seat * poseFrame(pose), shape
end

-- The control a gesture's tracks turn, if any.
local function turnedBy(gesture: DriverGestures.Gesture): string?
	for _, track in gesture.tracks do
		if track.turn then
			return track.turn.control
		end
	end
	return nil
end

-- Turns each control a gesture turns: with the finger while its gesture plays, else to the state
-- it shows.
function WheelGestures.turnControls(state: State)
	findTurned(state)
	for _, gesture in state.gestures.list do
		local name = turnedBy(gesture)
		local found = name and state.turned[name]
		if name and found then
			local control, from, to, share = HandGestures.turn(state.hands[gesture.side])
			local angle
			if control == name then
				local a, b = found.angles[from] or 0, found.angles[to] or 0
				angle = a + (b - a) * share
			else
				angle = found.angles[state.inputs.shown[gesture.control] or ""] or 0
			end
			if state.written[name] ~= angle then
				state.written[name] = angle
				found.weld.C0 = found.rest * CFrame.Angles(angle, 0, 0)
			end
		end
	end
end

-- The driver has gone: the turned controls back to rest.
function WheelGestures.release(state: State)
	active = math.max(0, active - 1)
	table.clear(pressed)
	for _, found in state.turned do
		if found.weld.Parent then
			found.weld.C0 = found.rest
		end
	end
end

return WheelGestures
