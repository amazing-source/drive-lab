--!strict
--[[
	Motion blur from how the camera moves, in plain numbers. Roblox draws no per-pixel motion
	blur, so it is built from what it has: a full-screen blur sized by how fast the camera turns,
	easing in quicker than out, and a depth of field that softens the world moving past while
	what rides with the camera stays sharp (the car in the chase view, the cabin in the cockpit),
	growing with the car's speed and with how hard it pulls. The pull's blur can be drawn as a
	full-screen blur instead, to compare: it blurs the car and the cabin too.
]]
local MotionBlur = {}

-- Half-lives (s) of a blur rising to a larger target and falling to a smaller one.
export type Easing = { rise: number, fall: number }

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

-- km/h: the chase view's near blur and the cockpit's and hood's far blur grow from `from` to
-- their full `near` and `far` at `to`.
export type Speed = { from: number, to: number, near: number, far: number, exponent: number }

-- How the pull's blur is drawn: on the depth of field, or as one blur over the whole view.
export type PullStyle = "DepthOfField" | "FullScreen"

export type Acceleration = {
	-- Scales the pull's blur in either style: 0 turns it off, 2 doubles it.
	intensity: number,
	style: PullStyle,
	-- g of pull where the blur starts and where it is full, eased by `exponent`.
	fromG: number,
	toG: number,
	exponent: number,
	rise: number,
	fall: number,
	-- The eased pull only nears 0: under this share it counts as none, so the depth of field
	-- is switched off rather than drawn for nothing once the car stops pulling.
	off: number,
	-- Depth of field at a full pull: `near` on the road between the chase camera and the car,
	-- `far` on the world past the car, `cabin` on the world past the cabin in the cockpit and
	-- hood views.
	near: number,
	far: number,
	cabin: number,
	-- The full-screen style's blur at a full pull, pixels.
	fullScreen: number,
}

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
function MotionBlur.follow(current: number, target: number, dt: number, easing: Easing): number
	local halfLife = if target > current then easing.rise else easing.fall
	return current + (target - current) * (1 - 0.5 ^ (math.max(dt, 0) / halfLife))
end

local function speedShare(speedKmh: number, speed: Speed): number
	local kmh = if speedKmh == speedKmh then math.abs(speedKmh) else 0
	return share(kmh, speed.from, speed.to) ^ speed.exponent
end

-- The chase view's near depth of field at a speed, either way.
function MotionBlur.speedNear(speedKmh: number, speed: Speed): number
	return speed.near * speedShare(speedKmh, speed)
end

-- The cockpit's and hood's far depth of field at a speed, either way.
function MotionBlur.speedFar(speedKmh: number, speed: Speed): number
	return speed.far * speedShare(speedKmh, speed)
end

-- The share of the acceleration blur a pull of `g` asks for, 0 to 1: none braking or coasting.
local function pullStrength(pull: number, acceleration: Acceleration): number
	local share = if pull == pull then math.clamp(pull, 0, 1) else 0
	return if share < acceleration.off then 0 else share * math.max(acceleration.intensity, 0)
end

function MotionBlur.pullShare(g: number, acceleration: Acceleration): number
	if g ~= g then
		return 0
	end
	return share(g, acceleration.fromG, acceleration.toG) ^ acceleration.exponent
end

-- The depth of field's near and far intensities, 0 to 1, in a view at a speed and an eased pull
-- share: the chase view blurs the road before the car and the world past it, the cockpit and
-- hood views the world past the cabin; on foot nothing.
function MotionBlur.depth(
	view: string,
	speedKmh: number,
	pull: number,
	speed: Speed,
	acceleration: Acceleration
): (number, number)
	local strength = if acceleration.style == "DepthOfField" then pullStrength(pull, acceleration) else 0
	if view == "Chase" then
		local near = MotionBlur.speedNear(speedKmh, speed) + acceleration.near * strength
		return math.min(near, 1), math.min(acceleration.far * strength, 1)
	elseif view == "Cockpit" or view == "Hood" then
		return 0, math.min(MotionBlur.speedFar(speedKmh, speed) + acceleration.cabin * strength, 1)
	end
	return 0, 0
end

-- The full-screen style's blur (pixels) at an eased pull share; none in the other style.
function MotionBlur.pulseSize(pull: number, acceleration: Acceleration): number
	if acceleration.style ~= "FullScreen" then
		return 0
	end
	return acceleration.fullScreen * pullStrength(pull, acceleration)
end

return table.freeze(MotionBlur)
