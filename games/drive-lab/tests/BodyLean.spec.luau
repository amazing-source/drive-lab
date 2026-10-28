--!strict
local BodyLean = require("../src/shared/Rules/BodyLean")
local Lean = require("../src/shared/Config/Lean")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local GRAVITY = 35
local SPEED = 22

-- time -> velocity x, z, facing x, z, yaw rate, seated
type Path = (time: number) -> (number, number, number, number, number, boolean?)

local function run(path: Path, seconds: number, fps: number, watch: ((BodyLean.State) -> ())?): BodyLean.State
	local state = BodyLean.new()
	local dt = 1 / fps
	for frame = 1, math.floor(seconds * fps + 0.5) do
		local vx, vz, fx, fz, yawRate, seated = path(frame * dt)
		state = BodyLean.step(state, {
			velocityX = vx,
			velocityZ = vz,
			facingX = fx,
			facingZ = fz,
			yawRate = yawRate,
			gravity = GRAVITY,
			upright = not seated,
		}, dt)
		if watch then
			watch(state)
		end
	end
	return state
end

-- Heading turns from -Z toward +X (a right turn seen from above) at `rate` rad/s.
local function turning(rate: number): Path
	return function(time)
		local heading = rate * time
		local fx, fz = math.sin(heading), -math.cos(heading)
		return fx * SPEED, fz * SPEED, fx, fz, rate
	end
end

describe("BodyLean", function()
	it("leans forward running straight, and not sideways", function()
		local state = run(function(_time)
			return 0, -SPEED, 0, -1, 0
		end, 2, 60)
		expect(state.pitch).toBeNear(Lean.FORWARD_TILT, math.rad(0.1))
		expect(math.abs(state.roll) < math.rad(0.1)).toBe(true)
	end)

	it("leans into a right turn and out of a left one", function()
		local right = run(turning(1.2), 2, 60)
		local left = run(turning(-1.2), 2, 60)
		expect(right.roll > math.rad(5)).toBe(true)
		expect(left.roll).toBeNear(-right.roll, 1e-9)
	end)

	it("leans the share of the balance angle in a steady turn", function()
		local state = run(turning(0.5), 3, 60)
		local expected = math.atan(SPEED * 0.5 / GRAVITY) * Lean.TURN_GAIN
		expect(state.roll).toBeNear(math.min(expected, Lean.MAX_ROLL), math.rad(0.1))
	end)

	it("goes straight back upright when the player lets go, never past it", function()
		local worstBack = 0
		run(
			function(time)
				local speed = if time < 1 then SPEED else 0
				return 0, -speed, 0, -1, 0
			end,
			3,
			60,
			function(state)
				worstBack = math.min(worstBack, state.pitch)
			end
		)
		expect(worstBack >= 0).toBe(true)
	end)

	it("tilts toward sideways travel", function()
		local state = run(function(_time)
			return Lean.SIDE_SPEED, 0, 0, -1, 0
		end, 2, 60)
		expect(state.roll).toBeNear(Lean.SIDE_TILT, math.rad(0.1))
	end)

	it("never passes its limits", function()
		local state = run(turning(20), 1, 60)
		expect(state.roll <= Lean.MAX_ROLL + 1e-9).toBe(true)
	end)

	it("relaxes upright when seated", function()
		local state = run(function(time)
			local vx, vz, fx, fz, yawRate = turning(1.2)(time)
			return vx, vz, fx, fz, yawRate, time > 1
		end, 3, 60)
		expect(math.abs(state.roll) < math.rad(0.1)).toBe(true)
	end)

	it("leans the same at 30 and 240 frames per second", function()
		local slow = run(turning(1.0), 2, 30)
		local fast = run(turning(1.0), 2, 240)
		expect(slow.roll).toBeNear(fast.roll, math.rad(0.2))
	end)
end)
