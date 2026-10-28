--!strict
--[[
	The numbers behind the driving cameras: easing toward a target and the field of view a speed
	calls for.
]]
local CarCamera = require("../Config/CarCamera")

local Rules = {}

-- Share of the remaining gap closed this frame; the gap halves every `halfLife` seconds.
function Rules.blend(dt: number, halfLife: number): number
	return 1 - 0.5 ^ (dt / halfLife)
end

function Rules.fieldOfView(speedKmh: number): number
	return CarCamera.BASE_FOV + CarCamera.FOV_GAIN * math.clamp(speedKmh / CarCamera.FOV_SPEED, 0, 1)
end

-- Degrees the view widens under a pull of `longitudinalG`: none when braking or coasting.
function Rules.kickTarget(longitudinalG: number): number
	local g = if longitudinalG == longitudinalG then longitudinalG else 0
	return CarCamera.FOV_KICK.perG * math.clamp(g, 0, CarCamera.FOV_KICK.maxG)
end

-- The kick moved toward its target over `dt`, quicker in than out.
function Rules.easeKick(current: number, target: number, dt: number): number
	local kick = CarCamera.FOV_KICK
	return current
		+ (target - current) * Rules.blend(dt, if target > current then kick.attack else kick.release)
end

return table.freeze(Rules)
