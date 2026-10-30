--!strict
--[[
	The SVJ's own camera points (Config/CarCamera CarViews).
]]
local CarCamera = require("../../CarCamera")

local Camera: CarCamera.CarViews = table.freeze({
	-- The cockpit eye, metres ahead of the head's centre. Behind it: the seated R6 driver's head
	-- already touches the headrest, so the eye moves back inside the hidden head to sit 0.38 m
	-- from the wheel (0.24 m at +0.08, the owner found the view too close, 2026-10-27). And raised,
	-- so the eye looks down over the forearms onto the hands on the rim; level with the forearms,
	-- they hid the hands.
	eye = table.freeze({ forward = 0, up = 0.07 }),
	-- From the centre of mass, along the car: just ahead of the windscreen, above the bonnet.
	hood = table.freeze({ forward = 1.15, up = 0.62 }),
	-- The ISR's 50 ms shifts are harsh in Corsa.
	shiftKick = table.freeze({ Strada = 0.35, Sport = 0.7, Corsa = 1 }),
})

return Camera
