--!strict
--[[
	The camera optics in rain (Rules/RainOptics): a contact blur of at most a third of a pixel
	as drops land on the lens, and a very light far depth of field, both off in the cockpit. The
	blur is this module's own BlurEffect (the strongest blur in Lighting wins, so a menu's blur
	is never weakened); a DepthOfFieldEffect the place already has is driven rather than doubled,
	and every property written on it is put back on destroy. It also carries the motion blur of
	the car's speed and pull (Rules/MotionBlur), the one depth of field serving both.
]]
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.RainOptics)
local MotionBlur = require(ReplicatedStorage.Shared.Rules.MotionBlur)
local MotionBlurConfig = require(ReplicatedStorage.Shared.Config.MotionBlur)
local RainOptics = require(ReplicatedStorage.Shared.Rules.RainOptics)

type Saved = { enabled: boolean, far: number, near: number, distance: number, radius: number }

export type Optics = {
	blur: BlurEffect,
	focus: DepthOfFieldEffect,
	created: boolean,
	saved: Saved,
	pulse: number,
	-- The car's pull as a share of the acceleration blur, eased.
	pull: number,
}

local Optics = {}

function Optics.new(): Optics
	local blur = Instance.new("BlurEffect")
	blur.Name = "DriveLabRainBlur"
	blur.Size = 0
	blur.Enabled = false
	blur.Parent = Lighting
	local existing = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	local focus = existing or Instance.new("DepthOfFieldEffect")
	local saved = {
		enabled = focus.Enabled,
		far = focus.FarIntensity,
		near = focus.NearIntensity,
		distance = focus.FocusDistance,
		radius = focus.InFocusRadius,
	}
	if existing == nil then
		focus.Name = "DriveLabRainFocus"
		focus.Enabled = false
		focus.Parent = Lighting
	end
	return { blur = blur, focus = focus, created = existing == nil, saved = saved, pulse = 0, pull = 0 }
end

-- `landed` is how many drops hit the lens this frame; carDistance and carLength (studs) let
-- the chase view focus on the car, and speedKmh and longitudinalG are that car's.
function Optics.update(
	optics: Optics,
	dt: number,
	view: RainOptics.View,
	intensity: number,
	landed: number,
	carDistance: number?,
	carLength: number,
	speedKmh: number,
	longitudinalG: number
)
	optics.pulse = RainOptics.contact(RainOptics.decay(optics.pulse, dt, Config.BLUR), landed, Config.BLUR)
	local size = RainOptics.blurSize(view, optics.pulse, Config.BLUR)
	local blur = optics.blur
	-- Under a hundredth of a pixel the blur is switched off rather than drawn for nothing.
	local on = size >= 0.01
	if blur.Enabled ~= on then
		blur.Enabled = on
	end
	if on then
		blur.Size = size
	end
	local acceleration = MotionBlurConfig.ACCELERATION
	optics.pull =
		MotionBlur.follow(optics.pull, MotionBlur.pullShare(longitudinalG, acceleration), dt, acceleration)
	local near, far = MotionBlur.depth(view, speedKmh, optics.pull, MotionBlurConfig.SPEED, acceleration)
	local depth = RainOptics.depthOfField(view, intensity, near, far, carDistance, carLength, Config.FOCUS)
	local focus = optics.focus
	if focus.Enabled ~= depth.enabled then
		focus.Enabled = depth.enabled
	end
	if depth.enabled then
		focus.FarIntensity = depth.far
		focus.NearIntensity = depth.near
		focus.FocusDistance = depth.distance
		focus.InFocusRadius = depth.radius
	end
end

function Optics.destroy(optics: Optics)
	optics.blur:Destroy()
	local focus, saved = optics.focus, optics.saved
	if optics.created then
		focus:Destroy()
		return
	end
	focus.Enabled = saved.enabled
	focus.FarIntensity = saved.far
	focus.NearIntensity = saved.near
	focus.FocusDistance = saved.distance
	focus.InFocusRadius = saved.radius
end

return Optics
