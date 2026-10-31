--!strict
local Config = require("../src/shared/Config/MotionBlur")
local MotionBlur = require("../src/shared/Rules/MotionBlur")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local ROTATION: MotionBlur.Rotation =
	{ from = 120, to = 480, max = 6, exponent = 1.5, rise = 0.03, fall = 0.08, cut = 45 }
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
		expect(MotionBlur.rotationSize(60, ROTATION)).toBe(0)
		expect(MotionBlur.rotationSize(120, ROTATION)).toBe(0)
		expect(MotionBlur.rotationSize(300, ROTATION)).toBeNear(6 * 0.5 ^ 1.5, 1e-12)
		expect(MotionBlur.rotationSize(480, ROTATION)).toBe(6)
		expect(MotionBlur.rotationSize(5000, ROTATION)).toBe(6)
		expect(MotionBlur.rotationSize(0 / 0, ROTATION)).toBe(0)
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
		local near, far = MotionBlur.depth("Chase", 50, 1, SPEED, ACCELERATION)
		expect(near).toBeNear(0.5, 1e-12)
		expect(far).toBeNear(0.4, 1e-12)
		near, far = MotionBlur.depth("Chase", 190, 0.5, SPEED, ACCELERATION)
		expect(near).toBeNear(MotionBlur.speedNear(190, SPEED) + 0.25, 1e-12)
		expect(far).toBeNear(0.2, 1e-12)
		near, far = MotionBlur.depth("Chase", 190, 0, SPEED, ACCELERATION)
		expect(near).toBeNear(MotionBlur.speedNear(190, SPEED), 1e-12)
		expect(far).toBe(0)
	end)

	it("blurs only past the cabin in the cockpit and hood views, never on foot", function()
		for _, view in { "Cockpit", "Hood" } do
			local near, far = MotionBlur.depth(view, 50, 1, SPEED, ACCELERATION)
			expect(near).toBe(0)
			expect(far).toBeNear(0.2, 1e-12)
			near, far = MotionBlur.depth(view, 400, 0, SPEED, ACCELERATION)
			expect(near).toBe(0)
			expect(far).toBeNear(0.15, 1e-12)
		end
		local near, far = MotionBlur.depth("OnFoot", 400, 1, SPEED, ACCELERATION)
		expect(near).toBe(0)
		expect(far).toBe(0)
	end)

	it("scales the pull's blur with its one intensity, never past full", function()
		local near, far = MotionBlur.depth("Chase", 50, 1, SPEED, with({ intensity = 0 }))
		expect(near).toBe(0)
		expect(far).toBe(0)
		near, far = MotionBlur.depth("Chase", 50, 0.5, SPEED, with({ intensity = 2 }))
		expect(near).toBeNear(0.5, 1e-12)
		expect(far).toBeNear(0.4, 1e-12)
		near, far = MotionBlur.depth("Chase", 400, 1, SPEED, with({ intensity = 5 }))
		expect(near).toBe(1)
		expect(far).toBe(1)
		near, far = MotionBlur.depth("Cockpit", 50, 0.5, SPEED, with({ intensity = 2 }))
		expect(far).toBeNear(0.2, 1e-12)
		near, far = MotionBlur.depth("Cockpit", 50, 0 / 0, SPEED, ACCELERATION)
		expect(far).toBe(0)
	end)

	it("counts a pull under its floor as none, so the blur switches off after a pull", function()
		local near, far = MotionBlur.depth("Chase", 50, 0.01, SPEED, ACCELERATION)
		expect(near).toBe(0)
		expect(far).toBe(0)
		expect(MotionBlur.pulseSize(0.01, with({ style = "FullScreen" }))).toBe(0)
		local pull = 1
		for _ = 1, 3 * 60 do
			pull = MotionBlur.follow(pull, MotionBlur.pullShare(0, ACCELERATION), 1 / 60, ACCELERATION)
		end
		expect(pull > 0).toBe(true)
		near, far = MotionBlur.depth("Cockpit", 50, pull, SPEED, ACCELERATION)
		expect(near).toBe(0)
		expect(far).toBe(0)
	end)

	it("draws the pull's blur in one style only: the depth of field or the full screen", function()
		expect(MotionBlur.pulseSize(1, ACCELERATION)).toBe(0)
		local full = with({ style = "FullScreen" })
		expect(MotionBlur.pulseSize(1, full)).toBe(3)
		expect(MotionBlur.pulseSize(0.5, with({ style = "FullScreen", intensity = 2 }))).toBeNear(3, 1e-12)
		expect(MotionBlur.pulseSize(0 / 0, full)).toBe(0)
		local near, far = MotionBlur.depth("Chase", 190, 1, SPEED, full)
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
		local _, far = MotionBlur.depth("Chase", 40, pull, Config.SPEED, acceleration)
		expect(far >= 0.25).toBe(true)
		local _, cabin = MotionBlur.depth("Cockpit", 40, pull, Config.SPEED, acceleration)
		expect(cabin >= 0.12).toBe(true)
	end)

	it("never fogs the cockpit or the hood view, at any speed and pull", function()
		for _, view in { "Cockpit", "Hood" } do
			for kmh = 0, 400, 20 do
				local _, far = MotionBlur.depth(view, kmh, 1, Config.SPEED, acceleration)
				expect(far <= COCKPIT_FOG).toBe(true)
			end
		end
	end)

	it("leaves a steady cruise to the speed's lighter blur", function()
		expect(MotionBlur.pullShare(0.1, acceleration)).toBe(0)
		local _, far = MotionBlur.depth("Chase", 400, 0, Config.SPEED, acceleration)
		expect(far).toBe(0)
	end)

	it("starts in the depth of field style, the full screen kept for comparison", function()
		expect(acceleration.style).toBe("DepthOfField")
		expect(acceleration.fullScreen > 0).toBe(true)
	end)
end)
