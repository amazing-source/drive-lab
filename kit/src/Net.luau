--!strict
--[[
	One declaration per remote. The server side requires a parser for every inbound
	remote: it turns the untrusted payload into a typed value or rejects it, and a token
	bucket per player caps how often it can be fired. Clients only ever send intents.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"

export type Parser<T> = (payload: unknown) -> T?

export type Limit = { perSecond: number, burst: number }

type Bucket = { tokens: number, updated: number }

local function folder(): Folder
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if existing then
			return existing :: Folder
		end
		local created = Instance.new("Folder")
		created.Name = FOLDER_NAME
		created.Parent = ReplicatedStorage
		return created
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

local function remote(
	name: string,
	className: "RemoteEvent" | "UnreliableRemoteEvent" | "RemoteFunction"
): Instance
	local container = folder()
	if RunService:IsServer() then
		local existing = container:FindFirstChild(name)
		if existing then
			return existing
		end
		local created = Instance.new(className)
		created.Name = name
		created.Parent = container
		return created
	end
	return container:WaitForChild(name)
end

local buckets: { [Player]: { [string]: Bucket } } = {}

local function admit(player: Player, name: string, limit: Limit): boolean
	local perPlayer = buckets[player]
	if perPlayer == nil then
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local now = os.clock()
	local bucket = perPlayer[name]
	if bucket == nil then
		bucket = { tokens = limit.burst, updated = now }
		perPlayer[name] = bucket
	end
	bucket.tokens = math.min(limit.burst, bucket.tokens + (now - bucket.updated) * limit.perSecond)
	bucket.updated = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

if RunService:IsServer() then
	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)
end

local Net = {}

-- The same per-player token bucket the remotes use, for other ways a client can ask the
-- server to act (ProximityPrompts, tool equips): whether `player` may act under `name` now.
function Net.allow(player: Player, name: string, limit: Limit): boolean
	return admit(player, name, limit)
end

function Net.onServerEvent<T>(name: string, limit: Limit, parse: Parser<T>, handler: (Player, T) -> ())
	local event = remote(name, "RemoteEvent") :: RemoteEvent
	event.OnServerEvent:Connect(function(player: Player, payload: unknown)
		if not admit(player, name, limit) then
			return
		end
		local value = parse(payload)
		if value == nil then
			return
		end
		handler(player, value)
	end)
end

function Net.onServerInvoke<T, R>(name: string, limit: Limit, parse: Parser<T>, handler: (Player, T) -> R): ()
	local func = remote(name, "RemoteFunction") :: RemoteFunction
	func.OnServerInvoke = function(player: Player, payload: unknown): R?
		if not admit(player, name, limit) then
			return nil
		end
		local value = parse(payload)
		if value == nil then
			return nil
		end
		return handler(player, value)
	end
end

function Net.declare(name: string, unreliable: boolean?)
	remote(name, if unreliable then "UnreliableRemoteEvent" else "RemoteEvent")
end

function Net.fireClient(name: string, player: Player, payload: unknown)
	(remote(name, "RemoteEvent") :: RemoteEvent):FireClient(player, payload)
end

function Net.fireAllClients(name: string, payload: unknown)
	(remote(name, "RemoteEvent") :: RemoteEvent):FireAllClients(payload)
end

function Net.fireUnreliable(name: string, player: Player, payload: unknown)
	(remote(name, "UnreliableRemoteEvent") :: UnreliableRemoteEvent):FireClient(player, payload)
end

function Net.send(name: string, payload: unknown)
	(remote(name, "RemoteEvent") :: RemoteEvent):FireServer(payload)
end

function Net.request(name: string, payload: unknown): unknown
	return (remote(name, "RemoteFunction") :: RemoteFunction):InvokeServer(payload)
end

function Net.onClientEvent<T>(name: string, handler: (payload: T) -> ()): RBXScriptConnection
	local instance = remote(name, "RemoteEvent")
	if instance:IsA("UnreliableRemoteEvent") then
		return instance.OnClientEvent:Connect(handler)
	end
	return (instance :: RemoteEvent).OnClientEvent:Connect(handler)
end

Net.parse = {
	none = function(_payload: unknown): boolean?
		return true
	end,
	boolean = function(payload: unknown): boolean?
		return if typeof(payload) == "boolean" then payload else nil
	end,
	index = function(maximum: number): Parser<number>
		return function(payload: unknown): number?
			if typeof(payload) ~= "number" or payload ~= payload then
				return nil
			end
			if payload % 1 ~= 0 or payload < 1 or payload > maximum then
				return nil
			end
			return payload
		end
	end,
	oneOf = function(options: { [string]: unknown }): Parser<string>
		return function(payload: unknown): string?
			if typeof(payload) == "string" and options[payload] ~= nil then
				return payload
			end
			return nil
		end
	end,
}

return Net
