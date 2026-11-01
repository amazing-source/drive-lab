--!strict
--[[
	What an analog cluster's message centre shows (Config/Gauges Message): the key's message after a
	start with that key until the car first moves off (the real car waits for its RESET button,
	which Drive Lab does not have), else the trip and the odometer in miles.
]]
local EngineGauges = require("./EngineGauges")
local Gauges = require("../Config/Gauges")

local MessageCentre = {}

-- Whether the car has moved off this drive: once it passes the message's speed, for good.
function MessageCentre.movedOff(message: Gauges.Message, already: boolean, speedKmh: number): boolean
	return already or speedKmh > message.moveOffKmh
end

-- The two lines, for a start with `key` (Rules/CarEntry.parseKey), distances in km.
function MessageCentre.lines(
	message: Gauges.Message,
	key: string,
	movedOff: boolean,
	trip: number,
	odometer: number
): { string }
	if key == message.key and not movedOff then
		return message.keyLines
	end
	return {
		string.format("%s %.1f", message.tripLabel, EngineGauges.miles(trip)),
		string.format("%.1f mi", EngineGauges.miles(odometer)),
	}
end

return table.freeze(MessageCentre)
