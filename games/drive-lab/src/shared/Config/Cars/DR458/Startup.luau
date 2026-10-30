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
	-- EST times, agreed with the animator, who keys the hands to them.
	moves = {
		{ control = "TunnelKey_Master", angle = travel("TunnelKey_Master"), move = 0.35, at = 0.3 },
		{ control = "PanelGuard_Ignition", angle = travel("PanelGuard_Ignition"), move = 0.25, at = 1.05 },
		{ control = "PanelSwitch_Ignition", angle = travel("PanelSwitch_Ignition"), move = 0.1, at = 1.45 },
	},
	pressAt = 2.4,
	wheelAt = 3.9,
	drivableAt = 4.1,
	-- Measured by the audio agent on the start-up the pack plays (the Ferrari 360 recording,
	-- events.wav 0.5 to 4.85 s, from the press): the starter from 0.2 s, the catch at 1.43 s, the
	-- flare's peak of 1,810 rpm at 2.0 s, a fast idle of 1,430 at 2.75 s, settled near 1,050 from
	-- 3.7 s. The 200 rpm while cranking and the last point, the physics' 1,000 rpm idle, are theirs.
	catchAfter = 1.43,
	rpm = {
		times = { 0, 0.2, 1.4, 1.55, 1.67, 1.8, 2.0, 2.4, 2.75, 3.0, 3.35, 3.7, 4.35 },
		values = { 0, 200, 200, 1100, 1480, 1680, 1810, 1580, 1430, 1310, 1130, 1060, 1000 },
	},
	-- As the SVJ's: the right foot holds the brake from the key until driving unlocks.
	brake = 0.6,
}

return Startup
