--!strict
--[[
	Motion blur from how the camera moves, in plain numbers. Roblox draws no per-pixel motion
	blur, so it is built from what it has: a full-screen blur sized by how fast the camera turns,
	easing in quicker than out, and a near depth of field that grows with the car's speed.
]]
local MotionBlur = {}

export type Rotation = {
	-- Degrees a second where the blur starts and where it reaches `max` pixels.
	from: number,
	to: number,
	max: number,
	exponent: number,
	-- Half-lives (s) of the blur rising to a larger target and falling to a smaller one.
	rise: number,
	fall: number,
	-- Degrees in one frame past which the turn is a camera cut, not a motion.
	cut: number,
}

export type Speed = { from: number, to: number, near: number, exponent: number }

local function share(value: number, from: number, to: number): number
	return math.clamp((value - from) / (to - from), 0, 1)
end

-- Degrees a second the camera turned over `dt`, or nil for a cut: a respawn or a change of view
-- must not blur.
function MotionBlur.turnRate(degrees: number, dt: number, cut: number): number?
	if dt <= 0 or degrees ~= degrees or degrees > cut then
		return nil
	end
	return math.abs(degrees) / dt
end

-- The blur size (pixels) a turn rate asks for.
function MotionBlur.rotationSize(rate: number, rotation: Rotation): number
	if rate ~= rate then
		return 0
	end
	return rotation.max * share(rate, rotation.from, rotation.to) ^ rotation.exponent
end

-- The blur moved toward `target` over `dt`, quicker rising than falling, at any frame rate.
function MotionBlur.follow(current: number, target: number, dt: number, rotation: Rotation): number
	local halfLife = if target > current then rotation.rise else rotation.fall
	return current + (target - current) * (1 - 0.5 ^ (math.max(dt, 0) / halfLife))
end

-- The near depth of field's intensity at a speed, either way.
function MotionBlur.speedNear(speedKmh: number, speed: Speed): number
	local kmh = if speedKmh == speedKmh then math.abs(speedKmh) else 0
	return speed.near * share(kmh, speed.from, speed.to) ^ speed.exponent
end

return table.freeze(MotionBlur)
