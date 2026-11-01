--!strict
--[[
	The Boss 302's own camera points (Config/CarCamera CarViews).
]]
local CarCamera = require("../../CarCamera")

local Camera: CarCamera.CarViews = table.freeze({
	-- The SVJ's eye offset from the head, a stand-in until the Boss's seated pose is in the place.
	eye = table.freeze({ forward = 0, up = 0.07 }),
	-- EST: as the DR458's, 0.13 m ahead of the windscreen's base (the binding's lower corners, 0.47 m
	-- ahead of the centre of mass, 0.47 m up) and 0.17 m above it.
	hood = table.freeze({ forward = 0.6, up = 0.64 }),
	-- EST: the six-speed's shifts kick harder as TracKey sharpens the car, as the DR458's modes do.
	shiftKick = table.freeze({ Normal = 0.6, Sport = 0.8, TracKey = 1 }),
})

return Camera
