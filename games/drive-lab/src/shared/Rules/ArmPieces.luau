--!strict
--[[
	Which pieces of a seated driver's custom arms are drawn. In the cockpit view, as in a racing
	sim, the player sees only their own gloved hands on the wheel: the sleeves (upper arm, elbow,
	forearm) are hidden and the gloves' closed cuffs end the hands. Every other view, and every
	other driver seen from the cockpit, keeps the full arms.
]]
local ArmPieces = {}

-- `view` is the camera's DriveLabView attribute, read as it comes.
function ArmPieces.sleevesShown(view: unknown, ownDriver: boolean, cockpitGlovesOnly: boolean): boolean
	return not (cockpitGlovesOnly and ownDriver and view == "Cockpit")
end

return table.freeze(ArmPieces)
