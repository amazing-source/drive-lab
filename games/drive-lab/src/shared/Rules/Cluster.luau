--!strict
--[[
	What a car's instrument cluster shows for a given state, on its own face (Config/Cluster Face):
	how many rev cells are lit, which of them sit in the red, how far to turn the wipe that reveals
	them, the start-up sweep, the gear's label, the limiter's flashing and the text under the gear.
]]
local Cluster = require("../Config/Cluster")
local DriverAssists = require("./DriverAssists")

local Rules = {}

-- A cell lights as soon as the revs enter its band, so the first red one lights past the redline.
function Rules.litCells(face: Cluster.Face, rpm: number): number
	return math.clamp(math.ceil(rpm / face.dialMaxRpm * face.cells - 1e-9), 0, face.cells)
end

-- Whether cell `index` (1-based) lies at or above the redline.
function Rules.isRed(face: Cluster.Face, index: number): boolean
	return (index - 1) / face.cells * face.dialMaxRpm >= face.redlineRpm - 1e-9
end

--[[
	Rotation, in degrees, of the gradient that shows the first `cells` cells. The lit image is
	opaque on one side of a line through the dial's centre and clear on the other; turned so the
	line lies along the edge after the last lit cell, it shows every cell before that edge. One
	line is enough because the dial sweeps less than half a turn.
]]
function Rules.wipeRotation(face: Cluster.Face, cells: number): number
	return face.dialStart + face.dialSweep * cells / face.cells + 90
end

-- The revs the dial shows `elapsed` seconds into the start-up sweep: up to the top and back.
function Rules.startupRpm(face: Cluster.Face, elapsed: number): number?
	if elapsed < 0 or elapsed >= face.startupSeconds then
		return nil
	end
	return face.dialMaxRpm * math.sin(math.pi * elapsed / face.startupSeconds)
end

function Rules.gearLabel(gear: number): string
	if gear < 0 then
		return "R"
	elseif gear == 0 then
		return "N"
	end
	return tostring(gear)
end

-- The text under the gear: LAUNCH while launch control is armed or launching, else the ESC light.
function Rules.lampText(lamp: DriverAssists.Lamp, launching: boolean): string
	if launching then
		return Cluster.LAUNCH_TEXT
	elseif lamp == "EscOff" then
		return "ESC OFF"
	end
	return if lamp == "Esc" then "ESC" else ""
end

-- Whether the lit cells show at time `now`: always, except flashing on the limiter.
function Rules.cellsShown(face: Cluster.Face, limiter: boolean, now: number): boolean
	return not limiter or math.floor(now * face.limiterFlashHz * 2) % 2 == 0
end

return table.freeze(Rules)
