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
	-- The start-up sound is the store recording (Audio's startup.sound), started at the press: its
	-- catch and revs follow that recording's firing order and end at the car's idle; the starter's
	-- revs are EST, as its sound carries no engine order.
	catchAfter = 0.71,
	rpm = {
		times = { 0, 0.70, 0.95, 1.15, 1.45, 1.65, 2.05, 2.45, 2.98 },
		values = { 250, 250, 2170, 2480, 2360, 2200, 1450, 1160, 1000 },
	},
	-- As the SVJ's: the right foot holds the brake from the key until driving unlocks.
	brake = 0.6,
}

return Startup
