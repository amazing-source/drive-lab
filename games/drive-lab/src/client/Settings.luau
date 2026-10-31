--!strict
--[[
	This client's settings for the session (Config/Settings, Rules/Settings): every setting starts
	at its default when the player joins, and nothing is saved.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.Settings)
local Rules = require(ReplicatedStorage.Shared.Rules.Settings)

local store = Rules.new(Config.LIST)

local Settings = {}

Settings.LIST = Config.LIST
Settings.TITLE = Config.TITLE

function Settings.get(id: string): string?
	return Rules.get(store, id)
end

function Settings.set(id: string, value: string): boolean
	return Rules.set(store, id, value)
end

function Settings.listen(listener: Rules.Listener): () -> ()
	return Rules.listen(store, listener)
end

return Settings
