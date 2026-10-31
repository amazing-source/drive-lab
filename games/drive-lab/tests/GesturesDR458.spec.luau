--!strict
local Binding = require("../src/shared/Config/Cars/Binding")
local Config = require("../src/shared/Config/DriverGestures")
local Contract = require("../src/shared/Config/Cars/Contract")
local DR458 = require("../src/shared/Config/Cars/DR458")
local HandGestures = require("../src/shared/Rules/HandGestures")
local Hinge = require("../src/shared/Rules/Hinge")
local StartupArms = require("../src/shared/Rules/StartupArms")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

type Vector = StartupArms.Vector
type Pose = StartupArms.Pose

local GESTURES = assert(DR458.driver.gestures, "the DR458 has hand gestures")
local MODEL = DR458.model
local METRES_PER_STUD = 0.28 / 1.5
-- How close a contact stays, metres (as the start-up's controls).
local TOUCH_GAP = 0.002
local DT = 1 / 60

local function gap(a: Vector, b: Vector): number
	return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
end

local function sub(a: Vector, b: Vector): Vector
	return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }
end

local function dot(a: Vector, b: Vector): number
	return a.x * b.x + a.y * b.y + a.z * b.z
end

local function cross(a: Vector, b: Vector): Vector
	return { x = a.y * b.z - a.z * b.y, y = a.z * b.x - a.x * b.z, z = a.x * b.y - a.y * b.x }
end

local function unit(a: Vector): Vector
	local length = math.sqrt(dot(a, a))
	return { x = a.x / length, y = a.y / length, z = a.z / length }
end

-- A binding point in the DriverSeat's frame (metres), as the start-up specs measure.
local function inSeat(point: Binding.CarPoint): Vector
	local p, s = Hinge.chassis(point), Hinge.chassis(MODEL.seat)
	return { x = p.x - s.x, y = p.y - s.y, z = p.z - s.z }
end

-- The steering wheel's frame in the seat frame at rest, as tools/anim/gesture_paths.py keys in it:
-- z along the column toward the driver, x the car's right across it.
local HUB = assert(MODEL.steeringHub, "the DR458 has a steering hub")
local HUB_Z = unit(Hinge.chassis(HUB.axis))
local HUB_X = unit(
	sub({ x = 1, y = 0, z = 0 }, { x = HUB_Z.x * HUB_Z.x, y = HUB_Z.x * HUB_Z.y, z = HUB_Z.x * HUB_Z.z })
)
local HUB_Y = cross(HUB_Z, HUB_X)
local HUB_AT = inSeat(HUB.pivot)

local function inWheel(point: Vector): Vector
	local rel = sub(point, HUB_AT)
	return { x = dot(rel, HUB_X), y = dot(rel, HUB_Y), z = dot(rel, HUB_Z) }
end

local function quaternion(axis: Vector, angle: number): StartupArms.Rotation
	local s = math.sin(angle / 2)
	return { w = math.cos(angle / 2), x = axis.x * s, y = axis.y * s, z = axis.z * s }
end

-- The wheel's frame in the seat frame turned `angle` radians, as Controllers/DriverArms turns it
-- (negative about the column toward the driver for a positive steer).
local function wheelPose(angle: number): Pose
	-- The rotation whose columns are HUB_X, HUB_Y, HUB_Z, as a quaternion.
	local m = { { HUB_X.x, HUB_Y.x, HUB_Z.x }, { HUB_X.y, HUB_Y.y, HUB_Z.y }, { HUB_X.z, HUB_Y.z, HUB_Z.z } }
	local trace = m[1][1] + m[2][2] + m[3][3]
	local w = math.sqrt(1 + trace) / 2
	local rest = {
		w = w,
		x = (m[3][2] - m[2][3]) / (4 * w),
		y = (m[1][3] - m[3][1]) / (4 * w),
		z = (m[2][1] - m[1][2]) / (4 * w),
	}
	return {
		position = HUB_AT,
		rotation = StartupArms.multiply(rest, quaternion({ x = 0, y = 0, z = 1 }, -angle)),
	}
end

local function keyPose(key: { number }): Pose
	return {
		position = { x = key[2], y = key[3], z = key[4] },
		rotation = { w = key[5], x = key[6], y = key[7], z = key[8] },
	}
end

local function gestureOf(control: string): Config.Gesture
	for _, gesture in GESTURES.list do
		if gesture.control == control then
			return gesture
		end
	end
	error(`no gesture on {control}`)
end

-- A hand pressing `gesture` from `state`, stepped to `seconds` into its track with the input held.
local function played(gesture: Config.Gesture, state: string, seconds: number): HandGestures.Hand
	local hand = HandGestures.newHand()
	local inputs: HandGestures.Inputs = {
		held = function()
			return true
		end,
		shown = { [gesture.control] = state },
		after = function(g: Config.Gesture, from: string): string
			return HandGestures.after(g, DR458.physics.modeOrder, from)
		end,
	}
	HandGestures.press(hand, gesture, 0)
	HandGestures.step(hand, inputs, GESTURES.HOLD_MIN, 0, 0)
	local now = 0
	while now < seconds - 1e-9 do
		local dt = math.min(DT, seconds - now)
		now += dt
		HandGestures.step(hand, inputs, GESTURES.HOLD_MIN, now, dt)
	end
	return hand
end

-- The grip's wrist frame in the wheel's frame (Rig/StartupHands.gripWrist), metres.
local function gripWrist(sign: number): Pose
	local grip = DR458.driver.grip
	local z = unit({ x = sign * grip.forearm.x, y = grip.forearm.y, z = grip.forearm.z })
	local up = { x = sign * grip.back.x, y = grip.back.y, z = grip.back.z }
	local along = dot(up, z)
	local y = unit({ x = up.x - z.x * along, y = up.y - z.y * along, z = up.z - z.z * along })
	local x = cross(y, z)
	local m = { { x.x, y.x, z.x }, { x.y, y.y, z.y }, { x.z, y.z, z.z } }
	local w = math.sqrt(math.max(0, 1 + m[1][1] + m[2][2] + m[3][3])) / 2
	return {
		position = {
			x = sign * grip.wrist.x * METRES_PER_STUD,
			y = grip.wrist.y * METRES_PER_STUD,
			z = grip.wrist.z * METRES_PER_STUD,
		},
		rotation = {
			w = w,
			x = (m[3][2] - m[2][3]) / (4 * w),
			y = (m[1][3] - m[3][1]) / (4 * w),
			z = (m[2][1] - m[1][2]) / (4 * w),
		},
	}
end

local function turnAngle(rotation: StartupArms.Rotation, other: StartupArms.Rotation): number
	local d =
		math.abs(rotation.w * other.w + rotation.x * other.x + rotation.y * other.y + rotation.z * other.z)
	return 2 * math.acos(math.min(1, d))
end

local STEERS = { -math.rad(110), -math.rad(90), 0, math.rad(45), math.rad(90), math.rad(110) }

describe("DR458 hand gestures: the buttons, the knob and the RAIN LIGHT toggle", function()
	it("starts every wheel gesture on the hand's grip, so leaving it does not jump", function()
		for _, gesture in GESTURES.list do
			if gesture.frame == "Wheel" then
				local grip = gripWrist(gesture.side)
				for state, track in gesture.tracks do
					local first = keyPose(track.keys[1])
					if
						gap(first.position, grip.position) > 1e-4
						or turnAngle(first.rotation, grip.rotation) > math.rad(0.1)
					then
						error(`{gesture.control} {state} does not start on the grip`)
					end
				end
			end
		end
	end)

	it("keeps a pressing thumb on its button at every steering angle the hands follow", function()
		for _, control in { "HIGH_BEAM", "PIT_LIMITER", "DISPLAY_PAGE", "WASHER", "WIPER" } do
			local gesture = gestureOf(control)
			local track = gesture.tracks.Press
			local finish = track.keys[#track.keys][1]
			local hand = played(gesture, "Press", finish + 0.05)
			for _, steer in STEERS do
				local wheel = wheelPose(steer)
				local pose = assert(HandGestures.inSeat(hand, wheel, wheel), `{control} is pressing`)
				local thumb = StartupArms.apply(pose, track.tip)
				local button = StartupArms.apply(wheel, track.target)
				if gap(thumb, button) > 0.001 then
					error(
						`{control} misses its button by {gap(thumb, button)} m at {math.deg(steer)} degrees`
					)
				end
			end
		end
	end)

	it(
		"shows a thumb's mesh only once the hand is at its pressing pose, the grip or open hand before",
		function()
			-- Sliding on the rim the thumb moves at the end of the slide; coming back onto the rim the
			-- open hand closes in the last frames, as the start-up's hands close on it.
			local closes = { WASHER = true, WIPER = true }
			for _, control in { "HIGH_BEAM", "PIT_LIMITER", "DISPLAY_PAGE", "WASHER", "WIPER" } do
				local track = gestureOf(control).tracks.Press
				local finish = track.keys[#track.keys][1]
				local last = keyPose(track.keys[#track.keys])
				local thumb = track.shapes[#track.shapes]
				expect(string.find(thumb.shape, "HandThumb", 1, true) ~= nil).toBe(true)
				if closes[control] then
					if finish - thumb.at > 0.05 + 1e-9 then
						error(`{control} closes on the rim {finish - thumb.at} s before it is there`)
					end
				else
					local at = StartupArms.sample(track.keys, thumb.at)
					if gap(at.position, last.position) > 0.002 then
						error(
							`{control} swaps to its thumb {gap(at.position, last.position)} m from its pose`
						)
					end
				end
				for _, change in track.shapes do
					if change.at < thumb.at then
						expect(change.shape == "Grip" or change.shape == "Rest").toBe(true)
					end
				end
			end
		end
	)

	it(
		"keeps the finger on the knob's lever while the knob turns, for every step of the drive modes",
		function()
			local gesture = gestureOf("DRIVING_MODE")
			local knob = assert(MODEL.modeKnob, "the DR458 binds its knob")
			local pivot = inWheel(inSeat(knob.hinge.pivot))
			local axisSeat = Hinge.chassis(knob.hinge.axis)
			local axis =
				unit({ x = dot(axisSeat, HUB_X), y = dot(axisSeat, HUB_Y), z = dot(axisSeat, HUB_Z) })
			for _, state in DR458.physics.modeOrder do
				local track = gesture.tracks[state]
				local turn = assert(track.turn, `the {state} track turns the knob`)
				local angles =
					assert(HandGestures.controlAngles(MODEL, gesture, turn.control), "the knob's angles")
				local reference: Vector? = nil
				local worst = 0
				for step = 0, 12 do
					local t = turn.start + (turn.finish - turn.start) * step / 12
					local hand = played(gesture, state, t)
					local control, from, to, share = HandGestures.turn(hand)
					expect(control).toBe(turn.control)
					local angle = angles[from] + (angles[to] - angles[from]) * share
					local wheel = wheelPose(0)
					local pose = assert(HandGestures.inSeat(hand, wheel, wheel), "the finger is out")
					local tip = inWheel(StartupArms.apply(pose, track.tip))
					-- The finger's end in the lever's own frame: still while the lever turns under it.
					local back = Hinge.rotate(tip, pivot, axis, -angle)
					if reference == nil then
						reference = back
					else
						worst = math.max(worst, gap(back, reference :: Vector))
					end
				end
				if worst > TOUCH_GAP then
					error(`the finger leaves the lever by {worst} m stepping from {state}`)
				end
			end
		end
	)

	it("turns the knob toward the driver's left from OFF to 1 to 2, as the wheel's markings run", function()
		local gesture = gestureOf("DRIVING_MODE")
		local knob = assert(MODEL.modeKnob, "the DR458 binds its knob")
		local angles =
			assert(HandGestures.controlAngles(MODEL, gesture, knob.hinge.part), "the knob's angles")
		local pivot = inSeat(knob.hinge.pivot)
		local axis = Hinge.chassis(knob.hinge.axis)
		-- The lever's tip at OFF points up the wheel's face.
		local tip =
			{ x = pivot.x + HUB_Y.x * 0.015, y = pivot.y + HUB_Y.y * 0.015, z = pivot.z + HUB_Y.z * 0.015 }
		local function across(mode: string): number
			return dot(sub(Hinge.rotate(tip, pivot, axis, angles[mode]), pivot), HUB_X)
		end
		expect(math.abs(across("OFF")) < 1e-6).toBe(true)
		expect(across("1") < -0.005).toBe(true)
		expect(across("2") < across("1")).toBe(true)
	end)

	it("keeps the index on the RAIN LIGHT lever while the game flicks it, both ways", function()
		local gesture = gestureOf("RAIN_LIGHT")
		local hinge = assert(MODEL.controls and MODEL.controls.PanelSwitch_RainLight, "the toggle is bound")
		local pivot, axis = inSeat(hinge.pivot), Hinge.chassis(hinge.axis)
		for _, state in { "Off", "On" } do
			local track = gesture.tracks[state]
			local turn = assert(track.turn, "the flick turns the toggle")
			local angles =
				assert(HandGestures.controlAngles(MODEL, gesture, turn.control), "the toggle's angles")
			local reference: Vector? = nil
			local worst = 0
			for step = 0, 8 do
				local t = turn.start + (turn.finish - turn.start) * step / 8
				local hand = played(gesture, state, t)
				local _, from, to, share = HandGestures.turn(hand)
				local angle = angles[from] + (angles[to] - angles[from]) * share
				local wheel = wheelPose(0)
				local pose =
					assert(HandGestures.inSeat(hand, wheel, keyPose(track.keys[1])), "the finger is out")
				local back = Hinge.rotate(StartupArms.apply(pose, track.tip), pivot, axis, -angle)
				if reference == nil then
					reference = back
				else
					worst = math.max(worst, gap(back, reference :: Vector))
				end
			end
			if worst > TOUCH_GAP then
				error(`the index leaves the toggle by {worst} m flicking it from {state}`)
			end
		end
	end)

	it("takes the RAIN LIGHT reach off the live grip and back onto it at any steering angle", function()
		local gesture = gestureOf("RAIN_LIGHT")
		local track = gesture.tracks.Off
		local keyed = keyPose(track.keys[1])
		for _, steer in STEERS do
			-- The live grip: the keyed one carried round the column with the wheel.
			local wheel = wheelPose(steer)
			local rest = wheelPose(0)
			local inWheelFrame = {
				position = StartupArms.apply({
					position = { x = 0, y = 0, z = 0 },
					rotation = {
						w = rest.rotation.w,
						x = -rest.rotation.x,
						y = -rest.rotation.y,
						z = -rest.rotation.z,
					},
				}, sub(keyed.position, rest.position)),
				rotation = StartupArms.multiply(
					{ w = rest.rotation.w, x = -rest.rotation.x, y = -rest.rotation.y, z = -rest.rotation.z },
					keyed.rotation
				),
			}
			local live = {
				position = StartupArms.apply(wheel, inWheelFrame.position),
				rotation = StartupArms.multiply(wheel.rotation, inWheelFrame.rotation),
			}
			local hand = played(gesture, "Off", 0)
			local pose = assert(HandGestures.inSeat(hand, wheel, live), "the reach has started")
			if gap(pose.position, live.position) > 1e-6 or turnAngle(pose.rotation, live.rotation) > 1e-4 then
				error(`the reach leaves from the keyed grip, not the live one, at {math.deg(steer)} degrees`)
			end
		end
	end)
	it("refuses a car whose knob gesture has no track for one of its drive modes", function()
		local knob = gestureOf("DRIVING_MODE")
		local tracks = table.clone(knob.tracks)
		tracks["2"] = nil
		local broken = table.clone(knob)
		broken.tracks = tracks
		local list = {}
		for _, gesture in GESTURES.list do
			table.insert(list, if gesture == knob then broken else gesture)
		end
		local driver = table.clone(DR458.driver)
		driver.gestures = { list = list, MESHES = GESTURES.MESHES, HOLD_MIN = GESTURES.HOLD_MIN }
		local entry = table.clone(DR458)
		entry.driver = driver
		local ok, problem = pcall(Contract.define, entry)
		expect(ok).toBe(false)
		expect(string.find(tostring(problem), 'no track for "2"', 1, true) ~= nil).toBe(true)
	end)
end)
