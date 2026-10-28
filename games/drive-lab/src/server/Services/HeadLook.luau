--!strict
--[[
	Relays where each player's head points. The owner's client sends its angles a few times a
	second; the server clamps them and stores them on the character, where attribute
	replication hands them to every other client, late joiners included.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HeadLook = require(ReplicatedStorage.Shared.Rules.HeadLook)
local Net = require(ReplicatedStorage.Kit.Net)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

-- Twice the client's send rate, so ordinary jitter in arrival never drops a legitimate update.
local LIMIT = { perSecond = 20, burst = 20 }

local Service = {}

function Service.start()
	Net.onServerEvent(Remotes.LOOK, LIMIT, HeadLook.parse, function(player: Player, angles: HeadLook.Angles)
		local character = player.Character
		if character == nil then
			return
		end
		character:SetAttribute("LookYaw", angles.yaw)
		character:SetAttribute("LookPitch", angles.pitch)
	end)
end

return Service
