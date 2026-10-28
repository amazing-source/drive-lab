--!strict
local RunService = game:GetService("RunService")

export type Level = "debug" | "info" | "warn" | "error"

export type Logger = {
	debug: (message: string) -> (),
	info: (message: string) -> (),
	warn: (message: string) -> (),
	error: (message: string) -> (),
}

local RANK: { [Level]: number } = { debug = 1, info = 2, warn = 3, error = 4 }

local threshold: Level = if RunService:IsStudio() then "debug" else "info"

local function emit(level: Level, tag: string, message: string)
	if RANK[level] < RANK[threshold] then
		return
	end
	local line = `[{tag}] {message}`
	if level == "warn" or level == "error" then
		warn(line)
	else
		print(line)
	end
end

local Log = {}

function Log.setThreshold(level: Level)
	threshold = level
end

function Log.scope(tag: string): Logger
	return {
		debug = function(message: string)
			emit("debug", tag, message)
		end,
		info = function(message: string)
			emit("info", tag, message)
		end,
		warn = function(message: string)
			emit("warn", tag, message)
		end,
		error = function(message: string)
			emit("error", tag, message)
		end,
	}
end

return Log
