--!strict
--[[
	The driver in the Boss 302: an R6 at 1.15 in the Recaro, with the DR458's arms. The grip and the
	footwell are the animators' for this cabin (grip v1_a13_t18: 13 degrees above 3 o'clock, the
	thumbs on the spokes; footwell v2: every pedal hung from above, the floor's rise under each heel
	measured), the start-up paths turn the key with a lean of the torso, and the right hand takes
	the gear lever's knob through each shift (Shift.luau).
]]
local Contract = require("../Contract")
local Shift = require("./Shift")
local StartupPaths = require("./StartupPaths")

local Driver: Contract.Driver = {
	scale = 1.15,
	-- The DR458's drawn arms (studs at scale 1): the seat and wheel were placed for them.
	arms = table.freeze({ upper = 1.25, lower = 1.13 }),
	-- The right hand, from hand_grip.py (grip v1_a13_t18). Its posed meshes are in the Boss's upload
	-- batch; until they are in the place the SVJ's stand in.
	grip = table.freeze({
		meshes = "HandsBoss302",
		centre = table.freeze({ x = 0.8146, y = 0.2263, z = 0.2089 }),
		cuff = table.freeze({ x = 0.8558, y = 0.0999, z = 0.7793 }),
		wrist = table.freeze({ x = 0.8968, y = 0.151, z = 0.6281 }),
		forearm = table.freeze({ x = -0.1276, y = -0.2077, z = 0.9698 }),
		back = table.freeze({ x = 0.9596, y = 0.2215, z = 0.1736 }),
	}),
	-- The animator's footwell (footwell_config_v2), its hinges on the binding's pedal pivots and its
	-- travels the binding's.
	footwell = table.freeze({
		throttle = table.freeze({
			part = "Pedal_Throttle",
			hinge = table.freeze({ x = 0.1001, y = 0.0733, z = -0.9873 }),
			travel = 0.205,
			heel = table.freeze({ x = 0.0985, y = -0.2746, z = -0.6977 }),
			ball = table.freeze({ x = 0.0985, y = -0.1488, z = -0.8877 }),
			hangs = true,
			heelSlope = 0.132,
		}),
		brake = table.freeze({
			part = "Pedal_Brake",
			hinge = table.freeze({ x = -0.024, y = 0.0399, z = -1.039 }),
			travel = 0.21,
			heel = table.freeze({ x = 0.0034, y = -0.278, z = -0.6755 }),
			ball = table.freeze({ x = 0.0034, y = -0.1195, z = -0.8655 }),
			hangs = true,
			heelSlope = 0.141,
		}),
		clutch = table.freeze({
			part = "Pedal_Clutch",
			hinge = table.freeze({ x = -0.1569, y = 0.0399, z = -1.039 }),
			travel = 0.5,
			heel = table.freeze({ x = -0.119, y = -0.2794, z = -0.6685 }),
			ball = table.freeze({ x = -0.119, y = -0.1099, z = -0.8585 }),
			hangs = true,
			heelSlope = 0.143,
		}),
		footrest = table.freeze({
			heel = table.freeze({ x = -0.2, y = -0.281, z = -0.66 }),
			ball = table.freeze({ x = -0.2, y = -0.221, z = -0.86 }),
		}),
		kneeToward = table.freeze({
			right = table.freeze({ x = 0.34, y = 0.92, z = -0.2 }),
			left = table.freeze({ x = -0.5, y = 0.84, z = -0.19 }),
		}),
	}),
	startupPaths = StartupPaths,
	-- The drawn hands start where the entry's blocky hands end (the entry animator's hand_over,
	-- converted from studs to metres) and ease onto the resting pose over `seconds` (DriverSeat
	-- frame). A direct door seats the driver with no hand-over, so it plays once the clips do.
	handOver = table.freeze({
		seconds = 0.6,
		right = table.freeze({
			position = table.freeze({ x = 0.33041, y = 0.23461, z = -0.13594 }),
			rotation = table.freeze({ w = 0.976, x = 0.20667, y = -0.06711, z = 0.01421 }),
		}),
		left = table.freeze({
			position = table.freeze({ x = -0.1111, y = 0.22017, z = -0.14114 }),
			rotation = table.freeze({ w = 0.96767, x = 0.1777, y = 0.17606, z = -0.03233 }),
		}),
	}),
	shift = Shift,
}

return Driver
