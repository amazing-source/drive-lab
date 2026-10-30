--!strict
--[[
	How the seated driver's hands are dressed (Config/DriverArms.GLOVES): racing gloves and their
	gauntlet cuffs, or bare hands in the avatar's skin colour with the sleeves' cuffs. The hand
	meshes carry a near-white skin detail map that takes either colour as a tint, so the knuckles
	and creases shape the glove too. Parts come back unparented, for the caller to place.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DriverArms = require(ReplicatedStorage.Shared.Config.DriverArms)

local GLOVE = Color3.fromRGB(DriverArms.GLOVE_RGB[1], DriverArms.GLOVE_RGB[2], DriverArms.GLOVE_RGB[3])
local SLEEVE = Color3.fromRGB(DriverArms.SLEEVE_RGB[1], DriverArms.SLEEVE_RGB[2], DriverArms.SLEEVE_RGB[3])

local Gloves = {}

function Gloves.hand(template: BasePart, skin: Color3): BasePart
	local part = template:Clone()
	local color = if DriverArms.GLOVES then GLOVE else skin
	local surface = part:FindFirstChildOfClass("SurfaceAppearance")
	if surface then
		surface.Color = color
	else
		part.Color = color
	end
	return part
end

function Gloves.cuff(template: BasePart): BasePart
	local part = template:Clone()
	part.Color = if DriverArms.GLOVES then GLOVE else SLEEVE
	return part
end

return table.freeze(Gloves)
