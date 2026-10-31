--!strict
--[[
	What a car with an H-pattern manual (Vehicle/HBox) tells the rest of its driver's client each
	frame: the shift state its lever, hand and foot are drawn from, and the instant a shift's gear
	engages (the lever entering its gate, the "SHIFT" press of Rig/ControlPresses). Plain values, so
	Lune can test it.
]]
local Interface = require("../Vehicle/Interface")

export type Readout = {
	ClutchPedal: number,
	ClutchFoot: number,
	ShiftHand: number,
	ShiftFrom: number,
	ShiftTo: number,
	ShiftElapsed: number,
}

local ShiftSync = {}

-- The attributes a manual car's driver publishes, by name (Controllers/Driving): the clutch in
-- effect (0 up, 1 down), how far the left foot is on it and the right hand on the knob (0 to 1),
-- and the shift running (from and to the same gear, and 0 s, when none is).
function ShiftSync.readout(telemetry: Interface.Telemetry): Readout
	return {
		ClutchPedal = telemetry.clutchPedal,
		ClutchFoot = telemetry.footAt,
		ShiftHand = telemetry.handAt,
		ShiftFrom = telemetry.shiftFrom,
		ShiftTo = telemetry.shiftTo,
		ShiftElapsed = telemetry.shiftElapsed,
	}
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
