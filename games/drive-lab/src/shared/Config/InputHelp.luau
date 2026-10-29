--!strict
--[[
	The help a keyboard or gamepad gets between the device and the steering rack (01 §4). It is
	not part of the car: the physical car is the same whichever preset drives it (08 §0, rule 1),
	and `direct` turns the help off for a wheel or a robot driver. Starting values come from
	01 §4's list; all are tuning, none are data.
]]
export type InputHelp = {
	-- Share of full lock per second when turning in at a standstill.
	steerRate: number,
	-- Returning toward centre is this many times faster than turning in.
	returnRateFactor: number,
	-- Speed (m/s) at which the steering rate has halved.
	rateHalvingSpeed: number,
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
	steerRate = 2.5,
	returnRateFactor = 2,
	rateHalvingSpeed = 25,
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
	steerRate = 4,
	returnRateFactor = 2,
	rateHalvingSpeed = 25,
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
	steerRate = math.huge,
	returnRateFactor = 1,
	rateHalvingSpeed = math.huge,
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
