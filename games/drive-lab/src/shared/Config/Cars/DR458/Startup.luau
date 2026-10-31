--!strict
--[[
	The DR458's start, in the order docs/research/12_dr458_challenge_evo.md §2.5 infers (no Ferrari
	procedure was reachable): the right hand turns the red master key on the tunnel, lifts the
	guard and switches IGNITION on, waits for the display, then presses ENGINE START with a foot on
	the brake. The key, guard and switch are the binding's controls (Model), each turned through
	its travel; ENGINE START is pressed by the hand. The guard stays up and the key on, as a
	missile-switch guard does over a switch that is on.
]]
local CarEntry = require("../../CarEntry")
local Model = require("./Model")

local function travel(control: string): number
	local controls = Model.controls
	local hinge = controls and controls[control]
	assert(hinge and hinge.travel, `the DR458's binding has no travel for {control}`)
	return hinge.travel
end

local Startup: CarEntry.Startup = {
	-- EST, the animator's from the hand's reach in the cockpit: from the thigh to the key 0.28 m,
	-- from the key to the guard's edge 0.31 m. Each move arrives at `at`.
	moves = {
		{ control = "TunnelKey_Master", angle = travel("TunnelKey_Master"), move = 0.35, at = 1.0 },
		{ control = "PanelGuard_Ignition", angle = travel("PanelGuard_Ignition"), move = 0.25, at = 1.7 },
		{ control = "PanelSwitch_Ignition", angle = travel("PanelSwitch_Ignition"), move = 0.1, at = 1.95 },
	},
	pressAt = 2.4,
	wheelAt = 3.9,
	drivableAt = 4.1,
	-- The start-up is the F40 LM's (Audio's startup region), started at the press: the starter turns
	-- until it catches, then the revs settle from about 1,290 rpm to the car's idle by the hand-over,
	-- read off that recording's firing line; the starter's revs are EST, as its sound carries no
	-- engine order.
	catchAfter = 1.4,
	rpm = {
		times = { 0, 1.38, 1.55, 3.0, 3.5, 4.0, 4.3, 4.6, 5.0 },
		values = { 250, 250, 1290, 1284, 1236, 1208, 1087, 1026, 1000 },
	},
	-- As the SVJ's: the right foot holds the brake from the key until driving unlocks.
	brake = 0.6,
}

return Startup
