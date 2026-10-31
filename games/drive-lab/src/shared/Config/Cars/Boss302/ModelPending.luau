--!strict
--[[
	What the Boss 302's model binding still lacks (issue #209): the car joins the catalog once this
	is empty. Its physics (Physics.luau) runs offline in tools/DriveSim meanwhile.
]]
return {
	"the 3D model and its manifest (the binding's parts, wheels, seat and lights)",
	"the cockpit's binding: the shifter's knob and gates, the clutch pedal, the steering wheel",
	"the driver's shift animation (Shift.luau: the reach, release and foot timings)",
	"the remaining car entry: audio, camera, HUD, lights and the start-up",
}
