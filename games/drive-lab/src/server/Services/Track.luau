--!strict
--[[
	Lays the endless test road as terrain, a chunk at a time. A chunk is laid while any player is
	within LOOKAHEAD of it and cleared once every player is beyond KEEP_BEHIND, so the road
	reaches ahead of the fastest driver and also comes back, identical, under anyone who turns
	round. Asphalt on the road and grass on the verges: the tyres feel the difference through
	Config/Surfaces. Lane lines are thin parts on top, and street lamps stand on both verges
	(Rules/StreetLamps), laid and cleared with their chunk; Controllers/StreetLights lights them.
	The rest of the furniture and the marks on the asphalt come from the server's Roadside.

	It starts under the car, so it runs before Cars rigs it; the baseplate is replaced by a
	concrete pad in the same terrain, since a part and terrain at one height flicker.
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Driving = require(ReplicatedStorage.Shared.Config.Driving)
local Log = require(ReplicatedStorage.Kit.Log)
local Roadside = require(script.Parent.Parent.Roadside)
local Track = require(ReplicatedStorage.Shared.Config.Track)
local StreetLamps = require(ReplicatedStorage.Shared.Rules.StreetLamps)
local TrackPath = require(ReplicatedStorage.Shared.Rules.TrackPath)
local Units = require(ReplicatedStorage.Shared.Units)

type Chunk = {
	-- The point before the chunk's first, so its first step has a start.
	from: TrackPath.Point,
	points: { TrackPath.Point },
	laid: boolean,
	lines: Folder?,
}

local log = Log.scope("Track")
local chunks: { Chunk } = {}
local origin = Vector3.zero
-- Terrain snaps a fill to its 4-stud grid, so its surface is not quite where the fill's top was
-- asked to be (2 studs higher on a baseplate at 0). Measured once on the pad; lines sit on it.
local surfaceLift = 0
local busy = false
local warnedLamp = false

local function studs(metres: number): number
	return Units.metresToStuds(metres)
end

local function toWorld(point: TrackPath.Point): Vector3
	return origin + Vector3.new(studs(point.x), 0, studs(point.z))
end

-- A block along the step from a to b, its top at ground level. Longer than the step by what
-- the bend opens at its outer edge, so consecutive blocks leave no gap.
local function stepBlock(
	a: TrackPath.Point,
	b: TrackPath.Point,
	width: number,
	depth: number
): (CFrame, Vector3)
	local turn = math.abs(math.atan2(a.dirX * b.dirZ - a.dirZ * b.dirX, a.dirX * b.dirX + a.dirZ * b.dirZ))
	local length = Track.STEP + width * turn + 1
	local mid = (toWorld(a) + toWorld(b)) / 2 - Vector3.new(0, studs(depth) / 2, 0)
	local direction = Vector3.new(b.x - a.x, 0, b.z - a.z).Unit
	return CFrame.lookAt(mid, mid + direction), Vector3.new(studs(width), studs(depth), studs(length))
end

local function line(parent: Folder, a: TrackPath.Point, b: TrackPath.Point, offset: number, length: number)
	local direction = Vector3.new(b.x - a.x, 0, b.z - a.z).Unit
	local right = Vector3.new(-direction.Z, 0, direction.X)
	local mid = (toWorld(a) + toWorld(b)) / 2 + right * studs(offset) + Vector3.new(0, surfaceLift + 0.05, 0)
	local part = Instance.new("Part")
	part.Name = "Line"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.fromRGB(235, 235, 230)
	part.Size = Vector3.new(studs(Track.LINE_WIDTH), 0.05, studs(length))
	part.CFrame = CFrame.lookAt(mid, mid + direction)
	part.Parent = parent
end

local function lampModel(): Model?
	local assets = ReplicatedStorage:FindFirstChild("DriveLabAssets")
	local lamp = assets and assets:FindFirstChild(Track.LAMP_ASSET)
	if lamp and lamp:IsA("Model") then
		return lamp
	end
	if not warnedLamp then
		warnedLamp = true
		log.warn(`ReplicatedStorage.DriveLabAssets.{Track.LAMP_ASSET} is missing; the road has no lamps`)
	end
	return nil
end

-- The road at arc length s (metres) in a chunk: its centreline on the surface, in studs, and the
-- unit direction along it. Past the chunk's last point the road runs straight on, so a piece
-- starting near the end can reach into the next chunk.
local function frameAt(chunk: Chunk, s: number): (Vector3, Vector3)
	local lift = Vector3.new(0, surfaceLift, 0)
	local previous = chunk.from
	for _, point in chunk.points do
		if point.s >= s then
			local share = math.clamp((s - previous.s) / math.max(point.s - previous.s, 1e-6), 0, 1)
			local along = Vector3.new(point.x - previous.x, 0, point.z - previous.z).Unit
			return toWorld(previous):Lerp(toWorld(point), share) + lift, along
		end
		previous = point
	end
	local along = Vector3.new(previous.dirX, 0, previous.dirZ).Unit
	return toWorld(previous) + along * studs(s - previous.s) + lift, along
end

-- The chunk's lamps, on the verges at the spots Rules/StreetLamps gives its stretch of road,
-- arms along the road. RoadSide tells the client's glints which way the road is.
local function placeLamps(chunk: Chunk, parent: Folder)
	local template = lampModel()
	if template == nil then
		return
	end
	local spots = StreetLamps.spots(chunk.from.s, chunk.points[#chunk.points].s, Track.SEED, Track.LAMPS)
	for _, spot in spots do
		local centre, along = frameAt(chunk, spot.s)
		local right = Vector3.new(-along.Z, 0, along.X)
		local position = centre + right * (spot.side * studs(Track.ROAD_WIDTH / 2 + Track.LAMP_SETBACK))
		local lamp = template:Clone()
		lamp:SetAttribute("RoadSide", spot.side)
		lamp:PivotTo(CFrame.fromMatrix(position, along, Vector3.yAxis))
		lamp.Parent = parent
	end
end

local function lay(chunk: Chunk)
	local terrain = Workspace.Terrain
	local lines = Instance.new("Folder")
	lines.Name = "TrackLines"
	local previous = chunk.from
	local verge = Track.ROAD_WIDTH + 2 * Track.VERGE_WIDTH
	for index, point in chunk.points do
		local cframe, size = stepBlock(previous, point, verge, Track.GROUND_DEPTH)
		terrain:FillBlock(cframe, size, Enum.Material.Grass)
		cframe, size = stepBlock(previous, point, Track.ROAD_WIDTH, Track.GROUND_DEPTH)
		terrain:FillBlock(cframe, size, Enum.Material.Asphalt)
		local edge = Track.ROAD_WIDTH / 2 - 0.4
		line(lines, previous, point, -edge, Track.STEP + 0.2)
		line(lines, previous, point, edge, Track.STEP + 0.2)
		if index % Track.DASH_EVERY == 0 then
			line(lines, previous, point, 0, Track.DASH_LENGTH)
		end
		previous = point
		if index % 10 == 0 then
			task.wait()
		end
	end
	placeLamps(chunk, lines)
	lines.Parent = Workspace
	Roadside.lay(function(s: number): (Vector3, Vector3)
		return frameAt(chunk, s)
	end, chunk.from.s, chunk.points[#chunk.points].s, Track.SEED, lines)
	chunk.lines = lines
	chunk.laid = true
end

local function clear(chunk: Chunk)
	local terrain = Workspace.Terrain
	local previous = chunk.from
	local verge = Track.ROAD_WIDTH + 2 * Track.VERGE_WIDTH
	for index, point in chunk.points do
		local cframe, size = stepBlock(previous, point, verge, Track.GROUND_DEPTH)
		terrain:FillBlock(cframe, size, Enum.Material.Air)
		previous = point
		if index % 10 == 0 then
			task.wait()
		end
	end
	if chunk.lines then
		chunk.lines:Destroy()
		chunk.lines = nil
	end
	chunk.laid = false
end

local function extend()
	local last = chunks[#chunks]
	local from = last.points[#last.points]
	table.insert(chunks, {
		from = from,
		points = TrackPath.generate(from, Track.CHUNK_STEPS, Track.STEP, Track.SEED),
		laid = false,
		lines = nil,
	})
end

-- Closest distance (studs) from any player to the chunk, sampled every few points.
local function nearest(chunk: Chunk, positions: { Vector3 }): number
	local best = math.huge
	for index = 1, #chunk.points, 8 do
		local at = toWorld(chunk.points[index])
		for _, position in positions do
			best = math.min(
				best,
				(Vector3.new(position.X, 0, position.Z) - Vector3.new(at.X, 0, at.Z)).Magnitude
			)
		end
	end
	return best
end

local function playerPositions(): { Vector3 }
	local positions = {}
	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			table.insert(positions, root.Position)
		end
	end
	return positions
end

local function update()
	if busy then
		return
	end
	busy = true
	local positions = playerPositions()
	if #positions > 0 then
		while nearest(chunks[#chunks], positions) < studs(Track.LOOKAHEAD) do
			extend()
		end
		for _, chunk in chunks do
			local distance = nearest(chunk, positions)
			if not chunk.laid and distance < studs(Track.LOOKAHEAD) then
				lay(chunk)
			elseif chunk.laid and distance > studs(Track.LOOKAHEAD + Track.KEEP_BEHIND) then
				clear(chunk)
			end
		end
	end
	busy = false
end

local function startFrame(): (Vector3, Vector3, number)
	local spawn = CollectionService:GetTagged(Driving.SPAWN_TAG)[1]
	local at = if spawn and spawn:IsA("Model") then spawn:GetPivot() else CFrame.new()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if spawn then { spawn } else {}
	local floor = Workspace:Raycast(at.Position + Vector3.new(0, 20, 0), Vector3.new(0, -200, 0), params)
	local ground = if floor then floor.Position.Y else 0
	local look = Vector3.new(at.LookVector.X, 0, at.LookVector.Z)
	local direction = if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, -1)
	return Vector3.new(at.Position.X, ground, at.Position.Z), direction, ground
end

local function layPad(centre: Vector3)
	local size = studs(Track.START_PAD)
	local depth = studs(Track.GROUND_DEPTH)
	Workspace.Terrain:FillBlock(
		CFrame.new(centre - Vector3.new(0, depth / 2, 0)),
		Vector3.new(size, depth, size),
		Enum.Material.Concrete
	)
end

local Service = {}

function Service.start()
	local carAt, direction, ground = startFrame()
	-- The road starts a little behind the car, so the car stands on it.
	local back = studs(30)
	origin = Vector3.new(carAt.X, ground, carAt.Z) - direction * back
	local spawnLocation = Workspace:FindFirstChildOfClass("SpawnLocation")
	local padCentre = if spawnLocation
		then (Vector3.new(spawnLocation.Position.X, ground, spawnLocation.Position.Z) + Vector3.new(
			carAt.X,
			ground,
			carAt.Z
		)) / 2
		else Vector3.new(carAt.X, ground, carAt.Z)
	layPad(padCentre)
	local start: TrackPath.Point = { x = 0, z = 0, dirX = direction.X, dirZ = direction.Z, s = 0 }
	table.insert(chunks, {
		from = start,
		points = TrackPath.generate(start, Track.CHUNK_STEPS, Track.STEP, Track.SEED),
		laid = false,
		lines = nil,
	})
	log.info(`road starts at {origin}, heading {direction}`)
	-- Laying yields between steps; the pad already holds the spawn and the car meanwhile.
	task.spawn(function()
		-- New terrain is not hit by raycasts until the next physics step.
		task.wait()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { Workspace.Terrain }
		local surface = Workspace:Raycast(padCentre + Vector3.new(0, 50, 0), Vector3.new(0, -100, 0), params)
		if surface then
			surfaceLift = surface.Position.Y - ground
		else
			log.warn("could not find the pad's surface; lane lines may sit off the road")
		end
		lay(chunks[1])
		local baseplate = Workspace:FindFirstChild("Baseplate")
		if baseplate then
			baseplate:Destroy()
		end
		while true do
			update()
			task.wait(Track.UPDATE_INTERVAL)
		end
	end)
end

return Service
