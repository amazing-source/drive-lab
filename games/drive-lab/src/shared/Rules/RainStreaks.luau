--!strict
--[[
	How a sprite of the rain pack becomes a streak of a chosen length and width on screen. The
	sprite's width is not the streak's: a particle's Size and Squash together set both.

	Measured in Studio (2026-10-28, rain_streaks_02 at Size 8, 40 studs away, VelocityParallel
	turned a quarter): a particle of Size S draws a quad 2S on a side. A Squash s >= 0 draws it
	(1 + s) times longer along its motion and (1 + s) times thinner; a negative one 1 / (1 - s)
	times as long and (1 - s) times as wide (s = 1: x1.97 long, x0.54 wide; s = 2: x2.9, x0.38;
	s = -0.5: x0.67, x1.51).

	A streak's length is the drop's fall over an exposure (Garg and Nayar, 2007: a drop at
	v m/s smears v * T over an exposure T), clamped. Only the fall: the streaks stay vertical
	in the world, so a moving camera does not lengthen or tilt them (owner, 2026-10-28).
]]
export type Fit = { size: number, squash: number }

local RainStreaks = {}

local function positive(value: number): number
	if value ~= value or value == math.huge then
		return 0
	end
	return math.max(value, 0)
end

-- The streak's visible length: the fall over the exposure, at most maxLength.
function RainStreaks.length(fall: number, exposure: number, maxLength: number): number
	return math.min(positive(fall) * positive(exposure), positive(maxLength))
end

-- How much longer along its motion a Squash draws a particle (its width shrinks as much).
function RainStreaks.stretch(squash: number): number
	if squash ~= squash then
		return 1
	end
	return if squash >= 0 then 1 + squash else 1 / (1 - squash)
end

-- The Squash that stretches a particle by `factor` along its motion.
function RainStreaks.squashFor(factor: number): number
	if factor ~= factor or factor <= 0 or factor == math.huge then
		return 0
	end
	return if factor >= 1 then factor - 1 else 1 - 1 / factor
end

-- The Size and Squash that draw a sprite's streak `length` long and `width` wide, where the
-- streak spans `along` of the sprite's height and `across` of its width.
function RainStreaks.fit(length: number, width: number, along: number, across: number): Fit
	if along <= 0 or across <= 0 or along ~= along or across ~= across then
		return { size = 0, squash = 0 }
	end
	local quadLength, quadWidth = positive(length) / along, positive(width) / across
	if quadLength <= 0 or quadWidth <= 0 then
		return { size = 0, squash = 0 }
	end
	return {
		size = math.sqrt(quadLength * quadWidth) / 2,
		squash = RainStreaks.squashFor(math.sqrt(quadLength / quadWidth)),
	}
end

-- Distance from a particle's centre to the end of its quad along its motion.
function RainStreaks.halfLength(size: number, squash: number): number
	return positive(size) * RainStreaks.stretch(squash)
end

return table.freeze(RainStreaks)
