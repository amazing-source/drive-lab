--!strict
--[[
	How bright a roadside reflector looks from the driven car. A reflector sends the light that
	reaches it back towards its source, so at night it lights up only in the car's own beams,
	only on the face turned to the car, and stays visible far beyond what the headlights light
	on the road: Roblox has no retroreflection, and a spotlight reaches 60 studs (11 m), so the
	glow is drawn instead. Distances are metres.
]]
local Reflectors = {}

export type Tuning = {
	-- Full glow up to fullTo metres, none past reach.
	fullTo: number,
	reach: number,
	-- Cosine of the angle off the car's heading: full inside cone, none outside coneEdge.
	cone: number,
	coneEdge: number,
	-- Cosine between the face's normal and the way to the car: none below edgeOn, full above
	-- faceOn (a reflector seen edge-on returns nothing).
	edgeOn: number,
	faceOn: number,
	-- Glow is shown in this many steps, so a reflector is only touched when its step changes.
	levels: number,
}

export type Sight = {
	headlights: boolean,
	distance: number,
	-- Cosine of the angle between the car's heading and the way to the reflector.
	ahead: number,
	-- Cosine between the reflector face's normal and the way back to the car.
	facing: number,
}

local function ramp(value: number, from: number, to: number): number
	return math.clamp((value - from) / (to - from), 0, 1)
end

-- Glow in [0, 1].
function Reflectors.glow(sight: Sight, tuning: Tuning): number
	if not sight.headlights or sight.distance ~= sight.distance then
		return 0
	end
	local range = 1 - ramp(sight.distance, tuning.fullTo, tuning.reach)
	local beam = ramp(sight.ahead, tuning.coneEdge, tuning.cone)
	local face = ramp(sight.facing, tuning.edgeOn, tuning.faceOn)
	return range * beam * face
end

-- The glow rounded up to one of `levels` steps (0 stays 0), so a fading reflector changes a
-- handful of times rather than every update.
function Reflectors.level(glow: number, levels: number): number
	if glow ~= glow or glow <= 0 then
		return 0
	end
	return math.ceil(math.min(glow, 1) * levels) / levels
end

return table.freeze(Reflectors)
