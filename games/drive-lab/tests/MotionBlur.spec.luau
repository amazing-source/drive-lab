--!strict
local Config = require("../src/shared/Config/MotionBlur")
local MotionBlur = require("../src/shared/Rules/MotionBlur")
local RainOptics = require("../src/shared/Rules/RainOptics")
local Settings = require("../src/shared/Config/Settings")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local ROTATION: MotionBlur.Rotation =
	{ from = 120, to = 480, max = 6, exponent = 1.5, rise = 0.03, fall = 0.08, cut = 45, off = 0.05 }
local SPEED: MotionBlur.Speed = { from = 80, to = 300, near = 0.45, far = 0.15, exponent = 1.2 }
local ACCELERATION: MotionBlur.Acceleration = {
	intensity = 1,
	style = "DepthOfField",
	fromG = 0.2,
	toG = 0.8,
	exponent = 1,
	rise = 0.1,
	fall = 0.4,
	off = 0.02,
	near = 0.5,
	far = 0.4,
	cabin = 0.2,
	fullScreen = 3,
}

local function with(overrides: { [string]: any }): MotionBlur.Acceleration
	local copy: { [string]: any } = table.clone(ACCELERATION :: any)
	for key, value in overrides do
		copy[key] = value
	end
	return copy :: any
end

describe("MotionBlur", function()
	it("reads a turn as degrees a second, and a jump past the cut as no motion", function()
		expect(MotionBlur.turnRate(5, 1 / 60, 45)).toBeNear(300, 1e-9)
		expect(MotionBlur.turnRate(-5, 1 / 60, 45)).toBeNear(300, 1e-9)
		expect(MotionBlur.turnRate(90, 1 / 60, 45)).toBe(nil)
		expect(MotionBlur.turnRate(5, 0, 45)).toBe(nil)
		expect(MotionBlur.turnRate(0 / 0, 1 / 60, 45)).toBe(nil)
	end)

	it("keeps ordinary turns sharp and blurs a fast one up to its cap", function()
		expect(MotionBlur.rotationSize(60, ROTATION, 1)).toBe(0)
		expect(MotionBlur.rotationSize(120, ROTATION, 1)).toBe(0)
		expect(MotionBlur.rotationSize(300, ROTATION, 1)).toBeNear(6 * 0.5 ^ 1.5, 1e-12)
		expect(MotionBlur.rotationSize(480, ROTATION, 1)).toBe(6)
		expect(MotionBlur.rotationSize(5000, ROTATION, 1)).toBe(6)
		expect(MotionBlur.rotationSize(0 / 0, ROTATION, 1)).toBe(0)
	end)

	it("rises quicker than it falls, by half each half-life at any frame rate", function()
		expect(MotionBlur.follow(0, 4, 0.03, ROTATION)).toBeNear(2, 1e-12)
		expect(MotionBlur.follow(4, 0, 0.08, ROTATION)).toBeNear(2, 1e-12)
		local stepped = 0
		for _ = 1, 4 do
			stepped = MotionBlur.follow(stepped, 4, 0.0075, ROTATION)
		end
		expect(stepped).toBeNear(MotionBlur.follow(0, 4, 0.03, ROTATION), 1e-12)
		expect(MotionBlur.follow(3, 0, -1, ROTATION)).toBe(3)
	end)

	it("blurs the near road from a speed, either way, up to its cap", function()
		expect(MotionBlur.speedNear(50, SPEED)).toBe(0)
		expect(MotionBlur.speedNear(80, SPEED)).toBe(0)
		expect(MotionBlur.speedNear(190, SPEED)).toBeNear(0.45 * 0.5 ^ 1.2, 1e-12)
		expect(MotionBlur.speedNear(-190, SPEED)).toBeNear(0.45 * 0.5 ^ 1.2, 1e-12)
		expect(MotionBlur.speedNear(400, SPEED)).toBe(0.45)
		expect(MotionBlur.speedNear(0 / 0, SPEED)).toBe(0)
		expect(MotionBlur.speedFar(190, SPEED)).toBeNear(0.15 * 0.5 ^ 1.2, 1e-12)
		expect(MotionBlur.speedFar(400, SPEED)).toBe(0.15)
	end)

	it("reads a pull from its start to its full g, none braking or coasting", function()
		expect(MotionBlur.pullShare(-1, ACCELERATION)).toBe(0)
		expect(MotionBlur.pullShare(0, ACCELERATION)).toBe(0)
		expect(MotionBlur.pullShare(0.2, ACCELERATION)).toBe(0)
		expect(MotionBlur.pullShare(0.5, ACCELERATION)).toBeNear(0.5, 1e-12)
		expect(MotionBlur.pullShare(0.8, ACCELERATION)).toBe(1)
		expect(MotionBlur.pullShare(3, ACCELERATION)).toBe(1)
		expect(MotionBlur.pullShare(0 / 0, ACCELERATION)).toBe(0)
		expect(MotionBlur.pullShare(0.5, with({ exponent = 2 }))).toBeNear(0.25, 1e-12)
	end)

	it("eases the pull in quicker than out, by half each half-life at any frame rate", function()
		expect(MotionBlur.follow(0, 1, 0.1, ACCELERATION)).toBeNear(0.5, 1e-12)
		expect(MotionBlur.follow(1, 0, 0.4, ACCELERATION)).toBeNear(0.5, 1e-12)
		local stepped = 0
		for _ = 1, 6 do
			stepped = MotionBlur.follow(stepped, 1, 0.1 / 6, ACCELERATION)
		end
		expect(stepped).toBeNear(0.5, 1e-12)
	end)

	it("blurs the road before the car and the world past it in the chase view, with the pull", function()
		local near, far = MotionBlur.depth("Chase", 50, 1, SPEED, ACCELERATION, 1)
		expect(near).toBeNear(0.5, 1e-12)
		expect(far).toBeNear(0.4, 1e-12)
		near, far = MotionBlur.depth("Chase", 190, 0.5, SPEED, ACCELERATION, 1)
		expect(near).toBeNear(MotionBlur.speedNear(190, SPEED) + 0.25, 1e-12)
		expect(far).toBeNear(0.2, 1e-12)
		near, far = MotionBlur.depth("Chase", 190, 0, SPEED, ACCELERATION, 1)
		expect(near).toBeNear(MotionBlur.speedNear(190, SPEED), 1e-12)
		expect(far).toBe(0)
	end)

	it("blurs only past the cabin in the cockpit and hood views, never on foot", function()
		for _, view in { "Cockpit", "Hood" } do
			local near, far = MotionBlur.depth(view, 50, 1, SPEED, ACCELERATION, 1)
			expect(near).toBe(0)
			expect(far).toBeNear(0.2, 1e-12)
			near, far = MotionBlur.depth(view, 400, 0, SPEED, ACCELERATION, 1)
			expect(near).toBe(0)
			expect(far).toBeNear(0.15, 1e-12)
		end
		local near, far = MotionBlur.depth("OnFoot", 400, 1, SPEED, ACCELERATION, 1)
		expect(near).toBe(0)
		expect(far).toBe(0)
	end)

	it("scales the pull's blur with its one intensity, never past full", function()
		local near, far = MotionBlur.depth("Chase", 50, 1, SPEED, with({ intensity = 0 }), 1)
		expect(near).toBe(0)
		expect(far).toBe(0)
		near, far = MotionBlur.depth("Chase", 50, 0.5, SPEED, with({ intensity = 2 }), 1)
		expect(near).toBeNear(0.5, 1e-12)
		expect(far).toBeNear(0.4, 1e-12)
		near, far = MotionBlur.depth("Chase", 400, 1, SPEED, with({ intensity = 5 }), 1)
		expect(near).toBe(1)
		expect(far).toBe(1)
		near, far = MotionBlur.depth("Cockpit", 50, 0.5, SPEED, with({ intensity = 2 }), 1)
		expect(far).toBeNear(0.2, 1e-12)
		near, far = MotionBlur.depth("Cockpit", 50, 0 / 0, SPEED, ACCELERATION, 1)
		expect(far).toBe(0)
	end)

	it("counts a pull under its floor as none, so the blur switches off after a pull", function()
		local near, far = MotionBlur.depth("Chase", 50, 0.01, SPEED, ACCELERATION, 1)
		expect(near).toBe(0)
		expect(far).toBe(0)
		expect(MotionBlur.pulseSize(0.01, with({ style = "FullScreen" }), 1)).toBe(0)
		local pull = 1
		for _ = 1, 3 * 60 do
			pull = MotionBlur.follow(pull, MotionBlur.pullShare(0, ACCELERATION), 1 / 60, ACCELERATION)
		end
		expect(pull > 0).toBe(true)
		near, far = MotionBlur.depth("Cockpit", 50, pull, SPEED, ACCELERATION, 1)
		expect(near).toBe(0)
		expect(far).toBe(0)
	end)

	it("draws the pull's blur in one style only: the depth of field or the full screen", function()
		expect(MotionBlur.pulseSize(1, ACCELERATION, 1)).toBe(0)
		local full = with({ style = "FullScreen" })
		expect(MotionBlur.pulseSize(1, full, 1)).toBe(3)
		expect(MotionBlur.pulseSize(0.5, with({ style = "FullScreen", intensity = 2 }), 1)).toBeNear(3, 1e-12)
		expect(MotionBlur.pulseSize(0 / 0, full, 1)).toBe(0)
		local near, far = MotionBlur.depth("Chase", 190, 1, SPEED, full, 1)
		expect(near).toBeNear(MotionBlur.speedNear(190, SPEED), 1e-12)
		expect(far).toBe(0)
	end)
end)

describe("MotionBlur config", function()
	local acceleration = Config.ACCELERATION

	-- Measured on edit-mode captures: a far blur of 0.25 already turned the outside to fog from
	-- the cockpit; 0.15 kept the horizon (68 to 80 % of its sharpness, the cabin untouched); in the
	-- chase view 0.3 softened the world plainly with the car sharp.
	local COCKPIT_FOG = 0.2

	it("blurs plainly at a full-throttle start: the chase view's world, the cockpit's outside", function()
		local pull = MotionBlur.pullShare(1, acceleration)
		expect(pull).toBe(1)
		local _, far = MotionBlur.depth("Chase", 40, pull, Config.SPEED, acceleration, 1)
		expect(far >= 0.25).toBe(true)
		local _, cabin = MotionBlur.depth("Cockpit", 40, pull, Config.SPEED, acceleration, 1)
		expect(cabin >= 0.12).toBe(true)
	end)

	it("never fogs the cockpit or the hood view, at any speed and pull", function()
		for _, view in { "Cockpit", "Hood" } do
			for kmh = 0, 400, 20 do
				local _, far = MotionBlur.depth(view, kmh, 1, Config.SPEED, acceleration, 1)
				expect(far <= COCKPIT_FOG).toBe(true)
			end
		end
	end)

	it("leaves a steady cruise to the speed's lighter blur", function()
		expect(MotionBlur.pullShare(0.1, acceleration)).toBe(0)
		local _, far = MotionBlur.depth("Chase", 400, 0, Config.SPEED, acceleration, 1)
		expect(far).toBe(0)
	end)

	it("starts in the depth of field style, the full screen kept for comparison", function()
		expect(acceleration.style).toBe("DepthOfField")
		expect(acceleration.fullScreen > 0).toBe(true)
	end)
end)

describe("MotionBlur levels", function()
	local LEVELS = { Off = 0, Light = 1 / 3, Full = 1 }
	local FOCUS: RainOptics.Focus =
		{ far = 0.12, radius = 40, hood = 60, onFoot = 30, margin = 10, nearMargin = 2, body = 6 }

	it("reads a level's scale, the full blur for a choice it does not know", function()
		expect(MotionBlur.level(LEVELS, "Off")).toBe(0)
		expect(MotionBlur.level(LEVELS, "Light")).toBeNear(1 / 3, 1e-12)
		expect(MotionBlur.level(LEVELS, "Full")).toBe(1)
		expect(MotionBlur.level(LEVELS, "Bogus")).toBe(1)
		expect(MotionBlur.level(LEVELS, nil)).toBe(1)
		expect(MotionBlur.level({ Odd = -2 }, "Odd")).toBe(0)
	end)

	it("scales every blur by the level: the turn, the speed, the pull and the full-screen style", function()
		local third = 1 / 3
		expect(MotionBlur.rotationSize(300, ROTATION, third)).toBeNear(
			MotionBlur.rotationSize(300, ROTATION, 1) / 3,
			1e-12
		)
		for _, view in { "Chase", "Cockpit", "Hood" } do
			for _, case in { { 190, 0 }, { 60, 0.8 }, { 250, 0.5 } } do
				local fullNear, fullFar = MotionBlur.depth(view, case[1], case[2], SPEED, ACCELERATION, 1)
				local near, far = MotionBlur.depth(view, case[1], case[2], SPEED, ACCELERATION, third)
				expect(near).toBeNear(fullNear / 3, 1e-12)
				expect(far).toBeNear(fullFar / 3, 1e-12)
			end
		end
		local full = with({ style = "FullScreen" })
		expect(MotionBlur.pulseSize(0.6, full, third)).toBeNear(MotionBlur.pulseSize(0.6, full, 1) / 3, 1e-12)
	end)

	it("draws nothing at Off: no turn blur, no depth of field, no full-screen pulse", function()
		expect(MotionBlur.rotationSize(5000, ROTATION, 0)).toBe(0)
		expect(MotionBlur.blurOn(0, ROTATION)).toBe(false)
		expect(MotionBlur.pulseSize(1, with({ style = "FullScreen" }), 0)).toBe(0)
		for _, view in { "Chase", "Cockpit", "Hood" } :: { RainOptics.View } do
			local near, far = MotionBlur.depth(view, 400, 1, SPEED, ACCELERATION, 0)
			expect(near).toBe(0)
			expect(far).toBe(0)
			expect(RainOptics.depthOfField(view, 0, near, far, 32, 26, FOCUS).enabled).toBe(false)
		end
	end)

	it("keeps the rain's own blur at Off: rain is weather, not motion blur", function()
		local near, far = MotionBlur.depth("Chase", 400, 1, SPEED, ACCELERATION, 0)
		local depth = RainOptics.depthOfField("Chase", 1, near, far, 32, 26, FOCUS)
		expect(depth.enabled).toBe(true)
		expect(depth.far).toBeNear(FOCUS.far, 1e-12)
		expect(depth.near).toBe(0)
	end)

	it("switches the turn blur's effect off under its floor and on from it", function()
		expect(MotionBlur.blurOn(0.049, ROTATION)).toBe(false)
		expect(MotionBlur.blurOn(0.05, ROTATION)).toBe(true)
		expect(MotionBlur.blurOn(0 / 0, ROTATION)).toBe(false)
	end)
end)

describe("MotionBlur levels config", function()
	local setting
	for _, entry in Settings.LIST do
		if entry.id == Config.SETTING then
			setting = entry
		end
	end

	it("gives every option of the motion-blur setting a level, Light by default", function()
		expect(setting ~= nil).toBe(true)
		for _, option in setting.options do
			expect(Config.LEVELS[option] ~= nil).toBe(true)
		end
		expect(setting.default).toBe("Light")
	end)

	it("makes Light a third of Full, Full today's blur and Off none", function()
		expect(Config.LEVELS.Full).toBe(1)
		expect(Config.LEVELS.Light).toBeNear(1 / 3, 1e-12)
		expect(Config.LEVELS.Off).toBe(0)
	end)
end)
