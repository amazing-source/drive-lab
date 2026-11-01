--!strict
--[[
	What tools/car_binding is told about the Boss 302 beyond its manifest (tools/ManifestBinding
	Settings): the parts and points by the house convention, which the 3D artist's full manifest
	names. Whatever the manifest lacks is listed as pending, and the car stays out of the catalog
	until none is.
]]
local ManifestBinding = require("./ManifestBinding")

local Settings: ManifestBinding.Settings = {
	wheelGroups = { "Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR" },
	tyreSuffix = "_Tyre",
	calipers = { { "Caliper_FL" }, { "Caliper_FR" }, { "Caliper_RL" }, { "Caliper_RR" } },
	steeringWheel = "SteeringWheel",
	-- The key rides the steering column, fixed to the body in the game; the driver's door turns on its
	-- skin's hinge.
	assemblies = {
		SteeringColumn = ManifestBinding.BODY,
		Door_L = "Door_L_Skin",
		Door_R = ManifestBinding.BODY,
	},
	door = { group = "Door_L", hinge = "Door_L_Skin" },
	-- The key the start-up turns (Config/Cars/Boss302/Startup).
	controls = { "Key_Ignition" },
	-- A manual's three pedals: the clutch is the left foot's (Controllers/DriverLegs).
	pedals = { "Pedal_Throttle", "Pedal_Brake", "Pedal_Clutch" },
	glazing = {
		"Glass_Windscreen",
		"Glass_RearScreen",
		"Glass_Quarter_L",
		"Glass_Quarter_R",
		"Door_L_Glass",
		"Door_R_Glass",
	},
	exhaust = { "Exhaust_Outlet_L", "Exhaust_Outlet_R" },
	steeringWheelLift = 0,
	bodyRaise = 0,
	-- EST: as the DR458, the collision shell above kerb height.
	hullClearance = 0.25,
	hipPoint = "Driver_HPoint",
	windshield = {
		"Windshield_TopLeft",
		"Windshield_TopRight",
		"Windshield_BottomRight",
		"Windshield_BottomLeft",
	},
	-- The key is modelled at OFF; its other end is the cylinder's START detent (the manifest's last).
	controlStates = {
		Key_Ignition = { rest = 0, other = math.pi / 2 },
	},
	shifter = "Shifter_Lever",
}

return Settings
