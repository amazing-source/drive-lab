--!strict
--[[
	Motion blur with Roblox's post-processing (Rules/MotionBlur): a blur that grows with how fast
	the camera turns, and a depth of field that softens the world moving past the car with its
	speed and, more, while it pulls. The values here are the Full level of the player's
	motion-blur setting (Config/Settings); LEVELS scales all of them. ACCELERATION's intensity
	turns the pull's blur up or down in one place.
]]
local MotionBlur = require("../Rules/MotionBlur")

export type MotionBlurConfig = {
	ROTATION: MotionBlur.Rotation,
	SPEED: MotionBlur.Speed,
	ACCELERATION: MotionBlur.Acceleration,
	-- The id of the setting that picks a level, and each of its options' scale.
	SETTING: string,
	LEVELS: { [string]: number },
}

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
		off = 0.05,
	}),
	-- km/h: the depth of field's intensity, 0 under `from`, full from `to`. In the cockpit and hood
	-- views a far blur over about 0.2 smears the bright sky over the road and reads as fog, not
	-- speed (edit-mode captures), so their speed and pull blurs together stay under it.
	SPEED = table.freeze({ from = 80, to = 300, near = 0.45, far = 0.05, exponent = 1.2 }),
	-- Strong blur reads slower, not faster (Holm, Skovhus and Kraus 2017), so the pull's blur is
	-- sized to be plain at a full-throttle start and gone by cruising: full from 0.8 g, which the
	-- cars pull only in the first gears, rising in a tenth of a second and fading over a third.
	ACCELERATION = table.freeze({
		intensity = 1,
		-- "FullScreen" draws it as one blur over the whole view instead, to compare in a playtest.
		style = "DepthOfField" :: MotionBlur.PullStyle,
		fromG = 0.15,
		toG = 0.8,
		exponent = 1,
		rise = 0.08,
		fall = 0.35,
		off = 0.02,
		near = 0.5,
		far = 0.3,
		cabin = 0.15,
		fullScreen = 3,
	}),
	SETTING = "MotionBlur",
	-- Light, the default, is a third of every blur; Off draws none.
	LEVELS = table.freeze({ Off = 0, Light = 1 / 3, Full = 1 }),
})

return Config
