--!strict
--[[
	What a car with an H-pattern manual (Vehicle/HBox) tells the rest of its driver's client each
	frame: the shift state its lever, hand and foot are drawn from, and the instant a shift's gear
	engages (the lever entering its gate, the "SHIFT" press of Rig/ControlPresses). Plain values, so
	Lune can test it.
]]
local HBox = require("../Vehicle/HBox")
local Interface = require("../Vehicle/Interface")
local ShiftPlan = require("../Vehicle/ShiftPlan")
local Types = require("../Config/Cars/Types")

export type Readout = {
	ClutchPedal: number,
	ClutchFoot: number,
	ShiftHand: number,
	ShiftFrom: number,
	ShiftTo: number,
	ShiftElapsed: number,
	LeverColumn: number,
	LeverRow: number,
	KnobDown: number,
}

local ShiftSync = {}

-- The attributes a manual car's driver publishes, by name (Controllers/Driving): the clutch in
-- effect (0 up, 1 down), how far the left foot is on it and the right hand on the knob (0 to 1),
-- the shift running (from and to the same gear, and 0 s, when none is), and the lever's place and
-- knob (ShiftSync.lever) for the box `hbox` with the H `gates`.
function ShiftSync.readout(
	telemetry: Interface.Telemetry,
	hbox: HBox.State,
	gates: { [number]: Types.Gate }
): Readout
	local column, row, knob = ShiftSync.lever(hbox, gates, telemetry.gear)
	return {
		ClutchPedal = telemetry.clutchPedal,
		ClutchFoot = telemetry.footAt,
		ShiftHand = telemetry.handAt,
		ShiftFrom = telemetry.shiftFrom,
		ShiftTo = telemetry.shiftTo,
		ShiftElapsed = telemetry.shiftElapsed,
		LeverColumn = column,
		LeverRow = row,
		KnobDown = knob,
	}
end

-- Where the lever is in its H (column and row, Vehicle/ShiftPlan) and how far its knob is pushed
-- down (0 to 1): along the shift running, else in the gate of `gear`.
function ShiftSync.lever(
	hbox: HBox.State,
	gates: { [number]: Types.Gate },
	gear: number
): (number, number, number)
	local plan = hbox.plan
	if plan then
		local column, row = ShiftPlan.lever(plan, gates, hbox.time)
		return column, row, ShiftPlan.knob(plan, hbox.time)
	end
	local gate = gates[gear]
	return gate.column, gate.row, 0
end

-- Whether a shift's gear engaged between the frame whose gear was `previousGear` and this one: the
-- gear flipped while a shift runs, onto its target.
function ShiftSync.engaged(previousGear: number?, telemetry: Interface.Telemetry): boolean
	return previousGear ~= nil
		and telemetry.gear ~= previousGear
		and telemetry.shiftTo ~= telemetry.shiftFrom
		and telemetry.gear == telemetry.shiftTo
end

return table.freeze(ShiftSync)
