--!strict
--[[
	The DR458's driver's door. Its entry over the cage is not animated yet (the animators' #108), so
	the door is direct: E seats the driver straight in the bucket and getting out stands them beside
	the door. The door still opens and shuts by the clips below, with no body animation (empty ids).
]]
local CarEntry = require("../../CarEntry")
local SVJDoor = require("../SVJ/Door")

local OPEN: CarEntry.Curve = table.freeze({ times = { 0.1, 0.9 }, values = { 0, 1 } })
local SHUT: CarEntry.Curve = table.freeze({ times = { 0.1, 0.9 }, values = { 1, 0 } })

local function moves(curve: CarEntry.Curve?, standing: boolean): CarEntry.Clip
	return table.freeze({ seated = "", standing = if standing then "" else nil, duration = 1, door = curve })
end

local Door: CarEntry.Door = {
	direct = true,
	clips = table.freeze({
		OutsideOpen = moves(OPEN, true),
		GetIn = moves(SHUT, false),
		InsideClose = moves(SHUT, false),
		InsideOpen = moves(OPEN, false),
		GetOut = moves(nil, false),
		OutsideClose = moves(SHUT, true),
	}),
	-- Stand-ins until the DR458's own seated pose and door sounds exist: the SVJ's.
	seatedPose = SVJDoor.seatedPose,
	-- Outboard of the door's skin (0.58 m from the seat's centre plane), where the prompt is.
	mark = table.freeze({ right = -0.9, forward = 0 }),
	-- Clear of the collision box, mirrors included, by about half a metre.
	exitEnd = table.freeze({ at = 1, right = -1.35, forward = 0 }),
	sound = SVJDoor.sound,
}

return table.freeze(Door)
