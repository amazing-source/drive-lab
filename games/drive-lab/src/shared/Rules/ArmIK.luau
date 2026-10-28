--!strict
--[[
	Two-bone reach for an arm whose shoulder and wrist are both fixed: how far the wrist can be
	reached and how far the upper arm swings off the shoulder-to-wrist line to put the elbow
	where both bones meet. Plain numbers, any one length unit, angles in radians.
]]
local ArmIK = {}

export type Reach = {
	-- Angle at the shoulder between the shoulder-to-wrist line and the upper arm.
	bend: number,
	-- Shoulder-to-wrist distance actually reached: the asked distance, unless the arm cannot
	-- stretch that far or fold that close.
	reach: number,
}

function ArmIK.solve(upper: number, lower: number, distance: number): Reach
	local reach = math.clamp(distance, math.abs(upper - lower) + 1e-6, upper + lower - 1e-6)
	-- Law of cosines in the triangle shoulder, elbow, wrist.
	local cosine = (upper * upper + reach * reach - lower * lower) / (2 * upper * reach)
	return { bend = math.acos(math.clamp(cosine, -1, 1)), reach = reach }
end

return table.freeze(ArmIK)
