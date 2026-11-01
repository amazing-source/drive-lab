--!strict
--[[
	One shift of an H-pattern gearbox, planned when it starts (issue #209): the physics follows it
	and the driver's animation samples it at the same time from the start, so the lever reaches the
	target gate on the frame the gear engages, in Play and offline alike.

	Times are seconds from the start. The left foot and the right hand first reach the clutch and
	the knob (shortened by how far they already are), the clutch goes down, the lever leaves its gate
	for the neutral rail, crosses to the target's column (pushing the knob down first on a path into
	reverse), enters the target gate, where the gear engages, and the clutch comes back up. The
	lever moves on one smooth progress along that path, at rest only in the two gates.
]]
local Types = require("../Config/Cars/Types")

export type Phase = "reach" | "clutchIn" | "leaveGate" | "crossNeutral" | "enterGate" | "clutchOut" | "done"

export type Plan = {
	from: number,
	to: number,
	-- Where the lever and the pedal were when the plan started (a shift retargeted mid-way starts
	-- from the lever's place, not its gate).
	startColumn: number,
	startRow: number,
	startPedal: number,
	-- The path pushes the knob down before crossing into reverse.
	knobDown: boolean,
	-- Seconds from the start: the hand on the knob, the clutch starting down and fully down, the
	-- lever on the rail, at the target's column, in the target gate (the gear engages), the clutch
	-- fully up.
	reachEnd: number,
	pressStart: number,
	clutchDown: number,
	leverOut: number,
	across: number,
	gateIn: number,
	clutchUp: number,
	-- The lever's path as budgets (s) laid end to end: leave, push, cross, enter.
	leaveBudget: number,
	pushBudget: number,
	crossBudget: number,
	enterBudget: number,
}

local ShiftPlan = {}

-- Ease with zero speed at both ends and a continuous speed between.
local function ease(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

-- The u in [0, 1] whose ease is `share`.
local function unease(share: number): number
	local low, high = 0, 1
	for _ = 1, 40 do
		local middle = (low + high) / 2
		if ease(middle) < share then
			low = middle
		else
			high = middle
		end
	end
	return (low + high) / 2
end

local function travel(plan: Plan): number
	return plan.leaveBudget + plan.pushBudget + plan.crossBudget + plan.enterBudget
end

-- The time at which the lever's progress reaches `budget` seconds of its path.
local function timeAt(plan: Plan, budget: number): number
	local total = travel(plan)
	if total <= 0 then
		return plan.clutchDown
	end
	return plan.clutchDown + total * unease(budget / total)
end

-- A plan from gear `from` to gear `to`. `handAt` and `footAt` (0 to 1) say how far the hand is
-- already on the knob and the foot on the clutch; a retarget passes the lever's place and the
-- pedal it starts from.
function ShiftPlan.plan(
	gates: { [number]: Types.Gate },
	timing: Types.ShiftTiming,
	from: number,
	to: number,
	handAt: number,
	footAt: number,
	startColumn: number?,
	startRow: number?,
	startPedal: number?
): Plan
	local origin, target = gates[from], gates[to]
	assert(origin and target, `the gearbox has no gate for {from} or {to}`)
	local column = startColumn or origin.column
	local row = startRow or origin.row
	local pedal = startPedal or 0
	local reachEnd = timing.reach * (1 - math.clamp(handAt, 0, 1))
	local footEnd = timing.footMove * (1 - math.clamp(footAt, 0, 1))
	local pressStart = math.max(reachEnd, footEnd)
	local columns = math.abs(target.column - column)
	local plan: Plan = {
		from = from,
		to = to,
		startColumn = column,
		startRow = row,
		startPedal = pedal,
		knobDown = to == -1 and from ~= -1,
		reachEnd = reachEnd,
		pressStart = pressStart,
		clutchDown = pressStart + timing.clutchIn * (1 - pedal),
		leverOut = 0,
		across = 0,
		gateIn = 0,
		clutchUp = 0,
		leaveBudget = timing.leave * math.abs(row),
		pushBudget = if to == -1 and from ~= -1 then timing.push else 0,
		crossBudget = if columns > 1e-9 then timing.crossBase + timing.crossPerColumn * columns else 0,
		enterBudget = timing.enter * math.abs(target.row),
	}
	plan.gateIn = plan.clutchDown + travel(plan)
	plan.leverOut = timeAt(plan, plan.leaveBudget)
	plan.across = timeAt(plan, plan.leaveBudget + plan.pushBudget + plan.crossBudget)
	plan.clutchUp = plan.gateIn + timing.clutchOut
	return plan
end

function ShiftPlan.phase(plan: Plan, t: number): Phase
	if t < plan.pressStart then
		return "reach"
	elseif t < plan.clutchDown then
		return "clutchIn"
	elseif t < plan.leverOut then
		return "leaveGate"
	elseif t < plan.across then
		return "crossNeutral"
	elseif t < plan.gateIn then
		return "enterGate"
	elseif t < plan.clutchUp then
		return "clutchOut"
	end
	return "done"
end

-- How far along its path (seconds of budget) the lever is at `t`.
local function progress(plan: Plan, t: number): number
	local total = travel(plan)
	if total <= 0 or t >= plan.gateIn then
		return total
	end
	return total * ease((t - plan.clutchDown) / total)
end

-- The lever's place (column, row) at `t`: out of its gate, along the rail, into the target gate.
function ShiftPlan.lever(plan: Plan, gates: { [number]: Types.Gate }, t: number): (number, number)
	local target = gates[plan.to]
	if t >= plan.gateIn then
		return target.column, target.row
	end
	local done = progress(plan, t)
	if done < plan.leaveBudget then
		return plan.startColumn, plan.startRow * (1 - done / plan.leaveBudget)
	end
	done -= plan.leaveBudget + plan.pushBudget
	if done < 0 then
		return plan.startColumn, 0
	end
	if done < plan.crossBudget then
		return plan.startColumn + (target.column - plan.startColumn) * done / plan.crossBudget, 0
	end
	done -= plan.crossBudget
	if plan.enterBudget <= 0 then
		return target.column, target.row
	end
	return target.column, target.row * math.min(1, done / plan.enterBudget)
end

-- How far the knob is pushed down (0 to 1) at `t`: during the push on a path into reverse, and held
-- down until the lever is in the gate.
function ShiftPlan.knob(plan: Plan, t: number): number
	if not plan.knobDown or t >= plan.gateIn then
		return 0
	end
	local done = progress(plan, t) - plan.leaveBudget
	if done <= 0 then
		return 0
	end
	return math.min(1, done / plan.pushBudget)
end

-- The clutch pedal (0 up, 1 down) the plan works at `t`.
function ShiftPlan.clutch(plan: Plan, t: number): number
	if t < plan.pressStart then
		return plan.startPedal
	elseif t < plan.clutchDown then
		return plan.startPedal
			+ (1 - plan.startPedal) * (t - plan.pressStart) / (plan.clutchDown - plan.pressStart)
	elseif t < plan.gateIn then
		return 1
	elseif t < plan.clutchUp then
		return 1 - (t - plan.gateIn) / (plan.clutchUp - plan.gateIn)
	end
	return 0
end

return table.freeze(ShiftPlan)
