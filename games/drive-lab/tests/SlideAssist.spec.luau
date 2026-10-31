--!strict
--[[
	The slide assist (Vehicle/SlideAssist) unit by unit, the game-feel level's rules and config, and
	the paths where the assist must change nothing: Realistic, and the drift button held.
]]
local DR458 = require("../src/shared/Config/Cars/DR458/Physics")
local DriveSim = require("../tools/DriveSim")
local GameFeel = require("../src/shared/Rules/GameFeel")
local GameFeelConfig = require("../src/shared/Config/GameFeel")
local Geometry = require("../src/shared/Vehicle/Geometry")
local InputHelp = require("../src/shared/Config/InputHelp")
local SVJ = require("../src/shared/Config/Cars/SVJ/Physics")
local SlideAssist = require("../src/shared/Vehicle/SlideAssist")
local Steering = require("../src/shared/Vehicle/Steering")
local T = require("../../../tools/test/T")
local Types = require("../src/shared/Config/Cars/Types")

local describe, it, expect = T.describe, T.it, T.expect

local function profileOf(car: Types.CarConfig): Types.SlideAssistProfile
	return car.slideAssist :: Types.SlideAssistProfile
end

local function contextFor(car: Types.CarConfig, notch: GameFeelConfig.Notch): SlideAssist.Context
	local profile = profileOf(car)
	return SlideAssist.newContext(profile, profile.notches[notch])
end

local function copy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, child in value do
		result[key] = copy(child)
	end
	return result
end

describe("Slide assist detector", function()
	it("measures no slide driving straight", function()
		for _, car in { SVJ, DR458 } do
			expect(SlideAssist.measure(car, contextFor(car, "Forgiving"), 0, 30, 0, 0)).toBe(0)
		end
	end)

	it("counts the rear past its start only while it slides more than the front", function()
		-- Straight wheels, the front axle moving along its heading, the rear at 1.25 of its peak.
		local car = DR458
		local front = Geometry.frontAxleDistance(car)
		local speed = 10
		local yaw = speed * math.tan(1.25 * car.rear.tyre.slipAngleAtPeak) / car.wheelbase
		local right = -front * yaw
		expect(yaw < profileOf(car).notches.Forgiving.yawErrorStart).toBe(true)
		local forgiving = SlideAssist.measure(car, contextFor(car, "Forgiving"), 0, speed, right, yaw)
		expect(forgiving).toBeNear((1.25 - 1) / profileOf(car).rearSlipBand, 1e-9)
		expect(SlideAssist.measure(car, contextFor(car, "Balanced"), 0, speed, right, yaw)).toBe(0)
		-- The same rear with the front sliding further is understeer, not a slide to catch.
		local lock = Steering.frontAngle(car.steering, 1, speed)
		local wide = SlideAssist.measure(car, contextFor(car, "Forgiving"), 1, speed, right, yaw)
		expect(lock > 2 * car.front.tyre.slipAngleAtPeak).toBe(true)
		expect(wide).toBe(0)
	end)

	it("counts the yaw rate past its start off ESC's reference", function()
		-- Straight wheels, so the reference is no yaw; the rear axle moving along its heading.
		local car = SVJ
		local rear = car.wheelbase - Geometry.frontAxleDistance(car)
		local yaw = 0.7
		local right = rear * yaw
		local profile = profileOf(car)
		local forgiving = SlideAssist.measure(car, contextFor(car, "Forgiving"), 0, 30, right, yaw)
		expect(forgiving).toBeNear(
			(yaw - profile.notches.Forgiving.yawErrorStart) / profile.yawErrorBand,
			1e-9
		)
		local balanced = SlideAssist.measure(car, contextFor(car, "Balanced"), 0, 30, right, yaw)
		expect(balanced).toBeNear((yaw - profile.notches.Balanced.yawErrorStart) / profile.yawErrorBand, 1e-9)
	end)

	it("holds a slide's share and hands it back over the hold time, never below nothing", function()
		expect(SlideAssist.hold(0, 1, 0.4, 0.1)).toBeNear(0.75, 1e-12)
		expect(SlideAssist.hold(0.9, 0.2, 0.4, 0.1)).toBe(0.9)
		expect(SlideAssist.hold(0, 0.05, 0.4, 0.1)).toBe(0)
	end)

	it("steers to the front axle's path, less the yaw damping", function()
		local car = SVJ
		local profile = profileOf(car)
		local speed, right, yaw = 20, -2, 0.5
		local path = math.atan((right + Geometry.frontAxleDistance(car) * yaw) / speed)
		local perRadian = Steering.ratio(car.steering, speed) / Steering.maxWheelAngle(car.steering)
		expect(SlideAssist.target(car, profile, speed, 0, 0)).toBe(0)
		expect(SlideAssist.target(car, profile, speed, right, yaw)).toBeNear(
			(path - profile.yawDamping * yaw) * perRadian,
			1e-12
		)
	end)
end)

describe("Game-feel level", function()
	it("steps Realistic, Balanced, Forgiving and back, starting at Balanced", function()
		expect(GameFeelConfig.DEFAULT).toBe("Balanced")
		expect(GameFeel.after("Realistic")).toBe("Balanced")
		expect(GameFeel.after("Balanced")).toBe("Forgiving")
		expect(GameFeel.after("Forgiving")).toBe("Realistic")
		expect(GameFeel.current("Forgiving")).toBe("Forgiving")
		expect(GameFeel.current(nil)).toBe("Balanced")
		expect(GameFeel.current("Strada")).toBe("Balanced")
	end)

	it("names the level on the HUD only for a moment after a change", function()
		local seconds = GameFeelConfig.FLASH_SECONDS
		expect(GameFeel.flash("Forgiving", 10, 10 + seconds / 2, seconds)).toBe("FORGIVING")
		expect(GameFeel.flash("Forgiving", 10, 10 + seconds, seconds)).toBe(nil)
		expect(GameFeel.flash("Forgiving", nil, 10, seconds)).toBe(nil)
	end)

	it("gives every car values for each notch above Realistic and none for Realistic", function()
		for _, car in { SVJ, DR458 } do
			local notches = profileOf(car).notches
			expect(notches.Realistic).toBe(nil)
			expect(notches.Balanced ~= nil and notches.Forgiving ~= nil).toBe(true)
			-- Forgiving catches the tail earlier than Balanced on both counts.
			expect(notches.Forgiving.rearSlipStart < notches.Balanced.rearSlipStart).toBe(true)
			expect(notches.Forgiving.yawErrorStart <= notches.Balanced.yawErrorStart).toBe(true)
		end
	end)

	it("refuses a profile that misses a notch, sets Realistic, names a stranger or has no band", function()
		local function define(edit: (any) -> ()): () -> ()
			return function()
				local car = copy(SVJ)
				edit(car.slideAssist)
				Types.define(car)
			end
		end
		expect(define(function(profile)
			profile.notches.Forgiving = nil
		end)).toThrow()
		expect(define(function(profile)
			profile.notches.Realistic = { rearSlipStart = 1, yawErrorStart = 1 }
		end)).toThrow()
		expect(define(function(profile)
			profile.notches.Arcade = { rearSlipStart = 1, yawErrorStart = 1 }
		end)).toThrow()
		expect(define(function(profile)
			profile.rearSlipBand = 0
		end)).toThrow()
		expect((pcall(define(function() end)))).toBe(true)
	end)
end)

-- Rolling at 100 km/h with the body set sliding 20° and turning into it, 2 s at 60 FPS: the
-- counter-steer key for half a second, then no keys. The yaw rate, lateral speed, steering and the
-- assist's share after each frame.
local function slide(car: Types.CarConfig, notch: GameFeelConfig.Notch?, drift: boolean): { number }
	local sim = DriveSim.new(car, InputHelp.keyboard)
	local speed = 100 / 3.6
	DriveSim.setSpeed(sim, speed, 3)
	sim.body.vx, sim.body.vy, sim.body.yawRate =
		speed * math.cos(math.rad(20)), -speed * math.sin(math.rad(20)), 0.8
	local trace: { number } = {}
	for frame = 1, 120 do
		local result = DriveSim.frame(
			sim,
			DriveSim.input({
				throttle = 0.3,
				steer = if frame < 30 then -1 else 0,
				drivingMode = car.modeOrder[1],
				drift = drift,
				handbrake = if drift then 1 else 0,
				gameFeel = notch,
			}),
			1 / 60
		)
		table.insert(trace, sim.body.yawRate)
		table.insert(trace, sim.body.vy)
		table.insert(trace, result.telemetry.steer)
		table.insert(trace, result.telemetry.slideAssist)
	end
	return trace
end

local function same(a: { number }, b: { number }): boolean
	if #a ~= #b then
		return false
	end
	for index, value in a do
		if value ~= b[index] then
			return false
		end
	end
	return true
end

describe("Slide assist stands aside", function()
	it("changes nothing at Realistic, frame for frame, through a slide", function()
		for _, car in { SVJ, DR458 } do
			expect(same(slide(car, "Realistic", false), slide(car, nil, false))).toBe(true)
		end
	end)

	it("changes nothing while the drift button is held, frame for frame, through a slide", function()
		for _, car in { SVJ, DR458 } do
			expect(same(slide(car, "Forgiving", true), slide(car, nil, true))).toBe(true)
		end
	end)

	it("takes the steering in the same slide at Forgiving", function()
		for _, car in { SVJ, DR458 } do
			expect(same(slide(car, "Forgiving", false), slide(car, nil, false))).toBe(false)
		end
	end)
end)
