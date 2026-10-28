--!strict
local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

local NumberFormat = {}

function NumberFormat.short(value: number): string
	if value ~= value then
		return "0"
	end
	local magnitude = math.abs(value)
	if magnitude < 1000 then
		return tostring(math.floor(value))
	end
	local tier = math.min(math.floor(math.log10(magnitude) / 3), #SUFFIXES - 1)
	local scaled = value / 1000 ^ tier
	if math.abs(scaled) >= 999.5 and tier < #SUFFIXES - 1 then
		tier += 1
		scaled /= 1000
	end
	local digits = if math.abs(scaled) < 10 then 2 elseif math.abs(scaled) < 100 then 1 else 0
	local text = string.format(`%.{digits}f`, scaled)
	if digits > 0 then
		text = (string.gsub(text, "0+$", ""))
		text = (string.gsub(text, "%.$", ""))
	end
	return text .. SUFFIXES[tier + 1]
end

function NumberFormat.cash(value: number): string
	return "$" .. NumberFormat.short(value)
end

function NumberFormat.clock(seconds: number): string
	local whole = math.max(math.floor(seconds), 0)
	local hours = whole // 3600
	local minutes = whole % 3600 // 60
	local secs = whole % 60
	if hours > 0 then
		return string.format("%d:%02d:%02d", hours, minutes, secs)
	end
	return string.format("%d:%02d", minutes, secs)
end

return NumberFormat
