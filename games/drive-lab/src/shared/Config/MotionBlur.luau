--!strict
--[[
	Motion blur with Roblox's post-processing (the owner asked for "le blur type motion blur",
	2026-10-28). A blur that grows with how fast the camera turns, and in the chase view the road
	between the camera and the car blurred the faster the car goes (Rules/MotionBlur). Seeds, for
	the owner's eye in a playtest.
]]
local MotionBlur = require("../Rules/MotionBlur")

export type MotionBlurConfig = { ROTATION: MotionBlur.Rotation, SPEED: MotionBlur.Speed }

local Config: MotionBlurConfig = table.freeze({
	-- Degrees a second: no blur under `from`, `max` pixels from `to`. Ordinary turns stay sharp;
	-- a flick of the camera or a spin blurs. A jump wider than `cut` degrees in one frame is a
	-- camera cut and never blurs.
	ROTATION = table.freeze({
		from = 120,
		to = 480,
		max = 6,
		exponent = 1.5,
		rise = 0.03,
		fall = 0.08,
		cut = 45,
	}),
	-- km/h: the near depth of field's intensity, 0 under `from`, `near` from `to`.
	SPEED = table.freeze({ from = 80, to = 300, near = 0.45, exponent = 1.2 }),
})

return Config
