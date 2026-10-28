--!strict
--[[
	Reads and writes a car's entry, door and engine state, the attributes Rules/CarEntry works
	from. Only the server writes them; every side reads them.
]]
local Config = require("../Config/CarEntry")
local Rules = require("../Rules/CarEntry")

local ATTRIBUTE = Config.ATTRIBUTES

local RESTS: { [string]: Config.DoorMotion } = { Closed = "Closed", Open = "Open" }
-- Only the clips that move the door can be its motion.
local DOOR_CLIPS: { [string]: Config.ClipName } = {
	OutsideOpen = "OutsideOpen",
	InsideClose = "InsideClose",
	InsideOpen = "InsideOpen",
	OutsideClose = "OutsideClose",
}

local CarState = {}

local function entryKind(value: unknown): Rules.EntryKind
	if value == "Enter" then
		return "Enter"
	elseif value == "Exit" then
		return "Exit"
	end
	return "None"
end

local function doorMotion(value: unknown): Config.DoorMotion
	if typeof(value) ~= "string" then
		return "Closed"
	end
	return RESTS[value] or DOOR_CLIPS[value] or "Closed"
end

local function engineState(value: unknown): Rules.EngineState
	if value == "On" then
		return "On"
	end
	return "Off"
end

local function number(model: Model, name: string): number
	local value = model:GetAttribute(name)
	return if typeof(value) == "number" and value == value then value else 0
end

function CarState.read(model: Model): Rules.State
	return {
		entry = entryKind(model:GetAttribute(ATTRIBUTE.ENTRY)),
		entryAt = number(model, ATTRIBUTE.ENTRY_AT),
		entryDoorOpen = model:GetAttribute(ATTRIBUTE.ENTRY_DOOR_OPEN) == true,
		door = doorMotion(model:GetAttribute(ATTRIBUTE.DOOR)),
		doorAt = number(model, ATTRIBUTE.DOOR_AT),
		engine = engineState(model:GetAttribute(ATTRIBUTE.ENGINE)),
		engineAt = number(model, ATTRIBUTE.ENGINE_AT),
	}
end

-- Server only.
function CarState.write(model: Model, state: Rules.State)
	model:SetAttribute(ATTRIBUTE.ENTRY, state.entry)
	model:SetAttribute(ATTRIBUTE.ENTRY_AT, state.entryAt)
	model:SetAttribute(ATTRIBUTE.ENTRY_DOOR_OPEN, state.entryDoorOpen)
	model:SetAttribute(ATTRIBUTE.DOOR, state.door)
	model:SetAttribute(ATTRIBUTE.DOOR_AT, state.doorAt)
	model:SetAttribute(ATTRIBUTE.ENGINE, state.engine)
	model:SetAttribute(ATTRIBUTE.ENGINE_AT, state.engineAt)
end

return table.freeze(CarState)
