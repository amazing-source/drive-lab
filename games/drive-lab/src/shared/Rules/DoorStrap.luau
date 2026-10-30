--!strict
--[[
	The driver's door pull strap: a soft loop sewn to the door card's lower edge. Left alone it
	hangs, leaned a little off the card into the cabin, as long as the trim below lets it (a soft
	strap pushed short, measured per door angle). While the driver pulls the door shut by it, it
	runs taut from where it is sewn toward the palm, never longer than it is.

	When it is held follows from the car's replicated entry state, so every client agrees: a clip
	that closes the door by the strap is playing and the door has come down to the angle where
	the hand takes it, but is not yet shut (the hand lets go as it latches). Where the palm is
	comes from the animated arm. Vectors are in the chassis's space (Rules/Hinge), lengths in any
	one unit.
]]
local Config = require("../Config/CarEntry")
local Entry = require("./CarEntry")
local Hinge = require("./Hinge")

type Vector = Hinge.Vector

-- A strap's shape in one length unit: its length, its lean off the card (radians) and the most
-- it can hang at each door angle (radians, ascending).
export type Shape = {
	length: number,
	lean: number,
	hang: { { angle: number, length: number } },
}

-- Which way the strap runs from where it is sewn (a unit vector), and how far.
export type Pose = { direction: Vector, length: number }

local DoorStrap = {}

-- The clips whose hand closes the door by the strap, decided with the entry lead and the
-- animation workstream (#31): the seated close, and the end of getting in, where the hand moves
-- from the door's lower edge onto the strap at the same angle.
DoorStrap.HOLDING = table.freeze({ InsideClose = true, GetIn = true }) :: { [string]: boolean }

-- The door motions that are clips, by name ("Closed" and "Open" are rests; Car/CarState).
local CLIP_NAMES: { [string]: Config.ClipName } = {
	OutsideOpen = "OutsideOpen",
	InsideClose = "InsideClose",
	InsideOpen = "InsideOpen",
	OutsideClose = "OutsideClose",
}

local DOWN: Vector = table.freeze({ x = 0, y = -1, z = 0 })
-- Toward the cabin from the driver's door (on the left), when the card faces straight down.
local INBOARD: Vector = table.freeze({ x = 1, y = 0, z = 0 })

local function dot(a: Vector, b: Vector): number
	return a.x * b.x + a.y * b.y + a.z * b.z
end

local function scaled(a: Vector, k: number): Vector
	return { x = a.x * k, y = a.y * k, z = a.z * k }
end

-- The clip moving the door now: a running entry or exit sequence's step, or the door's own
-- motion while it plays; nil when the door is at rest.
function DoorStrap.clip(car: Entry.Car, state: Entry.State, now: number): Config.ClipName?
	if state.entry ~= "None" then
		local steps = Entry.steps(car, state.entry, state.entryDoorOpen)
		if now - state.entryAt < Entry.length(steps) then
			local step = Entry.stepAt(steps, now - state.entryAt)
			return if step then step.clip else nil
		end
	end
	local clip: Config.ClipName? = CLIP_NAMES[state.door]
	if clip == nil or now - state.doorAt >= car.door.clips[clip].duration then
		return nil
	end
	return clip
end

-- The hand holds the strap: a holding clip plays and the door is down to `grab` (radians) but
-- not shut.
function DoorStrap.held(clip: string?, angle: number, grab: number): boolean
	return clip ~= nil and DoorStrap.HOLDING[clip] == true and angle > 0 and angle <= grab
end

-- The most the strap hangs at a door angle: linear between the shape's rows, held past either
-- end, never more than the strap's length.
function DoorStrap.hangLength(shape: Shape, angle: number): number
	local rows = shape.hang
	local first, last = rows[1], rows[#rows]
	if angle <= first.angle then
		return math.min(first.length, shape.length)
	end
	for index = 2, #rows do
		local below, above = rows[index - 1], rows[index]
		if angle <= above.angle then
			local share = (angle - below.angle) / (above.angle - below.angle)
			return math.min(below.length + (above.length - below.length) * share, shape.length)
		end
	end
	return math.min(last.length, shape.length)
end

-- Straight down, leaned `lean` radians off the card toward where it faces (`facing`, the card's
-- normal into the cabin, as turned with the door).
function DoorStrap.hanging(facing: Vector, lean: number): Vector
	local along = dot(facing, DOWN)
	local away =
		{ x = facing.x - DOWN.x * along, y = facing.y - DOWN.y * along, z = facing.z - DOWN.z * along }
	local size = math.sqrt(dot(away, away))
	away = if size > 1e-6 then scaled(away, 1 / size) else INBOARD
	local down, out = math.cos(lean), math.sin(lean)
	return {
		x = DOWN.x * down + away.x * out,
		y = DOWN.y * down + away.y * out,
		z = DOWN.z * down + away.z * out,
	}
end

-- The strap from `top` (where it is sewn, as turned with the door): toward `palm` when the hand
-- holds it, as far as the palm but never past its length; hanging otherwise, or when the palm
-- sits on its top.
function DoorStrap.pose(shape: Shape, top: Vector, facing: Vector, angle: number, palm: Vector?): Pose
	if palm then
		local to = { x = palm.x - top.x, y = palm.y - top.y, z = palm.z - top.z }
		local distance = math.sqrt(dot(to, to))
		if distance > 1e-6 then
			return { direction = scaled(to, 1 / distance), length = math.min(distance, shape.length) }
		end
	end
	return { direction = DoorStrap.hanging(facing, shape.lean), length = DoorStrap.hangLength(shape, angle) }
end

return table.freeze(DoorStrap)
