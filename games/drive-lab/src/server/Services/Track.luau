--!strict
--[[
	Lays the test road as terrain, a chunk at a time. On the endless layouts a chunk is laid while
	any player is within LOOKAHEAD of it and cleared once every player is beyond KEEP_BEHIND, so
	the road reaches ahead of the fastest driver and also comes back, identical, under anyone who
	turns round. The circuit is laid whole at start, on a grass field with its river and bridges
	(the server's Circuit), and stays. The Pad layout hands over to the server's Pad, which paves
	one asphalt square round the cars and nothing else. Asphalt on the road and grass beside it:
	the tyres feel the difference through Config/Surfaces. Lane lines are thin parts on top, and
	street lamps stand on both verges (Rules/StreetLamps), laid and cleared with their chunk;
	Controllers/StreetLights lights them. The rest of the furniture and the marks on the asphalt
	come from the server's Roadside.

	It starts under the car, so it runs before Cars rigs it; the baseplate is replaced by a
	concrete pad in the same terrain, since a part and terrain at one height flicker.
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Bridges = require(ReplicatedStorage.Shared.Rules.Bridges)
local Circuit = require(script.Parent.Parent.Circuit)
local CircuitConfig = require(ReplicatedStorage.Shared.Config.Circuit)
local CircuitPath = require(ReplicatedStorage.Shared.Rules.Circuit)
local Driving = require(ReplicatedStorage.Shared.Config.Driving)
local Log = require(ReplicatedStorage.Kit.Log)
local Pad = require(script.Parent.Parent.Pad)
local RoadsideConfig = require(ReplicatedStorage.Shared.Config.Roadside)
local Roadside = require(script.Parent.Parent.Roadside)
local RoadsideRules = require(ReplicatedStorage.Shared.Rules.Roadside)
local Scatter = require(ReplicatedStorage.Shared.Rules.Scatter)
local StreetLamps = require(ReplicatedStorage.Shared.Rules.StreetLamps)
local Track = require(ReplicatedStorage.Shared.Config.Track)
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
local isCircuit = Track.LAYOUT == "Circuit"
-- The circuit's bridges, where verge furniture keeps off, and the guardrails leading onto them;
-- empty on the endless layouts.
local spans: { Bridges.Span } = {}
local keepOut: { Scatter.Zone } = {}
local approaches: { RoadsideRules.Piece } = {}

local function studs(metres: number): number
	return Units.metresToStuds(metres)
end

local function toWorld(point: TrackPath.Point): Vector3
	return origin + Vector3.new(studs(point.x), 0, studs(point.z))
end

-- A block along the step from a to b, its top at ground level, as long as TrackPath.blockLength.
local function stepBlock(
	a: TrackPath.Point,
	b: TrackPath.Point,
	width: number,
	depth: number
): (CFrame, Vector3)
	local length = TrackPath.blockLength(b.s - a.s, width, TrackPath.turn(a, b))
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
	local spots =
		StreetLamps.spots(chunk.from.s, chunk.points[#chunk.points].s, Track.SEED, Track.LAMPS, keepOut)
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
		-- The circuit's field is its verges.
		if not isCircuit then
			local cframe, size = stepBlock(previous, point, verge, Track.GROUND_DEPTH)
			terrain:FillBlock(cframe, size, Enum.Material.Grass)
		end
		-- Over a river the bridge's deck is the road.
		if Bridges.fullDepth(spans, previous, point, Track.ROAD_WIDTH, CircuitConfig.BRIDGE) then
			local cframe, size = stepBlock(previous, point, Track.ROAD_WIDTH, Track.GROUND_DEPTH)
			terrain:FillBlock(cframe, size, Enum.Material.Asphalt)
		end
		local edge = Track.ROAD_WIDTH / 2 - 0.4
		local length = point.s - previous.s
		line(lines, previous, point, -edge, length + 0.2)
		line(lines, previous, point, edge, length + 0.2)
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
	end, chunk.from.s, chunk.points[#chunk.points].s, Track.SEED, lines, keepOut, approaches)
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
	local spawns = CollectionService:GetTagged(Driving.SPAWN_TAG)
	local names = table.create(#spawns)
	for index, candidate in spawns do
		names[index] = candidate:GetFullName()
	end
	local index = TrackPath.startIndex(names)
	local spawn = if index then spawns[index] else nil
	local at = if spawn and spawn:IsA("Model") then spawn:GetPivot() else CFrame.new()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = spawns
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

-- New terrain is not hit by raycasts until the next physics step: call a frame after laying the pad.
local function measureLift(padCentre: Vector3, ground: number)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { Workspace.Terrain }
	local surface = Workspace:Raycast(padCentre + Vector3.new(0, 50, 0), Vector3.new(0, -100, 0), params)
	if surface then
		surfaceLift = surface.Position.Y - ground
	else
		log.warn("could not find the pad's surface; lane lines may sit off the road")
	end
end

local function removeBaseplate()
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end
end

local function circuitChunks(course: CircuitPath.Course): { Chunk }
	local length = Track.STEP * Track.CHUNK_STEPS
	local found = {}
	local from = 0
	while from < course.length do
		local to = if course.length - (from + length) < Track.STEP then course.length else from + length
		table.insert(found, {
			from = CircuitPath.pointAt(course, from),
			points = CircuitPath.points(course, from, to, Track.STEP),
			laid = false,
			lines = nil,
		})
		from = to
	end
	return found
end

-- Lays the whole circuit: the field and the pad now, so the cars have ground; the river, the
-- bridges and the road over the next frames. Nothing is cleared afterwards.
local function startCircuit(start: TrackPath.Point, padCentre: Vector3, ground: number)
	local began = Workspace:GetServerTimeNow()
	local course = CircuitPath.build(CircuitConfig.SEGMENTS, start)
	local problems
	spans, problems = Bridges.spans(
		course,
		CircuitConfig.RIVER,
		CircuitConfig.BRIDGE,
		Track.ROAD_WIDTH,
		RoadsideConfig.GUARDRAILS
	)
	for _, problem in problems do
		log.warn(`{problem}: the road crosses on full ground there`)
	end
	keepOut = Bridges.keepOut(spans, CircuitConfig.BRIDGE, RoadsideConfig.GUARDRAILS)
	approaches =
		Bridges.guardrailPieces(spans, 0, course.length, CircuitConfig.BRIDGE, RoadsideConfig.GUARDRAILS)
	chunks = circuitChunks(course)
	local site: Circuit.Site = { origin = origin, course = course }
	local bounds = CircuitPath.bounds(course, CircuitConfig.FIELD_MARGIN, Track.STEP)
	Circuit.layField(site, bounds)
	layPad(padCentre)
	log.info(
		`circuit {math.round(course.length)} m in {#chunks} chunks, {#spans} bridges, start line at {origin}; field and pad in {string.format(
			"%.2f",
			Workspace:GetServerTimeNow() - began
		)} s`
	)
	task.spawn(function()
		task.wait()
		measureLift(padCentre, ground)
		Circuit.layRiver(site, bounds)
		local bridges = Instance.new("Folder")
		bridges.Name = "Bridges"
		Circuit.layBridges(site, spans, surfaceLift, bridges)
		bridges.Parent = Workspace
		for _, chunk in chunks do
			lay(chunk)
		end
		removeBaseplate()
		log.info(`circuit laid {string.format("%.2f", Workspace:GetServerTimeNow() - began)} s after start`)
	end)
end

local Service = {}

function Service.start()
	local carAt, direction, ground = startFrame()
	if Track.LAYOUT == "Pad" then
		Pad.start(Vector3.new(carAt.X, ground, carAt.Z), direction)
		return
	end
	-- The road starts a little behind the car, so the car stands on it; the circuit's start line
	-- runs to the right of the parked cars instead.
	local back = studs(30)
	origin = Vector3.new(carAt.X, ground, carAt.Z) - direction * back
	if isCircuit then
		origin += Vector3.new(-direction.Z, 0, direction.X) * studs(CircuitConfig.OFFSET)
	end
	local spawnLocation = Workspace:FindFirstChildOfClass("SpawnLocation")
	local padCentre = if spawnLocation
		then (Vector3.new(spawnLocation.Position.X, ground, spawnLocation.Position.Z) + Vector3.new(
			carAt.X,
			ground,
			carAt.Z
		)) / 2
		else Vector3.new(carAt.X, ground, carAt.Z)
	local start: TrackPath.Point = { x = 0, z = 0, dirX = direction.X, dirZ = direction.Z, s = 0 }
	if isCircuit then
		startCircuit(start, padCentre, ground)
		return
	end
	layPad(padCentre)
	table.insert(chunks, {
		from = start,
		points = TrackPath.generate(start, Track.CHUNK_STEPS, Track.STEP, Track.SEED),
		laid = false,
		lines = nil,
	})
	log.info(`road starts at {origin}, heading {direction}`)
	-- Laying yields between steps; the pad already holds the spawn and the car meanwhile.
	task.spawn(function()
		task.wait()
		measureLift(padCentre, ground)
		lay(chunks[1])
		-- Behind the start there is only the pad, then nothing; this stays when chunks are cleared.
		local roadEnd = Instance.new("Folder")
		roadEnd.Name = "RoadEnd"
		local centre, along = frameAt(chunks[1], 0)
		Roadside.layRoadEnd(centre, along, Track.ROAD_WIDTH + 2 * Track.VERGE_WIDTH, roadEnd)
		roadEnd.Parent = Workspace
		removeBaseplate()
		while true do
			update()
			task.wait(Track.UPDATE_INTERVAL)
		end
	end)
end

return Service
