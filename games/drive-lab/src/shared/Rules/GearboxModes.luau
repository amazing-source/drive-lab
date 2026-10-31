--!strict
--[[
	The gearbox modes the T key steps through (Controllers/Driving): automatic and manual on every
	car, and the clutch mode on a car whose H box offers the player's clutch, while driving on the
	keyboard: a pad has no free control for a clutch. And the grinds the car's audio counts: a shift
	refused because the player's clutch was up (Vehicle/HBox).
]]
local Gearbox = require("../Vehicle/Gearbox")
local HBox = require("../Vehicle/HBox")
local Types = require("../Config/Cars/Types")

local GearboxModes = {}

-- Whether the car offers the clutch mode to this driver.
function GearboxModes.offersClutch(gearbox: Types.GearboxConfig, keyboard: boolean): boolean
	local manual = gearbox.manual
	return keyboard and gearbox.kind == "manual" and manual ~= nil and manual.playerClutch
end

-- The mode a press of T leaves the gearbox in.
function GearboxModes.after(
	gearbox: Types.GearboxConfig,
	current: Gearbox.GearboxMode,
	keyboard: boolean
): Gearbox.GearboxMode
	if current == "auto" then
		return "manual"
	elseif current == "manual" and GearboxModes.offersClutch(gearbox, keyboard) then
		return "manualClutch"
	end
	return "auto"
end

-- `current` on this car and device: the clutch mode carried into a car or onto a device that does
-- not offer it becomes manual.
function GearboxModes.valid(
	gearbox: Types.GearboxConfig,
	current: Gearbox.GearboxMode,
	keyboard: boolean
): Gearbox.GearboxMode
	if current == "manualClutch" and not GearboxModes.offersClutch(gearbox, keyboard) then
		return "manual"
	end
	return current
end

-- The grinds counted so far, after a frame whose refused shift, if any, was `refusal`.
function GearboxModes.grinds(count: number, refusal: HBox.Refusal?): number
	return if refusal == "clutchUp" then count + 1 else count
end

return table.freeze(GearboxModes)
