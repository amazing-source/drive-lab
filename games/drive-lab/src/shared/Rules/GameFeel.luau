--!strict
--[[
	The game-feel notch (Config/GameFeel): the one the key selects next, and the one a published
	value names, so a missing or stale attribute reads as the default rather than as nothing.
]]
local Config = require("../Config/GameFeel")

local GameFeel = {}

-- The notch `value` names if it is one, or the default.
function GameFeel.current(value: unknown): Config.Notch
	for index = 1, #Config.ORDER do
		if Config.ORDER[index] == value then
			return Config.ORDER[index]
		end
	end
	return Config.DEFAULT
end

-- The notch the key selects after `notch`, from the last back to the first.
function GameFeel.after(notch: Config.Notch): Config.Notch
	local index = table.find(Config.ORDER, notch) or 0
	return Config.ORDER[index % #Config.ORDER + 1]
end

-- The notch's HUD label while within `seconds` of a change at `changedAt`, or nil.
function GameFeel.flash(notch: Config.Notch, changedAt: number?, now: number, seconds: number): string?
	if changedAt == nil or now - changedAt >= seconds then
		return nil
	end
	return Config.LABELS[notch]
end

return table.freeze(GameFeel)
