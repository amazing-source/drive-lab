--!strict
--[[
	Written by games/drive-lab/tools/car_binding.luau Boss302 from the car's 3D manifest: do not edit by hand, run the tool again.
]]
-- What the binding still lacks or estimates; a car joins the catalog once this is empty.
return {
	"displays (MessageCentre): the manifest has no Screen_MessageCentre",
	"displays (PodReadout): the manifest has no Screen_PodReadout",
	"needles: the manifest has no Needle_Fuel",
	"needles: the manifest has no Needle_Oil",
	"needles: the manifest has no Needle_Temp",
	"needles: the manifest has no Needle_Water",
	"the 3D model: its upload and the Studio import (this binding is from the promoted full manifest)",
	"the driver's shift animation (Shift.luau: the reach, release and foot timings)",
	"the remaining car entry: audio, camera, HUD, lights and the start-up",
}
