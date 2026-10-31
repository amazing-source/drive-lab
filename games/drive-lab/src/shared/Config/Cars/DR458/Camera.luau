--!strict
--[[
	The DR458's own camera points (Config/CarCamera CarViews).
]]
local CarCamera = require("../../CarCamera")

local Camera: CarCamera.CarViews = table.freeze({
	-- The SVJ's eye offset, a stand-in until the DR458's seated pose exists.
	eye = table.freeze({ forward = 0, up = 0.07 }),
	-- EST: from the centre of mass, 0.13 m ahead of the windscreen's base and 0.17 m above it.
	hood = table.freeze({ forward = 1.45, up = 0.5 }),
	-- EST: the sequential box kicks harder as the manettino takes its aids off.
	shiftKick = table.freeze({ ["1"] = 0.6, ["2"] = 0.8, OFF = 1 }),
})

return Camera
