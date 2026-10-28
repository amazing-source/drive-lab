--!strict
--[[
	The street lamps' glints, as a camera sees them at night: a faint horizontal lens flare on
	each lit head, and on a wet road a streak of reflected light running from the lamp towards
	the viewer.

	The streak follows the mirror geometry. Seen from an eye at height e, a lamp at height h is
	mirrored in the road at the point a share e / (e + h) of the way from the eye's foot to the
	lamp's, on the line between the two; a wet road is not a mirror, so the light smears along
	that line, the long streak of every wet night photograph. It is drawn from just short of the
	mirror point to where the line leaves the asphalt: lamps stand on the verge and grass does
	not shine. Plan positions and heights are metres; the result is too.
]]
local LampGlints = {}

export type Point = { x: number, z: number }

export type Tuning = {
	-- Flare: full opacity up to fadeFrom metres, none past reach; more of it in rain (share
	-- added at full intensity); its length and height in metres, growing with distance so it
	-- keeps about the same size on screen, as a lens's flare does.
	flareOpacity: number,
	flareFadeFrom: number,
	flareReach: number,
	flareRain: number,
	flareLength: number,
	flareLengthPerMetre: number,
	flareHeight: number,
	flareHeightPerMetre: number,
	-- Reflection: as the flare's, scaled by how wet the road is above dryBelow.
	reflectionOpacity: number,
	reflectionFadeFrom: number,
	reflectionReach: number,
	dryBelow: number,
	-- The near end as a share of the way to the mirror point, and never nearer than nearest
	-- metres; the far end kept edgeMargin metres inside the road; shorter than shortest, none.
	nearShare: number,
	nearest: number,
	edgeMargin: number,
	shortest: number,
	-- The streak's width as the eye sees it (radians): each end is as wide as that angle at its
	-- own distance, so the streak stays a narrow line down the screen instead of a blob near
	-- the eye.
	streakAngle: number,
}

export type Flare = { opacity: number, length: number, height: number }

-- Widths in metres at each end.
export type Streak = { near: Point, far: Point, opacity: number, nearWidth: number, farWidth: number }

local function fade(distance: number, from: number, reach: number): number
	if distance <= from then
		return 1
	end
	local t = math.clamp((distance - from) / (reach - from), 0, 1)
	return 1 - t * t * (3 - 2 * t)
end

local function finite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

-- The flare on a lit lamp `distance` metres from the eye, in rain of intensity 0 to 1.
function LampGlints.flare(distance: number, rain: number, tuning: Tuning): Flare
	if not finite(distance) or distance < 0 then
		return { opacity = 0, length = 0, height = 0 }
	end
	local wet = if finite(rain) then math.clamp(rain, 0, 1) else 0
	local opacity = math.min(tuning.flareOpacity * (1 + tuning.flareRain * wet), 1)
		* fade(distance, tuning.flareFadeFrom, tuning.flareReach)
	return {
		opacity = opacity,
		length = tuning.flareLength + tuning.flareLengthPerMetre * distance,
		height = tuning.flareHeight + tuning.flareHeightPerMetre * distance,
	}
end

--[[
	The reflected streak of a lamp, or nil when there is none: a dry road, a lamp too far, an
	eye off the asphalt, a streak too short to show. edge is a point on the road's edge on the
	lamp's side and inward the unit normal from it into the road; eyeHeight and lampHeight are
	above the road's surface.
]]
function LampGlints.reflection(
	eye: Point,
	eyeHeight: number,
	lamp: Point,
	lampHeight: number,
	edge: Point,
	inward: Point,
	wetness: number,
	tuning: Tuning
): Streak?
	local wet = if finite(wetness)
		then math.clamp((wetness - tuning.dryBelow) / (1 - tuning.dryBelow), 0, 1)
		else 0
	if wet <= 0 or not finite(eyeHeight) or eyeHeight <= 0 or lampHeight <= 0 then
		return nil
	end
	local dx, dz = lamp.x - eye.x, lamp.z - eye.z
	local distance = math.sqrt(dx * dx + dz * dz)
	local opacity = tuning.reflectionOpacity
		* wet
		* fade(distance, tuning.reflectionFadeFrom, tuning.reflectionReach)
	if not finite(distance) or distance < 1e-3 or opacity <= 0 then
		return nil
	end
	-- Inward distances from the edge: the eye's must be on the asphalt, the lamp's off it.
	local eyeIn = (eye.x - edge.x) * inward.x + (eye.z - edge.z) * inward.z
	local lampIn = (lamp.x - edge.x) * inward.x + (lamp.z - edge.z) * inward.z
	if eyeIn <= tuning.edgeMargin then
		return nil
	end
	local farShare = if lampIn < eyeIn then math.min((eyeIn - tuning.edgeMargin) / (eyeIn - lampIn), 1) else 1
	local mirror = eyeHeight / (eyeHeight + lampHeight)
	local nearShare = math.max(mirror * tuning.nearShare, tuning.nearest / distance)
	if (farShare - nearShare) * distance < tuning.shortest then
		return nil
	end
	return {
		near = { x = eye.x + dx * nearShare, z = eye.z + dz * nearShare },
		far = { x = eye.x + dx * farShare, z = eye.z + dz * farShare },
		opacity = opacity,
		nearWidth = tuning.streakAngle * math.sqrt((nearShare * distance) ^ 2 + eyeHeight ^ 2),
		farWidth = tuning.streakAngle * math.sqrt((farShare * distance) ^ 2 + eyeHeight ^ 2),
	}
end

return table.freeze(LampGlints)
