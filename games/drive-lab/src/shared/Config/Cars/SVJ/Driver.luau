--!strict
--[[
	The driver in the SVJ: the hands' grip on its rim, the footwell, and the start-up paths keyed
	against its cabin.
]]
local Contract = require("../Contract")
local StartupPaths = require("./StartupPaths")

local Driver: Contract.Driver = {
	-- The right hand, from hand_grip.py's hands.json (run with --bar-tilt 10 --wrist-turn -10),
	-- gripping 25 degrees above 3 o'clock, clear of the spoke.
	grip = table.freeze({
		meshes = "Hands",
		centre = table.freeze({ x = 0.7092, y = 0.4279, z = 0.1923 }),
		cuff = table.freeze({ x = 0.7962, y = 0.2674, z = 0.7406 }),
		wrist = table.freeze({ x = 0.8266, y = 0.3252, z = 0.5895 }),
		forearm = table.freeze({ x = -0.0816, y = -0.2297, z = 0.9698 }),
		back = table.freeze({ x = 0.8925, y = 0.4162, z = 0.1736 }),
	}),
	footwell = table.freeze({
		-- Measured on the SVJ's interior mesh (tools/blender/footwell.py): an organ throttle hinged on
		-- the floor, the foot lying on its plate with the heel at the hinge; a brake hanging from
		-- under the dash, the heel on the floor behind it; a fixed footrest. 16 and 12 degrees of
		-- travel: 5.8 and 4.0 cm at the ball of the foot (measured on the rigged pedals in Studio).
		throttle = table.freeze({
			part = "Pedal_Throttle",
			hinge = table.freeze({ x = 0.1761, y = -0.2364, z = -0.8354 }),
			travel = -math.rad(16),
			heel = table.freeze({ x = 0.1761, y = -0.2275, z = -0.8354 }),
			ball = table.freeze({ x = 0.2044, y = -0.0482, z = -0.924 }),
		}),
		brake = table.freeze({
			part = "Pedal_Brake",
			hinge = table.freeze({ x = 0.0304, y = 0.0956, z = -0.9992 }),
			travel = math.rad(12),
			heel = table.freeze({ x = 0.0308, y = -0.2334, z = -0.794 }),
			ball = table.freeze({ x = 0.0308, y = -0.0486, z = -0.8705 }),
		}),
		footrest = table.freeze({
			heel = table.freeze({ x = -0.1012, y = -0.2352, z = -0.8776 }),
			ball = table.freeze({ x = -0.1012, y = -0.0519, z = -0.9575 }),
		}),
		-- The right knee rides the gap between the steering column and the centre console, below
		-- the dash; the left leans out toward the door, where there is room. Fitted against the
		-- cabin (tools/blender/leg_clearance.py): the right leg touches the console and the column
		-- (at most 0.6 cm into them on a pedal, 1.0 cm at worst crossing between them), as a real
		-- driver's knee rests on the tunnel; the knee has 1.7 cm under the dash at full braking.
		-- Bent straight out instead, the knee sat 5 cm inside the console. The left clears
		-- everything by 5 cm.
		kneeToward = table.freeze({
			right = table.freeze({ x = 0.17, y = 0.15, z = -0.4 }),
			left = table.freeze({ x = -0.58, y = 0.62, z = 0.008 }),
		}),
	}),
	startupPaths = StartupPaths,
}

return table.freeze(Driver)
