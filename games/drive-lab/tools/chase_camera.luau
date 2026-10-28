--!strict
--[[
	The chase camera's numbers, offline: what Controllers/CarCamera sets each frame through a
	full-throttle run (the field of view through every upshift, against the rules it replaced),
	the steady pull and widening at each speed, the swing in a steady turn, and the horizontal
	field of view on a 16:9 screen and a 19.5:9 phone.

	    lune run games/drive-lab/tools/chase_camera [Strada|Sport|Corsa] [fps] [--frames]

	The car is DriveSim's SVJ; the g is measured as Car/VehicleRunner measures it (the change in
	velocity along the heading over the frame, low-passed with its 0.08 s constant).
]]
local CarCamera = require("../src/shared/Config/CarCamera")
local DriveSim = require("./DriveSim")
local Rules = require("../src/shared/Rules/CarCamera")
local SVJ = require("../src/shared/Config/Cars/SVJ")
local Types = require("../src/shared/Config/Cars/Types")
local World = require("../src/shared/Config/World")
local process = require("@lune/process")

-- Car/VehicleRunner's G_SMOOTHING.
local G_SMOOTHING = 0.08
-- The rules this branch replaced, for the before column: 70 degrees widening by 12 to 300 km/h,
-- plus 3 degrees per g up to 1.2 g, half-lives 0.04 s in and 0.12 s out.
local BEFORE = { base = 70, gain = 12, speed = 300, perG = 3, maxG = 1.2, attack = 0.04, release = 0.12 }

local mode = (process.args[1] or "Corsa") :: Types.DrivingMode
local fps = tonumber(process.args[2]) or 60
local frames = table.find(process.args, "--frames") ~= nil
local dt = 1 / fps

local function beforeKick(current: number, g: number, step: number): number
	local target = BEFORE.perG * math.clamp(g, 0, BEFORE.maxG)
	local halfLife = if target > current then BEFORE.attack else BEFORE.release
	return current + (target - current) * Rules.blend(step, halfLife)
end

local function beforeFov(speedKmh: number, kick: number): number
	return BEFORE.base + BEFORE.gain * math.clamp(speedKmh / BEFORE.speed, 0, 1) + kick
end

export type Sample = {
	time: number,
	gear: number,
	shifting: boolean,
	kmh: number,
	g: number,
	after: number,
	before: number,
}

-- Full throttle from rest for `seconds`, the gearbox in auto.
local function run(seconds: number): { Sample }
	local sim = DriveSim.new(SVJ)
	local input = DriveSim.input({ throttle = 1, drivingMode = mode })
	local kick = Rules.newKick()
	local old = 0
	local g = 0
	local samples: { Sample } = {}
	while sim.time < seconds do
		local vx, vy = sim.body.vx, sim.body.vy
		local result = DriveSim.frame(sim, input, dt)
		local heading = sim.body.heading
		local along = ((sim.body.vx - vx) * math.cos(heading) + (sim.body.vy - vy) * math.sin(heading)) / dt
		g += (along / World.GRAVITY_MPS2 - g) * (1 - math.exp(-dt / G_SMOOTHING))
		Rules.stepKick(kick, Rules.kickTarget(g), dt)
		old = beforeKick(old, g, dt)
		local kmh = DriveSim.forwardSpeed(sim) * 3.6
		table.insert(samples, {
			time = sim.time,
			gear = result.telemetry.gear,
			shifting = result.telemetry.shifting,
			kmh = kmh,
			g = g,
			after = Rules.fieldOfView("Chase", kick.degrees),
			before = beforeFov(kmh, old),
		})
	end
	return samples
end

-- Each upshift: the widening (field of view over its base) as the shift starts, its lowest in
-- the next `window` seconds and its value at the end of them. A view that breathes dips below
-- where it settles and comes back; one that only settles to the next gear's lower pull does not.
export type Shift = { from: number, to: number, kmh: number, start: number, lowest: number, settled: number }

local function upshifts(samples: { Sample }, window: number, widening: (Sample) -> number): { Shift }
	local found: { Shift } = {}
	for index = 2, #samples do
		local sample, start = samples[index], samples[index - 1]
		if sample.gear > start.gear and start.gear >= 1 then
			local lowest, settled = widening(start), widening(start)
			for later = index, #samples do
				local s = samples[later]
				if s.time - start.time > window then
					break
				end
				lowest, settled = math.min(lowest, widening(s)), widening(s)
			end
			table.insert(found, {
				from = start.gear,
				to = sample.gear,
				kmh = start.kmh,
				start = widening(start),
				lowest = lowest,
				settled = settled,
			})
		end
	end
	return found
end

local function shifts(samples: { Sample }, window: number)
	local after = upshifts(samples, window, function(s: Sample): number
		return s.after - CarCamera.FOV.Chase.base
	end)
	local before = upshifts(samples, window, function(s: Sample): number
		return s.before - beforeFov(s.kmh, 0)
	end)
	print(`\n(b) Upshifts at full throttle, {mode}, {fps} FPS: widening over the base (degrees) as the`)
	print(`shift starts, its lowest and its value {window} s later; breathing = settled - lowest`)
	print("gear | km/h | after: start lowest settled breathing | before (kick only): same")
	for index, shift in after do
		local old = before[index]
		print(
			("%d>%d | %3.0f | %5.2f %5.2f %5.2f %5.2f (%2.0f%%) | %4.2f %4.2f %4.2f %4.2f (%2.0f%%)"):format(
				shift.from,
				shift.to,
				shift.kmh,
				shift.start,
				shift.lowest,
				shift.settled,
				shift.settled - shift.lowest,
				100 * (shift.settled - shift.lowest) / shift.start,
				old.start,
				old.lowest,
				old.settled,
				old.settled - old.lowest,
				100 * (old.settled - old.lowest) / old.start
			)
		)
	end
end

-- Car width as a share of the frame height scales with 1 / (distance * tan(fov / 2)); at rest
-- it is 1 by definition. The distance is to the car's widest section (the wing's tips), `depth`
-- metres ahead of the eye along the view at rest: 2.74 at 3.3 m and 1.2 m, solved from the
-- edit-mode projection of the model (0.5702 cruising, 0.4948 at 65.52 degrees and 0.092 m back).
local function shrink(fov: number, back: number, depth: number): number
	local base = CarCamera.FOV.Chase.base
	return depth * math.tan(math.rad(base / 2)) / ((depth + back) * math.tan(math.rad(fov / 2)))
end

local function steady(samples: { Sample }, depth: number)
	print(`\n(a) Steady full throttle, {mode}: g, chase field of view, lean back, car size against cruising`)
	print(`(widest section {depth} m ahead of the eye; multiply by the cruising width Studio measures)`)
	print("km/h | gear | g | fov | lean m | size")
	local marks = { 60, 100, 140, 170, 200, 250 }
	local next = 1
	for _, s in samples do
		if next <= #marks and s.kmh >= marks[next] and not s.shifting then
			local target = Rules.leanTarget(s.g, 0, s.kmh)
			print(
				("%4.0f | %d | %.2f | %.1f | %.2f | %.3f"):format(
					s.kmh,
					s.gear,
					s.g,
					s.after,
					target.back,
					shrink(s.after, target.back, depth)
				)
			)
			next += 1
		end
	end
end

local function turn()
	local chase = CarCamera.CHASE
	local axleForward = Rules.rearAxle(SVJ)
	print("\n(c) Steady 1 g turn, lean settled, rigid yaw: the camera's swing round the car's centre, and")
	print("where the car then sits off the frame's centre (the aim turns with the eye)")
	print(
		"km/h | yaw rate deg/s | eye shift m | swing deg | aim turn deg | rear axle deg | centre of mass deg"
	)
	for _, kmh in { 60, 100, 150 } do
		local lean = Rules.leanTarget(0, 1, kmh)
		local shift = -lean.right
		local aim = math.atan(shift / (chase.distance + chase.lookAhead))
		local axle = math.atan(shift / chase.distance) - aim
		local swing = math.atan(shift / (chase.distance - axleForward))
		local centre = swing - aim
		local yawRate = World.GRAVITY_MPS2 / (kmh / 3.6)
		print(
			("%3d | %4.1f | %.2f | %.2f | %.2f | %.2f | %.2f"):format(
				kmh,
				math.deg(yawRate),
				shift,
				math.deg(swing),
				math.deg(aim),
				math.deg(axle),
				math.deg(centre)
			)
		)
		local spring = chase.yawSpring
		print(
			("      with the yaw spring on at %g Hz the view would trail by a further %.2f deg"):format(
				spring.hz,
				math.deg(2 * yawRate / (2 * math.pi * spring.hz))
			)
		)
	end
end

local function aspects()
	print("\n(d) Horizontal field of view (Roblox holds the vertical one)")
	print("aspect | chase cruising | chase +10 | cockpit")
	for _, aspect in { { "16:9", 16 / 9 }, { "19.5:9", 19.5 / 9 } } do
		local function horizontal(vertical: number): number
			return math.deg(2 * math.atan(math.tan(math.rad(vertical / 2)) * aspect[2]))
		end
		local chase = CarCamera.FOV.Chase.base
		print(
			("%s | %.1f | %.1f | %.1f"):format(
				aspect[1],
				horizontal(chase),
				horizontal(chase + CarCamera.FOV_KICK.max),
				horizontal(CarCamera.FOV.Cockpit.base)
			)
		)
	end
end

local samples = run(14)
if frames then
	print("time | gear | shifting | km/h | g | fov after | fov before")
	for _, s in samples do
		print(
			("%.4f | %d | %s | %.1f | %.3f | %.3f | %.3f"):format(
				s.time,
				s.gear,
				tostring(s.shifting),
				s.kmh,
				s.g,
				s.after,
				s.before
			)
		)
	end
	return
end
shifts(samples, 0.6)
steady(samples, tonumber(process.env.CHASE_DEPTH) or 2.74)
turn()
aspects()
