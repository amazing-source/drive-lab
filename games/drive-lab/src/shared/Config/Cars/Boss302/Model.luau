--!strict
--[[
	Written by games/drive-lab/tools/car_binding.luau Boss302 from the car's 3D manifest: do not edit by hand, run the tool again.
]]
local Binding = require("../Binding")

local Model: Binding.CarModel = {
	wheels = { "Wheel_FL_Tyre", "Wheel_FR_Tyre", "Wheel_RL_Tyre", "Wheel_RR_Tyre" },
	calipers = { { "Caliper_FL" }, { "Caliper_FR" }, { "Caliper_RL" }, { "Caliper_RR" } },
	steeringWheel = "SteeringWheel",
	steeringWheelLift = 0,
	seat = { forward = -0.3398, right = -0.3746, up = 0.0657 },
	hullClearance = 0.25,
	bodyRaise = 0,
	cluster = { forward = 0, right = 0, up = 0, width = 0, height = 0, tilt = 0 },
	glazing = {
		"Glass_Windscreen",
		"Glass_RearScreen",
		"Glass_Quarter_L",
		"Glass_Quarter_R",
		"Door_L_Glass",
		"Door_R_Glass",
	},
	windshield = {
		{ forward = -0.0102, right = -0.5863, up = 0.7428 },
		{ forward = -0.0102, right = 0.5863, up = 0.7428 },
		{ forward = 0.4735, right = 0.636, up = 0.4709 },
		{ forward = 0.4735, right = -0.636, up = 0.4709 },
	},
	door = {
		pivot = { forward = 0.4521, right = -0.8797, up = 0.142 },
		axis = { forward = 0, right = 0, up = -1 },
		parts = { "Door_L_Card", "Door_L_Glass", "Door_L_Mirror", "Door_L_Skin" },
		openAngle = 1.0367,
	},
	controls = {
		Key_Ignition = {
			part = "Key_Ignition",
			pivot = { forward = 0.1214, right = -0.2797, up = 0.2493 },
			axis = { forward = 0.36012, right = -0.93167, up = 0.04797 },
			travel = 1.5708,
		},
	},
	pedals = {
		{
			part = "Pedal_Throttle",
			pivot = { forward = 0.6475, right = -0.2745, up = 0.139 },
			axis = { forward = 0, right = 1, up = 0 },
			travel = 0.205,
		},
		{
			part = "Pedal_Brake",
			pivot = { forward = 0.6992, right = -0.3986, up = 0.1056 },
			axis = { forward = 0, right = 1, up = 0 },
			travel = 0.21,
		},
		{
			part = "Pedal_Clutch",
			pivot = { forward = 0.6992, right = -0.5315, up = 0.1056 },
			axis = { forward = 0, right = 1, up = 0 },
			travel = 0.5,
		},
	},
	parents = {
		SteeringWheel_Hub = "SteeringWheel",
		SteeringWheel_Rim = "SteeringWheel",
		SteeringWheel_Spokes = "SteeringWheel",
		Wheel_FL = "Wheel_FL_Tyre",
		Wheel_FR = "Wheel_FR_Tyre",
		Wheel_RL = "Wheel_RL_Tyre",
		Wheel_RR = "Wheel_RR_Tyre",
	},
	steeringHub = {
		pivot = { forward = 0.0179, right = -0.3713, up = 0.3649 },
		axis = { forward = -0.91122, right = 0, up = 0.41192 },
	},
	exhaustOutlets = {
		{
			centre = { forward = -2.5593, right = -0.5867, up = -0.1894 },
			axis = { forward = -1, right = 0, up = 0 },
			diameter = 0.1077,
		},
		{
			centre = { forward = -2.5593, right = 0.5867, up = -0.1894 },
			axis = { forward = -1, right = 0, up = 0 },
			diameter = 0.1077,
		},
	},
	shifter = {
		part = "Shifter_Lever",
		pivot = { forward = -0.0499, right = 0, up = 0.0376 },
		axisFore = { forward = 0, right = -1, up = 0 },
		axisSide = { forward = 1, right = 0, up = 0 },
		gates = {
			["1"] = { side = -0.15708, fore = 0.21817 },
			["2"] = { side = -0.15708, fore = -0.21817 },
			["3"] = { side = 0, fore = 0.21817 },
			["4"] = { side = 0, fore = -0.21817 },
			["5"] = { side = 0.15708, fore = 0.21817 },
			["6"] = { side = 0.15708, fore = -0.21817 },
			N = { side = 0, fore = 0 },
			R = { side = -0.31416, fore = 0.21817 },
		},
		knob = { forward = -0.0652, right = 0.0076, up = 0.175 },
		push = 0.008,
	},
}

return Model
