--!strict
--[[
	What tools/dr458_binding is told about the DR458 beyond its manifest (tools/ManifestBinding
	Settings): which parts play which role in the binding, and the few values the manifest does not
	carry, each with why.
]]
local ManifestBinding = require("./ManifestBinding")

local function names(prefix: string, count: number): { string }
	local list = table.create(count)
	for index = 1, count do
		list[index] = `{prefix}{index}`
	end
	return list
end

local Settings: ManifestBinding.Settings = {
	wheelGroups = { "Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR" },
	tyreSuffix = "_Tyre",
	calipers = { { "Caliper_FL" }, { "Caliper_FR" }, { "Caliper_RL" }, { "Caliper_RR" } },
	steeringWheel = "SteeringWheel",
	-- The driver's door turns on its skin's hinge; the other door does not open.
	assemblies = { Door_L = "Door_L_Skin", Door_R = ManifestBinding.BODY },
	door = { group = "Door_L", hinge = "Door_L_Skin" },
	-- The start-up's controls (Config/Cars/DR458/Startup): the master key, the ignition's guard and
	-- its switch. ENGINE START is pressed by the hand, not turned.
	controls = { "TunnelKey_Master", "PanelGuard_Ignition", "PanelSwitch_Ignition" },
	pedals = { "Pedal_Throttle", "Pedal_Brake" },
	-- The knob's positions in the order the manifest gives them, from its modelled pointer.
	modeKnob = { part = "WheelRotary_Manettino", modes = { "OFF", "1", "2" } },
	glazing = {
		"Glass_Windscreen",
		"Glass_RearScreen",
		"Glass_CabinRear",
		"Glass_Quarter_L",
		"Glass_Quarter_R",
		"Door_L_Glass",
		"Door_R_Glass",
	},
	screen = "Binnacle_Screen",
	exhaust = { "Exhaust_Outlet_L", "Exhaust_Outlet_R" },
	shiftLights = names("ShiftLight_", 8),
	panelLamps = { headlights = "PanelLamp_Light", rainLight = "PanelLamp_RainLight" },
	-- The race wheel is placed by the cockpit modeller, not adjusted on its column.
	steeringWheelLift = 0,
	-- The model is built on the physics' own wheel centres (3D lead, 2026-10-30).
	bodyRaise = 0,
	-- EST: the collision shell above kerb height; the race car rides 65 to 118 mm off the ground.
	hullClearance = 0.25,
	hipPoint = "Driver_HPoint",
	-- From the cockpit modeller (cockpit_points.json; photos 013 and 015, every control off): the
	-- key and the guard are modelled off and closed; the ignition toggle is modelled straight out,
	-- off when tipped down (+0.35) and on when up (-0.35).
	controlStates = {
		TunnelKey_Master = { rest = 0, other = math.pi / 2 },
		PanelGuard_Ignition = { rest = 0, other = 1.75 },
		PanelSwitch_Ignition = { rest = 0.35, other = -0.35 },
	},
}

return Settings
