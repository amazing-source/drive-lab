--!strict
--[[
	The driver in the DR458, until the animators' own module lands (#108): the grip and the
	footwell are theirs for this cabin, the start-up paths and the hand gestures are keyed against
	its controls, and the grip meshes posed for its rim are kept in their own folder (the SVJ's
	stand in for them in a place without it).
]]
local Contract = require("../Contract")
local Gestures = require("./Gestures")
local StartupPaths = require("./StartupPaths")

local Driver: Contract.Driver = {
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
	gestures = Gestures,
}

return table.freeze(Driver)
