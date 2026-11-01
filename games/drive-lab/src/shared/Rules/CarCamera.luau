--!strict
--[[
	The numbers behind the driving cameras: where the chase camera hangs on the car, its shift
	with the car's g, the optional spring on its yaw, and the field of view widening under
	acceleration and with speed. Every easing is an exact exponential or spring, so it moves the
	same at any frame rate.
]]
local CarCamera = require("../Config/CarCamera")
local Geometry = require("../Vehicle/Geometry")
local Types = require("../Config/Cars/Types")

-- Metres in the car's frame: `right` toward its right side, `back` toward its tail.
export type Lean = { right: number, back: number }

-- Degrees the view is widened by; the clock (s) and, oldest first, the times and targets of the
-- frames within the hold that no later target has matched, so the first is the hold's peak.
export type Kick = { degrees: number, clock: number, times: { number }, targets: { number } }

-- Radians and radians a second; `target` is the last frame's.
export type Spring = { angle: number, velocity: number, target: number }

local Rules = {}

local function finite(value: number): number
	return if value == value and math.abs(value) < math.huge then value else 0
end

-- What a notch of the mouse wheel moves in the cockpit view: the eye's height with its modifier
-- held, its distance forward otherwise, and nothing while the clutch key is in use, since the
-- clutch mode's key (Config/Controls CLUTCH) is the height's modifier too.
function Rules.eyeScroll(heightModifier: boolean, clutchInUse: boolean): ("Height" | "Forward")?
	if clutchInUse then
		return nil
	end
	return if heightModifier then "Height" else "Forward"
end

-- Share of the remaining gap closed this frame; the gap halves every `halfLife` seconds.
function Rules.blend(dt: number, halfLife: number): number
	return 1 - 0.5 ^ (dt / halfLife)
end

-- The midpoint of the rear hubs from the centre of mass, metres: forward (negative, behind it)
-- and up (the rear tyre's radius against the centre's height above the road).
function Rules.rearAxle(car: Types.CarConfig): (number, number)
	return Geometry.frontAxleDistance(car) - car.wheelbase, car.rear.tyre.radius - car.cgHeight
end

-- The chase camera's distance behind and height above the rear axle for this car's views, metres.
function Rules.chaseFraming(views: CarCamera.CarViews?): CarCamera.ChaseFraming
	local own = views and views.chase
	return own or { distance = CarCamera.CHASE.distance, height = CarCamera.CHASE.height }
end

-- Where the lean heads under these g: back while accelerating, forward braking, toward the
-- outside of a turn (LateralG is positive toward the right, the inside of a right turn); none
-- at rest, full from `fadeKmh`.
function Rules.leanTarget(longitudinalG: number, lateralG: number, speedKmh: number): Lean
	local lean = CarCamera.CHASE.lean
	local fade = math.clamp(finite(speedKmh) / lean.fadeKmh, 0, 1)
	return {
		right = math.clamp(-lean.lateralPerG * finite(lateralG), -lean.max, lean.max) * fade,
		back = math.clamp(lean.longitudinalPerG * finite(longitudinalG), -lean.max, lean.max) * fade,
	}
end

function Rules.stepLean(lean: Lean, target: Lean, dt: number)
	local share = Rules.blend(dt, CarCamera.CHASE.lean.halfLife)
	lean.right += (target.right - lean.right) * share
	lean.back += (target.back - lean.back) * share
end

local function wrap(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

-- The chase camera's turn toward a drifting car's path (rad, in the yaw's sense): `share` of the
-- angle from the heading's yaw to the path's yaw, times the drift's engagement `drift` (0 to 1).
-- None while the drift is not engaged or the car is slower than `minSpeed`.
function Rules.driftYawTarget(
	drift: number,
	headingYaw: number,
	pathYaw: number,
	speed: number,
	blend: CarCamera.DriftBlend
): number
	if drift <= 0 or speed < blend.minSpeed then
		return 0
	end
	return math.clamp(drift, 0, 1) * blend.share * wrap(pathYaw - headingYaw)
end

-- `current` moved toward `target`, half the gap every `halfLife` s.
function Rules.stepDriftYaw(current: number, target: number, dt: number, halfLife: number): number
	return current + (target - current) * Rules.blend(dt, halfLife)
end

function Rules.newSpring(angle: number): Spring
	return { angle = angle, velocity = 0, target = angle }
end

-- The critically damped spring after `dt`, its target moving at a steady rate from the last
-- frame's to this one: the exact solution, so it is stable, trails a steady turn by exactly
-- 2 * rate / omega, and moves the same at any frame rate. The target turns the short way round
-- across +-180 degrees; the angle is always kept on the target's side of it.
function Rules.stepYaw(spring: Spring, target: number, dt: number, hz: number)
	if dt <= 0 then
		return
	end
	local omega = 2 * math.pi * hz
	local rate = wrap(target - spring.target) / dt
	local trail = 2 * rate / omega
	local offset = spring.angle - spring.target + trail
	local slip = spring.velocity - rate
	local drive = slip + omega * offset
	local decay = math.exp(-omega * dt)
	spring.angle = target + (offset + drive * dt) * decay - trail
	spring.velocity = (slip - omega * drive * dt) * decay + rate
	spring.target = target
end

function Rules.newKick(): Kick
	return { degrees = 0, clock = 0, times = {}, targets = {} }
end

-- Degrees the view widens under a pull of `longitudinalG`: none when braking or coasting.
function Rules.kickTarget(longitudinalG: number): number
	local kick = CarCamera.FOV_KICK
	return math.min(kick.perG * math.max(finite(longitudinalG), 0), kick.max)
end

local function ease(kick: Kick, peak: number, span: number)
	local tuning = CarCamera.FOV_KICK
	local halfLife = if peak > kick.degrees then tuning.attack else tuning.release
	kick.degrees += (peak - kick.degrees) * Rules.blend(span, halfLife)
end

-- The kick eases toward the highest target of the last `hold` seconds (in with the attack
-- half-life, out with the release one), so a dip in the pull shorter than the hold, a gear
-- change's torque cut, never reaches the view, while a lasting fall does, `hold` late. Where a
-- peak runs out inside a frame, the frame is eased in parts, so any frame rate gives the same.
function Rules.stepKick(kick: Kick, target: number, dt: number)
	local hold = CarCamera.FOV_KICK.hold
	local times, targets = kick.times, kick.targets
	local elapsed = kick.clock
	kick.clock += dt
	while #targets > 0 and targets[#targets] <= target do
		table.remove(targets)
		table.remove(times)
	end
	table.insert(targets, target)
	table.insert(times, kick.clock)
	while true do
		local expiry = times[1] + hold
		local reached = math.min(expiry, kick.clock)
		if reached > elapsed then
			ease(kick, targets[1], reached - elapsed)
			elapsed = reached
		end
		-- A peak running out on the frame's own end (to rounding) still covers the frame.
		if expiry >= kick.clock - 1e-9 then
			return
		end
		table.remove(targets, 1)
		table.remove(times, 1)
	end
end

-- Degrees the view widens at `speedKmh`, either way: none under `fromKmh`, then `perKmh` a km/h
-- up to `max`.
function Rules.speedTarget(speedKmh: number): number
	local widen = CarCamera.FOV_SPEED
	return math.clamp((math.abs(finite(speedKmh)) - widen.fromKmh) * widen.perKmh, 0, widen.max)
end

-- `current` moved toward `target`, half the gap every FOV_SPEED.halfLife s.
function Rules.stepSpeedWiden(current: number, target: number, dt: number): number
	return current + (target - current) * Rules.blend(dt, CarCamera.FOV_SPEED.halfLife)
end

-- The view's field of view (degrees): the base, plus the view's shares of the kick and of the
-- speed's widening.
function Rules.fieldOfView(view: CarCamera.View, kickDegrees: number, speedDegrees: number): number
	local fov = CarCamera.FOV[view]
	return fov.base + finite(kickDegrees) * fov.kickShare + finite(speedDegrees) * fov.speedShare
end

return table.freeze(Rules)
