--!strict
--[[
	Moves the weather from one look to another with a smoothstep, field by field: numbers and
	{ r, g, b } colours blend linearly, fields named in `cyclic` blend the short way round their
	period (clock time across midnight). A new choice mid-transition starts from what is on
	screen, never from either end. The road's wetness rides along untouched: a choice changes
	where the rain is heading, and the water already on the road dries or builds from there.
]]
export type Blend<T> = { from: T, to: T, elapsed: number, duration: number }
export type Weather<T> = { blend: Blend<T>, wetness: number }
export type Cyclic = { [string]: number }

type Rgb = { r: number, g: number, b: number }

local PresetBlend = {}

local function smoothstep(u: number): number
	local t = math.clamp(u, 0, 1)
	return t * t * (3 - 2 * t)
end

local function around(from: number, to: number, share: number, period: number): number
	if share >= 1 then
		return to
	end
	local delta = (to - from + period / 2) % period - period / 2
	return (from + delta * share) % period
end

local function mixed(from: unknown, to: unknown, share: number, period: number?): unknown
	if typeof(from) == "number" and typeof(to) == "number" then
		if period then
			return around(from, to, share, period)
		end
		return from * (1 - share) + to * share
	end
	local a, b = from :: Rgb, to :: Rgb
	return {
		r = a.r * (1 - share) + b.r * share,
		g = a.g * (1 - share) + b.g * share,
		b = a.b * (1 - share) + b.b * share,
	}
end

-- The look `share` of the way from one look to another (0 gives `from`, 1 gives `to`).
function PresetBlend.mix<T>(from: T, to: T, share: number, cyclic: Cyclic): T
	-- A look is a flat record of numbers and colours; the blend walks it by field name.
	local source, target = from :: any, to :: any
	local result = {}
	for key, value in target do
		result[key] = mixed(source[key], value, share, cyclic[key])
	end
	return (result :: any) :: T
end

function PresetBlend.settled<T>(look: T): Blend<T>
	return { from = look, to = look, elapsed = 0, duration = 0 }
end

-- Smoothstepped progress, 0 to 1.
function PresetBlend.progress<T>(blend: Blend<T>): number
	if blend.duration <= 0 then
		return 1
	end
	return smoothstep(blend.elapsed / blend.duration)
end

function PresetBlend.current<T>(blend: Blend<T>, cyclic: Cyclic): T
	local share = PresetBlend.progress(blend)
	if share >= 1 then
		return blend.to
	end
	return PresetBlend.mix(blend.from, blend.to, share, cyclic)
end

function PresetBlend.advance<T>(blend: Blend<T>, dt: number): Blend<T>
	if dt ~= dt or dt <= 0 or blend.elapsed >= blend.duration then
		return blend
	end
	return {
		from = blend.from,
		to = blend.to,
		elapsed = math.min(blend.elapsed + dt, blend.duration),
		duration = blend.duration,
	}
end

-- Heads for `target` over `duration` seconds, from the look on screen now.
function PresetBlend.retarget<T>(blend: Blend<T>, target: T, duration: number, cyclic: Cyclic): Blend<T>
	return {
		from = PresetBlend.current(blend, cyclic),
		to = target,
		elapsed = 0,
		duration = if duration ~= duration then 0 else math.max(duration, 0),
	}
end

function PresetBlend.weather<T>(look: T, wetness: number): Weather<T>
	return { blend = PresetBlend.settled(look), wetness = wetness }
end

-- A new preset choice. The wetness is carried over unchanged.
function PresetBlend.choose<T>(weather: Weather<T>, target: T, duration: number, cyclic: Cyclic): Weather<T>
	return {
		blend = PresetBlend.retarget(weather.blend, target, duration, cyclic),
		wetness = weather.wetness,
	}
end

return table.freeze(PresetBlend)
