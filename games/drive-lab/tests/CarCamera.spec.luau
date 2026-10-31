--!strict
local CarCamera = require("../src/shared/Config/CarCamera")
local DriveSim = require("../tools/DriveSim")
local Rules = require("../src/shared/Rules/CarCamera")
local SVJ = require("../src/shared/Config/Cars/SVJ/Physics")
local T = require("../../../tools/test/T")
local Types = require("../src/shared/Config/Cars/Types")

local describe, it, expect = T.describe, T.it, T.expect

-- Steps the kick through `seconds` toward `target` at `fps`.
local function hold(kick: Rules.Kick, target: number, seconds: number, fps: number)
	for _ = 1, math.floor(seconds * fps + 0.5) do
		Rules.stepKick(kick, target, 1 / fps)
	end
end

local function settled(degrees: number): Rules.Kick
	local kick = Rules.newKick()
	hold(kick, degrees, 10, 60)
	return kick
end

-- Full throttle from rest in `mode` at 60 FPS, the g measured as Car/VehicleRunner measures it
-- (its 0.08 s low-pass); for each upshift, how far the widening dips in the 0.6 s after the shift
-- starts below where it is at the end of them.
local function upshiftDips(mode: Types.DrivingMode): { number }
	local dt = 1 / 60
	local sim = DriveSim.new(SVJ)
	local input = DriveSim.input({ throttle = 1, drivingMode = mode })
	local kick = Rules.newKick()
	local g, gear = 0, 1
	local starts: { number } = {}
	local trace: { { time: number, degrees: number } } = {}
	while sim.time < 12 do
		local vx, vy = sim.body.vx, sim.body.vy
		local result = DriveSim.frame(sim, input, dt)
		local heading = sim.body.heading
		local along = ((sim.body.vx - vx) * math.cos(heading) + (sim.body.vy - vy) * math.sin(heading)) / dt
		g += (along / 9.81 - g) * (1 - math.exp(-dt / 0.08))
		Rules.stepKick(kick, Rules.kickTarget(g), dt)
		if result.telemetry.gear > gear then
			table.insert(starts, #trace)
		end
		gear = result.telemetry.gear
		table.insert(trace, { time = sim.time, degrees = kick.degrees })
	end
	local dips: { number } = {}
	for _, start in starts do
		local lowest, last = math.huge, 0
		for index = start, #trace do
			if trace[index].time - trace[start].time > 0.6 then
				break
			end
			lowest, last = math.min(lowest, trace[index].degrees), trace[index].degrees
		end
		table.insert(dips, last - lowest)
	end
	return dips
end

describe("CarCamera", function()
	it("closes the same share of a gap whatever the frame rate", function()
		local coarse = Rules.blend(0.1, 0.25)
		local fine = 0
		for _ = 1, 10 do
			fine += (1 - fine) * Rules.blend(0.01, 0.25)
		end
		expect(fine).toBeNear(coarse, 1e-9)
	end)

	it("hangs the chase camera off the SVJ's rear axle, from its config", function()
		local forward, up = Rules.rearAxle(SVJ)
		expect(forward).toBeNear(-1.161, 1e-9)
		expect(up).toBeNear(-0.098, 1e-9)
	end)

	it("leans back under acceleration, forward braking and out of a turn, within its cap", function()
		local lean = CarCamera.CHASE.lean
		expect(Rules.leanTarget(1, 0, 100).back).toBeNear(lean.longitudinalPerG, 1e-12)
		expect(Rules.leanTarget(-1, 0, 100).back).toBeNear(-lean.longitudinalPerG, 1e-12)
		-- LateralG is positive toward the right, the inside of a right turn: the camera goes left.
		expect(Rules.leanTarget(0, 1, 100).right).toBeNear(-lean.lateralPerG, 1e-12)
		expect(Rules.leanTarget(0, -1, 100).right).toBeNear(lean.lateralPerG, 1e-12)
		expect(Rules.leanTarget(0, 3, 100).right).toBeNear(-lean.max, 1e-12)
		expect(Rules.leanTarget(5, 0, 100).back).toBeNear(lean.max, 1e-12)
	end)

	it("does not lean at rest, and fades the lean in up to its speed", function()
		local lean = CarCamera.CHASE.lean
		local still = Rules.leanTarget(1, 1, 0)
		expect(still.back).toBe(0)
		expect(still.right).toBe(0)
		expect(Rules.leanTarget(1, 0, lean.fadeKmh / 2).back).toBeNear(lean.longitudinalPerG / 2, 1e-12)
		local broken = Rules.leanTarget(0 / 0, math.huge, 0 / 0)
		expect(broken.back).toBe(0)
		expect(broken.right).toBe(0)
	end)

	it("eases the lean with its half-life, the same at any frame rate", function()
		local target = { right = -0.4, back = 0.2 }
		local results: { Rules.Lean } = {}
		for _, fps in { 30, 60, 144, 240 } do
			local lean = { right = 0, back = 0 }
			for _ = 1, fps do
				Rules.stepLean(lean, target, 1 / fps)
			end
			table.insert(results, lean)
		end
		local expected = 1 - 0.5 ^ (1 / CarCamera.CHASE.lean.halfLife)
		for _, lean in results do
			expect(lean.back).toBeNear(0.2 * expected, 1e-9)
			expect(lean.right).toBeNear(-0.4 * expected, 1e-9)
		end
	end)

	it("widens 12 degrees per g of pull, none braking, within its cap", function()
		local kick = CarCamera.FOV_KICK
		expect(Rules.kickTarget(0.5)).toBeNear(kick.perG * 0.5, 1e-12)
		expect(Rules.kickTarget(-1.2)).toBe(0)
		expect(Rules.kickTarget(5)).toBe(kick.max)
		expect(Rules.kickTarget(0 / 0)).toBe(0)
	end)

	it("eases the widening in with the attack half-life at any frame rate", function()
		for _, fps in { 60, 120, 240 } do
			local kick = Rules.newKick()
			hold(kick, 6, CarCamera.FOV_KICK.attack, fps)
			expect(kick.degrees).toBeNear(3, 1e-9)
		end
	end)

	it("keeps the widening through a dip in the pull shorter than the hold", function()
		for _, fps in { 30, 60, 144, 240 } do
			local kick = settled(6)
			local before = kick.degrees
			hold(kick, 0, CarCamera.FOV_KICK.hold * 0.9, fps)
			hold(kick, 6, 0.5, fps)
			expect(kick.degrees >= before - 1e-6).toBe(true)
		end
	end)

	it("lets the widening out after the hold, with the release half-life", function()
		local tuning = CarCamera.FOV_KICK
		for _, fps in { 60, 120, 240 } do
			local kick = settled(6)
			local before = kick.degrees
			hold(kick, 0, tuning.hold, fps)
			expect(kick.degrees).toBeNear(before, 1e-9)
			hold(kick, 0, tuning.release, fps)
			expect(kick.degrees).toBeNear(before / 2, 1e-9)
		end
		-- At 30 FPS the hold runs out half way through a frame: only the rest of it is released.
		local coarse = settled(6)
		local before = coarse.degrees
		hold(coarse, 0, 0.8, 30)
		expect(coarse.degrees).toBeNear(before * 0.5 ^ ((0.8 - tuning.hold) / tuning.release), 1e-9)
	end)

	it(
		"holds the widening through every upshift of a full-throttle run, Strada's long cut included",
		function()
			for _, mode: Types.DrivingMode in { "Strada", "Corsa" } do
				local dips = upshiftDips(mode)
				expect(#dips >= 4).toBe(true)
				for _, dip in dips do
					expect(dip).toBeNear(0, 0.05)
				end
			end
		end
	)

	it(
		"trails a steady turn by 2 yaw rate / omega with the yaw spring, the same at any frame rate",
		function()
			local hz, rate = 5, math.rad(30)
			local expected = 2 * rate / (2 * math.pi * hz)
			for _, fps in { 60, 240 } do
				local spring = Rules.newSpring(0)
				local target = 0
				for _ = 1, 2 * fps do
					target += rate / fps
					Rules.stepYaw(spring, target, 1 / fps, hz)
				end
				expect(target - spring.angle).toBeNear(expected, 1e-6)
			end
		end
	)

	it("turns the yaw spring the short way round", function()
		local spring = Rules.newSpring(math.rad(179))
		Rules.stepYaw(spring, math.rad(-179), 1 / 60, 5)
		local moved = (spring.angle - math.rad(179) + math.pi) % (2 * math.pi) - math.pi
		expect(moved > 0).toBe(true)
		expect(moved < math.rad(2)).toBe(true)
	end)

	it("sets each view's field of view from its base and its share of the widening, not speed", function()
		local fov = CarCamera.FOV
		expect(Rules.fieldOfView("Chase", 0)).toBe(fov.Chase.base)
		expect(Rules.fieldOfView("Chase", 8)).toBeNear(fov.Chase.base + 8 * fov.Chase.kickShare, 1e-12)
		expect(Rules.fieldOfView("Cockpit", 8)).toBeNear(fov.Cockpit.base + 8 * fov.Cockpit.kickShare, 1e-12)
		expect(Rules.fieldOfView("Hood", 8)).toBeNear(fov.Hood.base + 8 * fov.Hood.kickShare, 1e-12)
		expect(Rules.fieldOfView("Cockpit", 0 / 0)).toBe(fov.Cockpit.base)
	end)
end)

describe("Chase camera drift blend", function()
	local blend = CarCamera.CHASE.driftBlend

	it("turns not at all while no drift is engaged, or below its minimum speed", function()
		expect(Rules.driftYawTarget(0, 0, math.rad(25), 20, blend)).toBe(0)
		expect(Rules.driftYawTarget(1, 0, math.rad(25), blend.minSpeed - 0.1, blend)).toBe(0)
	end)

	it("turns its share of the angle from the heading to the path, times the engagement", function()
		expect(Rules.driftYawTarget(1, 0, math.rad(25), 20, blend)).toBeNear(
			blend.share * math.rad(25),
			1e-12
		)
		expect(Rules.driftYawTarget(0.5, 0, -math.rad(25), 20, blend)).toBeNear(
			-0.5 * blend.share * math.rad(25),
			1e-12
		)
	end)

	it("turns the short way round across 180 degrees", function()
		local turn = Rules.driftYawTarget(1, math.rad(179), math.rad(-179), 20, blend)
		expect(turn).toBeNear(blend.share * math.rad(2), 1e-9)
	end)

	it("eases toward the turn, half the gap every half-life", function()
		expect(Rules.stepDriftYaw(0, 0.2, blend.halfLife, blend.halfLife)).toBeNear(0.1, 1e-12)
	end)

	it("stays off until the owner has looked at it", function()
		expect(blend.enabled).toBe(false)
	end)
end)
