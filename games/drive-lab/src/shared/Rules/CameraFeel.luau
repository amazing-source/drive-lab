--!strict
--[[
	The numbers behind the on-foot camera: the field of view a ground speed calls for, and the
	frame-rate independent ease both the orbit and the field of view follow.
]]
local CameraFeel = require("../Config/CameraFeel")

local Rules = {}

-- Base FOV at walking pace or slower, rising linearly to SPRINT_FOV at sprint speed.
function Rules.fieldOfView(groundSpeed: number, walkSpeed: number, sprintSpeed: number): number
	local share = math.clamp((groundSpeed - walkSpeed) / (sprintSpeed - walkSpeed), 0, 1)
	return CameraFeel.BASE_FOV + (CameraFeel.SPRINT_FOV - CameraFeel.BASE_FOV) * share
end

-- The share of the remaining gap to close this frame, so the gap halves every `halfLife` s.
function Rules.blend(dt: number, halfLife: number): number
	return 1 - 0.5 ^ (dt / halfLife)
end

return table.freeze(Rules)
