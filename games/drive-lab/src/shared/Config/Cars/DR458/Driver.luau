--!strict
--[[
	The driver in the DR458: an R6 at 1.15 in the race bucket, its clips and seated pose authored
	at that scale (Door.luau). The grip and the footwell are the animators' for this cabin, the
	start-up paths and the hand gestures are keyed against its controls, and the grip meshes posed
	for its rim are kept in their own folder (the SVJ's stand in for them in a place without it).
]]
local Contract = require("../Contract")
local Gestures = require("./Gestures")
local StartupPaths = require("./StartupPaths")

local Driver: Contract.Driver = {
	scale = 1.15,
	-- The drawn arms (studs at scale 1), sized for this wheel at this scale (seated_D_v1).
	arms = table.freeze({ upper = 1.25, lower = 1.13 }),
	-- The right hand, from hand_grip.py (grip v9_a10: 10 degrees above 3 o'clock, the thumb over the
	-- spoke, bar tilt 10, wrist turn -10).
	grip = table.freeze({
		meshes = "HandsDR458",
		centre = table.freeze({ x = 0.8024, y = 0.1708, z = 0.2028 }),
		cuff = table.freeze({ x = 0.81, y = 0.046, z = 0.7702 }),
		wrist = table.freeze({ x = 0.8533, y = 0.095, z = 0.619 }),
		forearm = table.freeze({ x = -0.1383, y = -0.2007, z = 0.9698 }),
		back = table.freeze({ x = 0.9698, y = 0.171, z = 0.1736 }),
	}),
	-- The animator's footwell (footwell_v2), its hinges on the binding's pedal pivots and its
	-- travels the binding's.
	footwell = table.freeze({
		throttle = table.freeze({
			part = "Pedal_Throttle",
			hinge = table.freeze({ x = 0.2383, y = -0.1765, z = -0.8949 }),
			travel = -0.18,
			heel = table.freeze({ x = 0.2423, y = -0.1693, z = -0.7499 }),
			ball = table.freeze({ x = 0.2423, y = -0.0644, z = -0.9244 }),
		}),
		brake = table.freeze({
			part = "Pedal_Brake",
			hinge = table.freeze({ x = 0.0983, y = 0.2585, z = -0.9999 }),
			travel = 0.1,
			heel = table.freeze({ x = 0.0983, y = -0.1949, z = -0.7499 }),
			ball = table.freeze({ x = 0.0983, y = -0.0263, z = -0.9048 }),
		}),
		footrest = table.freeze({
			heel = table.freeze({ x = -0.0857, y = -0.1938, z = -0.6699 }),
			ball = table.freeze({ x = -0.0857, y = -0.1746, z = -0.8599 }),
		}),
		kneeToward = table.freeze({
			right = table.freeze({ x = 0, y = 0.9, z = -0.3 }),
			left = table.freeze({ x = -0.3, y = 0.9, z = -0.3 }),
		}),
	}),
	startupPaths = StartupPaths,
	-- The drawn hands start where the entry's blocky hands end and ease onto the resting pose over
	-- `seconds` (metres, DriverSeat frame).
	handOver = table.freeze({
		seconds = 0.6,
		right = table.freeze({
			position = table.freeze({ x = 0.19835, y = 0.18843, z = -0.04913 }),
			rotation = table.freeze({ w = 0.97773, x = 0.20689, y = 0.03443, z = -0.00729 }),
		}),
		left = table.freeze({
			position = table.freeze({ x = -0.26627, y = 0.34659, z = -0.08182 }),
			rotation = table.freeze({ w = 0.981, x = 0.18948, y = 0.04092, z = -0.0079 }),
		}),
	}),
	gestures = Gestures,
}

return table.freeze(Driver)
