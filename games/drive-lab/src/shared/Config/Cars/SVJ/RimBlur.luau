--!strict
--[[
	The SVJ's ten-spoke rims, for the rim blur (Config/RimBlur Rims).
]]
local RimBlur = require("../../RimBlur")

local Rims: RimBlur.Rims = table.freeze({
	-- About 17 to 41 km/h on the front tyres (0.322 m), 19 to 44 on the rear (0.346 m). Ends
	-- under 40 rad/s: ten spokes look still at 37.7 rad/s at 60 FPS.
	spin = table.freeze({ from = 15, to = 35 }),
	-- rim_blur.py, 2026-10-28: the coverage round the front and rear rims' mid radius has its
	-- strongest harmonic at 10, and none at 5.
	repeats = 10,
})

return Rims
