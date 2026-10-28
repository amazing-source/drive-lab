--!strict
--[[
	Server half of the car entry Play matrix (#40): fixtures and a log, installed in a Play
	session only (a ModuleScript copied into the place before Play and deleted after; it is not
	part of the game). The client half drives the scenarios through _PacingRemote.

	Fixtures: "outside" puts the player outside the car at full size with the car at rest and its
	door shut or open; "seated" seats the player at the driver's size, the entry long finished;
	"kill" resets the character; "state" returns what this server sees; "log" the requests the
	CarAction remote received, with where this server saw the body at that moment.
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CarState = require(ReplicatedStorage.Shared.Car.CarState)
local DoorMark = require(ReplicatedStorage.Shared.Car.DoorMark)
local Driving = require(ReplicatedStorage.Shared.Config.Driving)

type Entry = { t: number, action: string, dist: number, scale: number }

local Server = {}
local entries: { Entry } = {}

local function car(): Model
	return CollectionService:GetTagged("DriveLabCar")[1] :: Model
end

local function seat(): Seat
	return car():FindFirstChild("DriverSeat", true) :: Seat
end

local function rest(door: string)
	CarState.write(car(), {
		entry = "None",
		entryAt = 0,
		entryDoorOpen = false,
		door = if door == "Open" then "Open" else "Closed",
		doorAt = 0,
		engine = "Off",
		engineAt = 0,
	})
end

local function unseat(player: Player)
	local weld = seat():FindFirstChild("SeatWeld")
	if weld then
		weld:Destroy()
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Sit = false
	end
end

local HANDLERS: { [string]: (Player, any) -> any } = {
	outside = function(player: Player, door: string)
		local wasSeated = seat().Occupant ~= nil
		rest(door)
		unseat(player)
		local character = player.Character
		if character and math.abs(character:GetScale() - 1) > 1e-3 then
			character:ScaleTo(1)
		end
		if wasSeated and character then
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
			local mark = DoorMark.frame(seat())
			local spot = mark * CFrame.new(0, 0, 4)
			character:PivotTo(
				(spot.Rotation + Vector3.new(spot.Position.X, root.Position.Y - 1, spot.Position.Z))
					* root.CFrame:ToObjectSpace(character:GetPivot())
			)
		end
		return true
	end,
	seated = function(player: Player, door: string)
		local character = player.Character :: Model
		local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
		local at = Workspace:GetServerTimeNow()
		CarState.write(car(), {
			entry = "Enter",
			entryAt = at - 100,
			entryDoorOpen = false,
			door = if door == "Open" then "Open" else "Closed",
			doorAt = at - 100,
			engine = "Off",
			engineAt = 0,
		})
		if math.abs(character:GetScale() - Driving.DRIVER_SCALE) > 1e-3 then
			character:ScaleTo(Driving.DRIVER_SCALE)
		end
		seat():Sit(humanoid)
		return true
	end,
	kill = function(player: Player)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Health = 0
		end
		return true
	end,
	state = function(player: Player)
		local model = car()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		return {
			entry = model:GetAttribute("Entry"),
			door = model:GetAttribute("Door"),
			engine = model:GetAttribute("Engine"),
			reservedBy = model:GetAttribute("ReservedBy"),
			occupied = seat().Occupant ~= nil,
			dist = if root and root:IsA("BasePart") then DoorMark.distance(seat(), root.Position) else -1,
			scale = if character then character:GetScale() else 0,
		}
	end,
	log = function(_player: Player, since: number)
		local out = {}
		for _, entry in entries do
			if entry.t >= since then
				table.insert(out, entry)
			end
		end
		return out
	end,
}

function Server.install(): string
	if ReplicatedStorage:FindFirstChild("_PacingRemote") then
		return "already installed"
	end
	local remote = Instance.new("RemoteFunction")
	remote.Name = "_PacingRemote"
	remote.OnServerInvoke = function(player: Player, command: unknown, argument: unknown)
		local handler = if typeof(command) == "string" then HANDLERS[command] else nil
		return if handler then handler(player, argument) else nil
	end
	remote.Parent = ReplicatedStorage
	local action = ReplicatedStorage:FindFirstChild("CarAction", true) :: RemoteEvent
	action.OnServerEvent:Connect(function(player: Player, payload: any)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		table.insert(entries, {
			t = Workspace:GetServerTimeNow(),
			action = if typeof(payload) == "table" then tostring(payload.action) else "?",
			dist = if root and root:IsA("BasePart") then DoorMark.distance(seat(), root.Position) else -1,
			scale = if character then character:GetScale() else 0,
		})
	end)
	return `installed for {car():GetFullName()}; players {#Players:GetPlayers()}`
end

return Server
