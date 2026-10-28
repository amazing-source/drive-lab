--!strict
--[[
	Where a character's head points, as a yaw (positive = left) and a pitch (positive = up)
	relative to its body. The owning client derives them from its camera; every other client
	receives them through the server and eases toward them.
]]
local Look = require("../Config/Look")

export type Angles = { yaw: number, pitch: number }

local HeadLook = {}

local function clamp(angles: Angles): Angles
	return {
		yaw = math.clamp(angles.yaw, -Look.MAX_YAW, Look.MAX_YAW),
		pitch = math.clamp(angles.pitch, -Look.MAX_PITCH_DOWN, Look.MAX_PITCH_UP),
	}
end

-- `x, y, z` is the look direction in the body's frame, where forward is -Z and up is +Y.
-- Yaw is the sine of the sideways part, the usual R6 head script's choice: a look back toward
-- the face folds onto the front, so a camera facing the character has the head look back at
-- it, and the yaw never jumps between its two limits as the camera passes behind.
function HeadLook.fromDirection(x: number, y: number, z: number): Angles
	local length = math.sqrt(x * x + y * y + z * z)
	if length < 1e-6 then
		return { yaw = 0, pitch = 0 }
	end
	return clamp({
		yaw = math.asin(math.clamp(-x / length, -1, 1)),
		pitch = math.asin(math.clamp(y / length, -1, 1)),
	})
end

function HeadLook.parse(payload: unknown): Angles?
	if typeof(payload) ~= "table" then
		return nil
	end
	local yaw, pitch = (payload :: { [unknown]: unknown }).yaw, (payload :: { [unknown]: unknown }).pitch
	if typeof(yaw) ~= "number" or typeof(pitch) ~= "number" then
		return nil
	end
	if yaw ~= yaw or pitch ~= pitch or math.abs(yaw) == math.huge or math.abs(pitch) == math.huge then
		return nil
	end
	return clamp({ yaw = yaw, pitch = pitch })
end

function HeadLook.differs(a: Angles, b: Angles): boolean
	return math.abs(a.yaw - b.yaw) >= Look.SEND_THRESHOLD
		or math.abs(a.pitch - b.pitch) >= Look.SEND_THRESHOLD
end

-- Frame-rate independent easing: the gap halves every `halfLife` seconds (by default the
-- replicated head's SMOOTHING_HALF_LIFE).
function HeadLook.approach(current: Angles, target: Angles, dt: number, halfLife: number?): Angles
	local keep = 0.5 ^ (dt / (halfLife or Look.SMOOTHING_HALF_LIFE))
	return {
		yaw = target.yaw + (current.yaw - target.yaw) * keep,
		pitch = target.pitch + (current.pitch - target.pitch) * keep,
	}
end

return table.freeze(HeadLook)
