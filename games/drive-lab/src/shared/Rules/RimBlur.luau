--!strict
--[[
	How blurred a wheel's rim looks at its spin: the sharp rim face fades out and a disc carrying
	the rim's blurred image fades in, as Assetto Corsa swaps in pre-blurred rim meshes. A real
	camera smears the spokes at speed, and a rendered frame cannot: past a spin the spokes look
	frozen or turning backwards (the wagon-wheel effect), so the blur has to be complete before it.
]]

export type Tuning = {
	-- Wheel spin, rad/s, at which the blur starts and where it is complete.
	from: number,
	to: number,
}

-- What each layer of one wheel shows: whether the car's own wheel is swapped for the split
-- pieces, and the Transparency of the sharp face and of the blurred disc.
export type Layers = { swapped: boolean, face: number, disc: number }

local RimBlur = {}

-- NaN and the infinities read as 0: a broken speed is a stopped wheel, never a blurred one.
local function finite(value: number): number
	return if value == value and math.abs(value) < math.huge then value else 0
end

-- Rad/s of a wheel rolling without slip at `speed` m/s, either way, on a tyre of `radius` m.
function RimBlur.spin(speed: number, radius: number): number
	assert(radius > 0, "a wheel needs a radius")
	return math.abs(finite(speed)) / radius
end

-- 0 sharp to 1 blurred, eased at both ends so the fade never starts or stops with a step.
function RimBlur.share(tuning: Tuning, spin: number): number
	local t = math.clamp((finite(spin) - tuning.from) / (tuning.to - tuning.from), 0, 1)
	return t * t * (3 - 2 * t)
end

-- At no blur the car's own wheel shows and nothing else; at any blur the pieces stand in for
-- it, the face fading out as the disc fades in. The pieces together are the wheel, so the swap
-- itself is invisible.
function RimBlur.layers(share: number): Layers
	local blur = math.clamp(finite(share), 0, 1)
	return { swapped = blur > 0, face = blur, disc = 1 - blur }
end

-- The lowest spin, rad/s, at which a rim that repeats `repeats` times round looks still at
-- `frameRate`: it turns one repeat a frame. It starts to look wrong from half that.
function RimBlur.frozenSpin(repeats: number, frameRate: number): number
	return 2 * math.pi / repeats * frameRate
end

-- Whether `layers` differ from `shown` by at least `step` in either transparency, or in the
-- swap: what is worth writing to the instances this frame.
function RimBlur.changed(shown: Layers, layers: Layers, step: number): boolean
	return shown.swapped ~= layers.swapped
		or math.abs(shown.face - layers.face) >= step
		or math.abs(shown.disc - layers.disc) >= step
		or (layers.face == 1 and shown.face ~= 1)
		or (layers.face == 0 and shown.face ~= 0)
end

return table.freeze(RimBlur)
