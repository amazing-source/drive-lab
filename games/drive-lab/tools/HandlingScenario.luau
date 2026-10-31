--!strict
--[[
	Scripted drivers on tools/DriveSim for the handling's specs and tools/handling.luau: what a
	keyboard or pad player does at the limit, and what the car does back. Every run turns right
	(steer +1); a right-hand oversteer slides with the velocity left of the heading, so its body
	slip is negative.

	- `liftOff`: a held corner at a speed, the key held, then the throttle lifted with the key still
	  held.
	- `powerOn`: the same corner, then full throttle with the key held.
	- `brakeTurn`: the same corner, then full brake with the key held.
	- `stepSteer`: straight at a speed, then the key pressed and held.
	- `laneChange`: straight, then right for a moment, left for as long, and released.
	- `recover`: rolling straight with the car already sliding (a body slip and a yaw rate set on the
	  body), then a driver who lets go of the keys, or one who counter-steers on the keys.
]]
local DriveSim = require("./DriveSim")
local DriverAssists = require("../src/shared/Rules/DriverAssists")
local GameFeel = require("../src/shared/Config/GameFeel")
local InputHelp = require("../src/shared/Config/InputHelp")
local Model = require("../src/shared/Vehicle/Model")
local Types = require("../src/shared/Config/Cars/Types")

local KMH = 1 / 3.6
-- Body slip past which a run counts as a spin.
local SPIN = math.rad(45)
-- Body slip under which a slide counts as caught, and how long it must stay there.
local CAUGHT = math.rad(2)
local CAUGHT_HOLD = 0.5
local CORNER_TIME = 3
local EVENT_TIME = 3
-- Below this speed (m/s) body slip has no meaning (a stopped car has no direction of travel), so
-- slip and spins are only read above it.
local SLIP_SPEED = 5

export type Setup = {
	car: Types.CarConfig,
	assists: DriverAssists.Tuning,
	mode: Types.DrivingMode,
	escOff: boolean?,
	help: InputHelp.InputHelp?,
	fps: number?,
	gameFeel: GameFeel.Notch?,
}

export type Event = {
	-- Body slip (rad, signed) and yaw rate (rad/s) on the last frame before the event.
	slipBefore: number,
	yawBefore: number,
	lateralBefore: number,
	-- After the event: the most body slip toward the oversteer (rad, positive), the peak yaw rate
	-- over the one before it, whether the car spun, and the share of frames ESC acted.
	peakSlip: number,
	yawGain: number,
	spun: boolean,
	escShare: number,
	-- km/h at the end of the event.
	endKmh: number,
}

export type Step = {
	-- Seconds from the press to half and 90 % of the steady yaw rate (math.huge if never).
	t50: number,
	t90: number,
	-- Over the last 0.5 s held: yaw rate (rad/s), lateral g, body slip (rad, signed), the front and
	-- rear slip angles over their peaks, and the steering input the filter settled on.
	yaw: number,
	lateral: number,
	slip: number,
	frontShare: number,
	rearShare: number,
	steer: number,
	-- Peak yaw rate over the steady one, less 1.
	overshoot: number,
	spun: boolean,
	-- The most of the steering the slide assist held.
	assistPeak: number,
}

export type Lane = {
	-- Most body slip (rad, unsigned) and seconds from the release until the slip stays under 2°.
	peakSlip: number,
	settle: number,
	spun: boolean,
	assistPeak: number,
}

export type Recovery = {
	-- Seconds until the slip stays under 2° for 0.5 s (math.huge if never), the most slip the
	-- other way once the slide has crossed zero (rad, positive), the peak slip, and a spin.
	settle: number,
	overcorrect: number,
	peakSlip: number,
	spun: boolean,
	endKmh: number,
}

local HandlingScenario = {}

HandlingScenario.SPIN = SPIN

-- Body slip (rad), signed: positive when the velocity points right of the heading.
function HandlingScenario.bodySlip(sim: DriveSim.Sim): number
	local forward, right = DriveSim.localVelocity(sim.body)
	return math.atan2(right, math.abs(forward))
end

-- The gear the car would hold at `kmh` (its highest at or above 4,000 rpm).
function HandlingScenario.gearFor(car: Types.CarConfig, kmh: number): number
	local wheel = kmh * KMH / car.rear.tyre.radius * car.driveline.rearReduction
	for gear = #car.gearbox.ratios, 1, -1 do
		if wheel * car.gearbox.ratios[gear] * 60 / (2 * math.pi) >= 4000 then
			return gear
		end
	end
	return 1
end

local function newSim(setup: Setup, kmh: number): DriveSim.Sim
	local sim = DriveSim.new(setup.car, setup.help or InputHelp.keyboard)
	DriveSim.setSpeed(sim, kmh * KMH, HandlingScenario.gearFor(setup.car, kmh))
	return sim
end

local function input(setup: Setup, throttle: number, brake: number, steer: number): Model.DriverInput
	local assists = DriverAssists.assists(setup.escOff == true, setup.mode, setup.assists)
	return DriveSim.input({
		throttle = throttle,
		brake = brake,
		steer = steer,
		drivingMode = setup.mode,
		abs = assists.abs,
		tc = assists.tc,
		esc = assists.esc,
		gameFeel = setup.gameFeel,
	})
end

local function moving(sim: DriveSim.Sim): boolean
	local body = sim.body
	return body.vx * body.vx + body.vy * body.vy > SLIP_SPEED * SLIP_SPEED
end

local function hold(sim: DriveSim.Sim, kmh: number): number
	return math.clamp(0.3 + 0.6 * (kmh * KMH - DriveSim.forwardSpeed(sim)), 0, 1)
end

local function dtOf(setup: Setup): number
	return 1 / (setup.fps or 60)
end

-- A corner held for CORNER_TIME with the key down and the throttle holding `kmh`, then `event`'s
-- pedals for EVENT_TIME with the key still down.
local function corner(setup: Setup, kmh: number, throttle: number, brake: number): Event
	local dt = dtOf(setup)
	local sim = newSim(setup, kmh)
	local outcome: Event = {
		slipBefore = 0,
		yawBefore = 0,
		lateralBefore = 0,
		peakSlip = 0,
		yawGain = 0,
		spun = false,
		escShare = 0,
		endKmh = 0,
	}
	while sim.time < CORNER_TIME do
		DriveSim.frame(sim, input(setup, hold(sim, kmh), 0, 1), dt)
	end
	outcome.slipBefore = HandlingScenario.bodySlip(sim)
	outcome.yawBefore = sim.body.yawRate
	outcome.lateralBefore = DriveSim.forwardSpeed(sim) * sim.body.yawRate / 9.81
	local frames, peakYaw = 0, 0
	while sim.time < CORNER_TIME + EVENT_TIME do
		local result = DriveSim.frame(sim, input(setup, throttle, brake, 1), dt)
		frames += 1
		if moving(sim) then
			local slip = HandlingScenario.bodySlip(sim)
			outcome.peakSlip = math.max(outcome.peakSlip, -slip)
			peakYaw = math.max(peakYaw, sim.body.yawRate)
			outcome.spun = outcome.spun or math.abs(slip) > SPIN
		end
		outcome.escShare += if result.telemetry.escActive then 1 else 0
	end
	outcome.escShare /= frames
	outcome.yawGain = if outcome.yawBefore > 1e-6 then peakYaw / outcome.yawBefore else 0
	outcome.endKmh = DriveSim.forwardSpeed(sim) / KMH
	return outcome
end

function HandlingScenario.liftOff(setup: Setup, kmh: number): Event
	return corner(setup, kmh, 0, 0)
end

function HandlingScenario.powerOn(setup: Setup, kmh: number): Event
	return corner(setup, kmh, 1, 0)
end

-- `brake` is the pedal: 1 is a keyboard's key, a part is a pad's trigger.
function HandlingScenario.brakeTurn(setup: Setup, kmh: number, brake: number): Event
	return corner(setup, kmh, 0, brake)
end

-- Straight for 1 s, then `steer` held for 3 s with the throttle holding `kmh`.
function HandlingScenario.stepSteer(setup: Setup, kmh: number, steer: number): Step
	local dt = dtOf(setup)
	local sim = newSim(setup, kmh)
	local press, stop = 1, 4
	local yaws: { number } = {}
	local times: { number } = {}
	local outcome: Step = {
		t50 = math.huge,
		t90 = math.huge,
		yaw = 0,
		lateral = 0,
		slip = 0,
		frontShare = 0,
		rearShare = 0,
		steer = 0,
		overshoot = 0,
		spun = false,
		assistPeak = 0,
	}
	local car = setup.car
	local frames = 0
	while sim.time < stop do
		local held = sim.time >= press
		local result = DriveSim.frame(sim, input(setup, hold(sim, kmh), 0, if held then steer else 0), dt)
		outcome.assistPeak = math.max(outcome.assistPeak, result.telemetry.slideAssist)
		if held then
			table.insert(yaws, sim.body.yawRate)
			table.insert(times, sim.time - press)
			local slip = HandlingScenario.bodySlip(sim)
			outcome.spun = outcome.spun or math.abs(slip) > SPIN
			if sim.time >= stop - 0.5 then
				frames += 1
				local wheels = result.wheels
				outcome.yaw += sim.body.yawRate
				outcome.lateral += DriveSim.forwardSpeed(sim) * sim.body.yawRate / 9.81
				outcome.slip += slip
				outcome.frontShare += math.abs(wheels[1].slipAngle + wheels[2].slipAngle) / 2 / car.front.tyre.slipAngleAtPeak
				outcome.rearShare += math.abs(wheels[3].slipAngle + wheels[4].slipAngle) / 2 / car.rear.tyre.slipAngleAtPeak
				outcome.steer += result.telemetry.steer
			end
		end
	end
	frames = math.max(frames, 1)
	outcome.yaw /= frames
	outcome.lateral /= frames
	outcome.slip /= frames
	outcome.frontShare /= frames
	outcome.rearShare /= frames
	outcome.steer /= frames
	local peak = 0
	for index, yaw in yaws do
		peak = math.max(peak, yaw)
		if outcome.yaw > 1e-6 then
			if yaw >= 0.5 * outcome.yaw and outcome.t50 == math.huge then
				outcome.t50 = times[index]
			end
			if yaw >= 0.9 * outcome.yaw and outcome.t90 == math.huge then
				outcome.t90 = times[index]
			end
		end
	end
	outcome.overshoot = if outcome.yaw > 1e-6 then peak / outcome.yaw - 1 else 0
	return outcome
end

-- Straight for 1 s, the right key for `seconds`, the left key for as long, then nothing for 3 s.
function HandlingScenario.laneChange(setup: Setup, kmh: number, seconds: number): Lane
	local dt = dtOf(setup)
	local sim = newSim(setup, kmh)
	local press = 1
	local release = press + 2 * seconds
	local outcome: Lane = { peakSlip = 0, settle = math.huge, spun = false, assistPeak = 0 }
	local calm = 0
	while sim.time < release + 3 do
		local t = sim.time
		local steer = if t < press then 0 elseif t < press + seconds then 1 elseif t < release then -1 else 0
		local result = DriveSim.frame(sim, input(setup, hold(sim, kmh), 0, steer), dt)
		outcome.assistPeak = math.max(outcome.assistPeak, result.telemetry.slideAssist)
		local slip = HandlingScenario.bodySlip(sim)
		outcome.peakSlip = math.max(outcome.peakSlip, math.abs(slip))
		outcome.spun = outcome.spun or math.abs(slip) > SPIN
		if sim.time >= release then
			calm = if math.abs(slip) < CAUGHT then calm + dt else 0
			if calm >= CAUGHT_HOLD and outcome.settle == math.huge then
				outcome.settle = sim.time - CAUGHT_HOLD - release
			end
		end
	end
	return outcome
end

export type Driver = "hands off" | "keys" | "stick"

-- Body slip (rad) at which the "stick" driver's counter-steer reaches full lock.
local STICK_FULL = math.rad(15)

-- Rolling straight at `kmh` with the body already sliding: `slip` (rad, the velocity left of the
-- heading for a positive value, as a right-hand oversteer) and the yaw rate turning into it. The
-- "keys" driver holds the counter-steer key while the slip is over 2° and growing or over 6°,
-- and lets go otherwise, as a player on a keyboard catches a slide; the "stick" driver
-- counter-steers in proportion to the slip, as a thumb can. The throttle holds 0.3. The run lasts
-- `seconds`, 6 unless given.
function HandlingScenario.recover(
	setup: Setup,
	kmh: number,
	slip: number,
	yawRate: number,
	driver: Driver,
	seconds: number?
): Recovery
	local dt = dtOf(setup)
	local sim = newSim(setup, kmh)
	local speed = kmh * KMH
	local body = sim.body
	body.vx = speed * math.cos(slip)
	body.vy = -speed * math.sin(slip)
	body.yawRate = yawRate
	local outcome: Recovery = { settle = math.huge, overcorrect = 0, peakSlip = 0, spun = false, endKmh = 0 }
	local crossed, calm, last = false, 0, slip
	local stop = seconds or 6
	while sim.time < stop do
		local now = -HandlingScenario.bodySlip(sim)
		local steer = 0
		if driver == "keys" then
			local growing = now > last
			if now > math.rad(6) or (now > math.rad(2) and growing) then
				steer = -1
			elseif now < -math.rad(6) or (now < -math.rad(2) and not growing) then
				steer = 1
			end
		elseif driver == "stick" then
			steer = math.clamp(-now / STICK_FULL, -1, 1)
		end
		last = now
		DriveSim.frame(sim, input(setup, 0.3, 0, steer), dt)
		if not moving(sim) then
			continue
		end
		local after = -HandlingScenario.bodySlip(sim)
		outcome.peakSlip = math.max(outcome.peakSlip, math.abs(after))
		outcome.spun = outcome.spun or math.abs(after) > SPIN
		crossed = crossed or after < 0
		if crossed then
			outcome.overcorrect = math.max(outcome.overcorrect, -after)
		end
		calm = if math.abs(after) < CAUGHT then calm + dt else 0
		if calm >= CAUGHT_HOLD and outcome.settle == math.huge then
			outcome.settle = sim.time - CAUGHT_HOLD
		end
	end
	outcome.endKmh = DriveSim.forwardSpeed(sim) / KMH
	return outcome
end

return table.freeze(HandlingScenario)
