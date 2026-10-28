--!strict
--[[
	What the driving HUD shows for a given state: how much of each rev segment is lit, where its
	red zone starts, whether the lit segments flash, and the HUD's display modes. Plain numbers.
]]
local Hud = {}

export type Mode = "Full" | "Minimal" | "Off"

local MODES: { Mode } = { "Full", "Minimal", "Off" }

function Hud.nextMode(mode: Mode): Mode
	local index = table.find(MODES, mode) or 1
	return MODES[index % #MODES + 1]
end

-- Share of rev segment `index` lying below `rpm`, 0 to 1, segment 1 starting at 0 rpm: how much
-- of it the revs light, or, given the redline, where its red zone starts.
function Hud.segmentShare(rpm: number, index: number, perSegment: number): number
	return math.clamp(rpm / perSegment - (index - 1), 0, 1)
end

-- Whether the lit segments flash for the upshift: only in manual, past the shift point, in the
-- lit half of a blink (the automatic shifts by itself, so a flash would be noise).
function Hud.shiftFlash(rpm: number, shiftAt: number, manual: boolean, time: number, hz: number): boolean
	return manual and rpm >= shiftAt and (time * hz) % 1 < 0.5
end

return table.freeze(Hud)
