--!strict
--[[
	What the instrument cluster shows for a given state: how many rev cells are lit, which of them
	sit in the red, how far to turn the wipe that reveals them, the start-up sweep, the gear's
	label and the limiter's flashing.
]]
local Cluster = require("../Config/Cluster")

local Rules = {}

-- A cell lights as soon as the revs enter its band, so the first red one lights past the redline.
function Rules.litCells(rpm: number): number
	return math.clamp(math.ceil(rpm / Cluster.DIAL_MAX_RPM * Cluster.CELLS - 1e-9), 0, Cluster.CELLS)
end

-- Whether cell `index` (1-based) lies at or above the redline.
function Rules.isRed(index: number): boolean
	return (index - 1) / Cluster.CELLS * Cluster.DIAL_MAX_RPM >= Cluster.REDLINE_RPM - 1e-9
end

--[[
	Rotation, in degrees, of the gradient that shows the first `cells` cells. The lit image is
	opaque on one side of a line through the dial's centre and clear on the other; turned so the
	line lies along the edge after the last lit cell, it shows every cell before that edge. One
	line is enough because the dial sweeps less than half a turn.
]]
function Rules.wipeRotation(cells: number): number
	return Cluster.DIAL_START + Cluster.DIAL_SWEEP * cells / Cluster.CELLS + 90
end

-- The revs the dial shows `elapsed` seconds into the start-up sweep: up to the top and back.
function Rules.startupRpm(elapsed: number): number?
	if elapsed < 0 or elapsed >= Cluster.STARTUP_SECONDS then
		return nil
	end
	return Cluster.DIAL_MAX_RPM * math.sin(math.pi * elapsed / Cluster.STARTUP_SECONDS)
end

function Rules.gearLabel(gear: number): string
	if gear < 0 then
		return "R"
	elseif gear == 0 then
		return "N"
	end
	return tostring(gear)
end

-- Whether the lit cells show at time `now`: always, except flashing on the limiter.
function Rules.cellsShown(limiter: boolean, now: number): boolean
	return not limiter or math.floor(now * Cluster.LIMITER_FLASH_HZ * 2) % 2 == 0
end

return table.freeze(Rules)
