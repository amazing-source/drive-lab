--!strict
--[[
	The help a keyboard or gamepad gets between the device and the steering rack (01 §4). It is
	not part of the car: the physical car is the same whichever preset drives it (08 §0, rule 1),
	and `direct` turns the help off for a wheel or a robot driver. Starting values come from
	01 §4's list; all are tuning, none are data.

	Steering moves as a hand turns a wheel: it speeds up, holds a capped rate, and slows into
	where it is going (Vehicle/InputFilter). The keyboard's times follow the steering research
	of 2026-10-29: 0.4 s to full lock asked about 1,000 degrees a second of the steering wheel,
	faster than NHTSA's 720 degrees a second robot; a brisk human parking turn gives 0.7 to 1.2 s.
	A stopped car does not centre its own wheel, so the return is slow at rest and quick on the
	move, as the road's trail pulls it back.
]]
export type InputHelp = {
	-- Seconds from centre to full lock at a standstill (0: no filter), and the seconds of that
	-- spent speeding up, and again slowing down, at the ends of the move.
	lockTime: number,
	easeTime: number,
	-- Speed (m/s) at which turning in takes twice as long.
	rateHalvingSpeed: number,
	-- Steering toward the other side runs this many times faster than turning in.
	oppositeFactor: number,
	-- Seconds from full lock back to centre at rest and on the move, blended between the two
	-- speeds (m/s) of returnBlend.
	returnTimeStill: number,
	returnTimeMoving: number,
	returnBlend: { from: number, to: number },
	stickExponent: number,
	deadzone: number,
	-- Clamp steering so the front axle stays near its peak slip angle.
	dynamicLimit: boolean,
	targetSlip: number,
	limitMinSpeed: number,
	-- Seconds for a pedal to go from released to full, and back.
	throttleRiseTime: number,
	throttleFallTime: number,
	brakeRiseTime: number,
	brakeFallTime: number,
	-- Seconds the brake, held on its own at a standstill in automatic, takes to select reverse,
	-- and the accelerator in reverse to select first; in reverse the pedals swap, as GTA and Forza
	-- do (Vehicle/Selector). nil: the pedals select nothing and keep their meaning.
	reverseHoldTime: number?,
}

-- Longer than a tap (Config/ControlsHelp.TAP_SECONDS), so a dab of the brake at a standstill
-- selects nothing; shorter than the exit's hold (Config/CarEntry), so reversing is not slower
-- than getting out.
local REVERSE_HOLD_SECONDS = 0.3

local InputHelp = {}

InputHelp.REVERSE_HOLD_SECONDS = REVERSE_HOLD_SECONDS

InputHelp.keyboard = table.freeze({
	-- Was a constant 2.5 of lock a second (0.4 s), twice as fast back, with no easing: the
	-- owner found it abrupt (2026-10-29). The research's 0.9 s still felt too light to the
	-- owner the same day, so 1.3 s, the relaxed end of a human parking turn (about 330 to 400
	-- degrees a second of the steering wheel); the ease and the returns keep their proportions.
	-- Assetto Corsa's keyboard defaults also turn toward the other side about 1.4 times faster
	-- than they turn in, so a slide can be caught.
	lockTime = 1.3,
	easeTime = 0.22,
	rateHalvingSpeed = 25,
	oppositeFactor = 1.4,
	returnTimeStill = 1.3,
	returnTimeMoving = 0.55,
	returnBlend = table.freeze({ from = 2, to = 15 }),
	stickExponent = 1,
	deadzone = 0,
	dynamicLimit = true,
	targetSlip = 0.95,
	limitMinSpeed = 5,
	throttleRiseTime = 0.2,
	throttleFallTime = 0.1,
	brakeRiseTime = 0.12,
	brakeFallTime = 0.08,
	reverseHoldTime = REVERSE_HOLD_SECONDS,
}) :: InputHelp

InputHelp.gamepad = table.freeze({
	-- The thumb already doses the angle, so the pad's filter is quicker than the keyboard's.
	lockTime = 0.5,
	easeTime = 0.08,
	rateHalvingSpeed = 25,
	oppositeFactor = 1.4,
	returnTimeStill = 0.5,
	returnTimeMoving = 0.3,
	returnBlend = table.freeze({ from = 2, to = 15 }),
	stickExponent = 1.4,
	deadzone = 0.1,
	dynamicLimit = true,
	targetSlip = 0.95,
	limitMinSpeed = 5,
	throttleRiseTime = 0.05,
	throttleFallTime = 0.05,
	brakeRiseTime = 0.05,
	brakeFallTime = 0.05,
	reverseHoldTime = REVERSE_HOLD_SECONDS,
}) :: InputHelp

InputHelp.direct = table.freeze({
	lockTime = 0,
	easeTime = 0,
	rateHalvingSpeed = math.huge,
	oppositeFactor = 1,
	returnTimeStill = 0,
	returnTimeMoving = 0,
	returnBlend = table.freeze({ from = 0, to = 1 }),
	stickExponent = 1,
	deadzone = 0,
	dynamicLimit = false,
	targetSlip = 1,
	limitMinSpeed = 0,
	throttleRiseTime = 0,
	throttleFallTime = 0,
	brakeRiseTime = 0,
	brakeFallTime = 0,
}) :: InputHelp

return table.freeze(InputHelp)
