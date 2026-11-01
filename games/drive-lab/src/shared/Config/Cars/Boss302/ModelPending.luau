--!strict
--[[
	Written by games/drive-lab/tools/car_binding.luau Boss302 from the car's 3D manifest: do not edit by hand, run the tool again.
]]
-- What the binding still lacks or estimates; a car joins the catalog once this is empty.
return {
	"cluster: no live display screen named",
	"gauges: the six Needle_* dials are not bound yet (the cluster's needles are a later field)",
	"the 3D model: its upload and the Studio import (this binding is from the promoted full manifest)",
	"the driver's shift animation (Shift.luau: the reach, release and foot timings)",
	"the remaining car entry: audio, camera, HUD, lights and the start-up",
}
