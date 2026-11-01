--!strict
--[[
	The H-pattern manual's own parts (issue #209), run by Vehicle/Gearbox for a gearbox of kind
	"manual": the shift as a ShiftPlan, so the gear engages on the frame the lever reaches its
	gate; the clutch as a pedal through its bite; the stall; and the driver's right hand and left
	foot, as shares from the wheel or the floor (0) to the knob or the pedal (1), which a plan's
	reach starts from.
]]
local ShiftPlan = require("./ShiftPlan")
local Types = require("../Config/Cars/Types")

-- Why a shift was refused: it would over-rev, or the player's clutch was up (a grind).
export type Refusal = "overRev" | "clutchUp"

export type State = {
	plan: ShiftPlan.Plan?,
	-- Seconds since the plan started.
	time: number,
	-- A shift asked for once the plan's gear had engaged, started when the plan ends.
	queued: number?,
	handAt: number,
	footAt: number,
	-- Seconds since the last plan ended.
	sincePlan: number,
	-- The pedal in effect (0 up, 1 down): the plan's, the automatic clutch's or the player's.
	pedal: number,
	stalled: boolean,
	-- Why the shift asked for this frame was refused, if it was.
	refusal: Refusal?,
}

local HBox = {}

function HBox.newState(): State
	return {
		plan = nil,
		time = 0,
		queued = nil,
		handAt = 0,
		footAt = 0,
		sincePlan = math.huge,
		pedal = 0,
		stalled = false,
		refusal = nil,
	}
end

-- The clutch's share of its torque at `pedal`: none from the bite point down, all of it once the
-- pedal is a bite width further up.
function HBox.engagement(manual: Types.ManualGearboxConfig, pedal: number): number
	return math.clamp((manual.bitePoint - pedal) / manual.biteWidth, 0, 1)
end

-- The pedal that gives `engagement`: where the automatic clutch's foot is.
function HBox.pedalFor(manual: Types.ManualGearboxConfig, engagement: number): number
	if engagement <= 0 then
		return 1
	elseif engagement >= 1 then
		return 0
	end
	return manual.bitePoint - manual.biteWidth * engagement
end

-- Starts a shift from `gear` to `to`. A plan still short of its gate is replaced by one from the
-- lever's place, with the clutch where it is; once the plan's gear has engaged, the shift waits
-- for the plan's end.
function HBox.shift(manual: Types.ManualGearboxConfig, state: State, gear: number, to: number)
	local plan = state.plan
	if plan == nil then
		state.plan = ShiftPlan.plan(
			manual.gates,
			manual.timing,
			gear,
			to,
			state.handAt,
			state.footAt,
			nil,
			nil,
			state.pedal
		)
		state.time = 0
	elseif state.time < plan.gateIn then
		local column, row = ShiftPlan.lever(plan, manual.gates, state.time)
		local pedal = ShiftPlan.clutch(plan, state.time)
		state.plan = ShiftPlan.plan(
			manual.gates,
			manual.timing,
			plan.from,
			to,
			state.handAt,
			state.footAt,
			column,
			row,
			pedal
		)
		state.time = 0
	else
		state.queued = to
	end
end

-- The gear a shift asked for now would start from: the plan's or the queued target, or `gear`.
function HBox.aimedGear(state: State, gear: number): number
	local plan = state.plan
	if plan == nil then
		return gear
	end
	return state.queued or plan.to
end

-- Moves the hand toward the knob while a plan runs, for the linger after one, or when `ready`, and
-- back to the wheel otherwise; the foot goes to the pedal on the same terms and whenever the
-- pedal is down.
function HBox.moveLimbs(manual: Types.ManualGearboxConfig, state: State, ready: boolean, dt: number)
	local timing = manual.timing
	local hand = state.plan ~= nil or state.sincePlan < timing.linger or ready
	state.handAt = if hand
		then math.min(1, state.handAt + dt / timing.reach)
		else math.max(0, state.handAt - dt / timing.release)
	local foot = hand or state.pedal > 0
	state.footAt = if foot
		then math.min(1, state.footAt + dt / timing.footMove)
		else math.max(0, state.footAt - dt / timing.footMove)
end

return table.freeze(HBox)
