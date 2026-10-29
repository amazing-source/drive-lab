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
-- Where the car stood when the harness was installed: every fixture puts it back there, so a
-- scenario that moved it does not move the next one's start.
local home: CFrame? = nil

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

-- The car back where it stood, still: a fixture that unseats the body inside the car's collision
-- box shoves the car on this server (measured: 10.6 studs over 20 scenarios).
local function park(): boolean
	local model = car()
	local at = home
	if at == nil then
		return false
	end
	local here = model:GetPivot()
	if (here.Position - at.Position).Magnitude <= 0.02 and here.LookVector:Dot(at.LookVector) >= 0.99999 then
		return false
	end
	model:PivotTo(at)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and not part.Anchored then
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
	-- Put back, the car settles on its suspension (measured: a bounce of 0.7 studs): the next
	-- scenario starts once it is still.
	task.wait(1.5)
	return true
end

-- Lets the body go and puts it outside in the same step, as the game's own exit does, so it is
-- never free inside the car's collision box.
local function unseat(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local weld = seat():FindFirstChild("SeatWeld")
	if weld then
		weld:Destroy()
		if character and root then
			local spot = DoorMark.frame(seat()) * CFrame.new(0, 0, 4)
			character:PivotTo(
				(spot.Rotation + Vector3.new(spot.Position.X, spot.Position.Y + 1, spot.Position.Z))
					* root.CFrame:ToObjectSpace(character:GetPivot())
			)
		end
	end
	if humanoid then
		humanoid.Sit = false
	end
end

-- As the game scales the body (Services/CarEntry): about the root, which keeps its place. The
-- character's own pivot is its head, and scaling about it moves the root on the client.
local function scaleTo(character: Model, to: number)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root == nil or math.abs(character:GetScale() - to) <= 1e-3 then
		return
	end
	local primary = character.PrimaryPart
	character.PrimaryPart = root
	character:ScaleTo(to)
	character.PrimaryPart = primary
end

local HANDLERS: { [string]: (Player, any) -> any } = {
	outside = function(player: Player, door: string)
		rest(door)
		unseat(player)
		local character = player.Character
		if character then
			scaleTo(character, 1)
		end
		park()
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
		scaleTo(character, Driving.DRIVER_SCALE)
		park()
		-- The seat frees a moment after the last occupant leaves; Sit before that fails.
		for _ = 1, 30 do
			if seat().Occupant == humanoid then
				return true
			end
			if seat().Occupant == nil then
				pcall(function()
					seat():Sit(humanoid)
				end)
			end
			task.wait(0.1)
		end
		return seat().Occupant == humanoid
	end,
	park = function(_player: Player)
		return park()
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
		local pivot = model:GetPivot()
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
			carMoved = if home then (pivot.Position - home.Position).Magnitude else 0,
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
	home = car():GetPivot()
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
