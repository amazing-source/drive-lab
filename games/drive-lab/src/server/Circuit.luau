--!strict
--[[
	Lays the test circuit's ground for Services/Track: the grass field under the whole lap, the
	river's channel through it, and at each crossing a deck of the road's own terrain asphalt (so
	the tyres, the road audio and the wet look find the same road) with a concrete parapet along
	both edges. The road itself, its lines and its furniture are laid by Services/Track.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Bridges = require(ReplicatedStorage.Shared.Rules.Bridges)
local Config = require(ReplicatedStorage.Shared.Config.Circuit)
local Rules = require(ReplicatedStorage.Shared.Rules.Circuit)
local Track = require(ReplicatedStorage.Shared.Config.Track)
local Units = require(ReplicatedStorage.Shared.Units)

-- origin: the start line's centre at ground level, in studs.
export type Site = { origin: Vector3, course: Rules.Course }

local PARAPET_COLOR = Color3.fromRGB(168, 166, 160)

local function studs(metres: number): number
	return Units.metresToStuds(metres)
end

local function frameOf(site: Site): (Vector3, Vector3)
	local start = site.course.start
	local look = Vector3.new(start.dirX, 0, start.dirZ)
	return look, Vector3.new(-look.Z, 0, look.X)
end

-- A block in the start's frame: centred `along` and `across` metres from the start line, its top
-- and bottom metres above ground level.
local function block(
	site: Site,
	along: number,
	across: number,
	size: Vector2,
	top: number,
	bottom: number
): (CFrame, Vector3)
	local look, right = frameOf(site)
	local centre = site.origin
		+ look * studs(along)
		+ right * studs(across)
		+ Vector3.new(0, studs((top + bottom) / 2), 0)
	return CFrame.lookAt(centre, centre + look),
		Vector3.new(studs(size.X), studs(top - bottom), studs(size.Y))
end

-- Fills a strip `width` metres wide along the start direction across the field's length, between
-- top and bottom metres above ground, in tiles.
local function strip(
	site: Site,
	bounds: Rules.Bounds,
	across: number,
	width: number,
	top: number,
	bottom: number,
	material: Enum.Material
)
	for _, tile in Rules.tiles(bounds.alongMin, bounds.alongMax, Config.FIELD_TILE, Config.TILE_OVERLAP) do
		local length = tile.to - tile.from
		local cframe, size =
			block(site, tile.from + length / 2, across, Vector2.new(width, length), top, bottom)
		Workspace.Terrain:FillBlock(cframe, size, material)
	end
end

local Circuit = {}

-- The grass under the whole lap, a tile at a time.
function Circuit.layField(site: Site, bounds: Rules.Bounds)
	for _, tile in Rules.tiles(bounds.acrossMin, bounds.acrossMax, Config.FIELD_TILE, Config.TILE_OVERLAP) do
		local width = tile.to - tile.from
		strip(site, bounds, tile.from + width / 2, width, 0, -Track.GROUND_DEPTH, Enum.Material.Grass)
	end
end

-- The channel across the field: ground under the banks and the bed, the field cut away, then the
-- water.
function Circuit.layRiver(site: Site, bounds: Rules.Bounds)
	local river = Config.RIVER
	local bedTop = -math.max(river.bed, Track.GROUND_DEPTH)
	strip(
		site,
		bounds,
		river.offset,
		river.width + 2 * river.bank,
		-Track.GROUND_DEPTH,
		bedTop - river.bank,
		Enum.Material.Mud
	)
	task.wait()
	strip(site, bounds, river.offset, river.width, 1, -river.bed, Enum.Material.Air)
	task.wait()
	strip(site, bounds, river.offset, river.width, -river.surface, -river.bed, Enum.Material.Water)
end

-- Each bridge's deck, as terrain level with the road, and its two parapets, from the deck's
-- underside to parapetHeight above the road's surface (studs above ground level).
function Circuit.layBridges(site: Site, spans: { Bridges.Span }, surfaceLift: number, parent: Instance)
	local bridge = Config.BRIDGE
	for _, span in spans do
		local middle = Rules.pointAt(site.course, (span.from + span.to) / 2)
		local along = Vector3.new(middle.dirX, 0, middle.dirZ)
		local right = Vector3.new(-along.Z, 0, along.X)
		local centre = site.origin
			+ Vector3.new(studs(middle.x - site.course.start.x), 0, studs(middle.z - site.course.start.z))
		local length = span.to - span.from
		local width = Track.ROAD_WIDTH + 2 * bridge.kerb
		local deckCentre = centre - Vector3.new(0, studs(bridge.thickness) / 2, 0)
		Workspace.Terrain:FillBlock(
			CFrame.lookAt(deckCentre, deckCentre + along),
			Vector3.new(studs(width), studs(bridge.thickness), studs(length)),
			Enum.Material.Asphalt
		)
		local bottom = -studs(bridge.thickness)
		local top = surfaceLift + studs(bridge.parapetHeight)
		for _, parapet in Bridges.parapets(span, bridge, Track.ROAD_WIDTH) do
			local offset = parapet.side * studs(parapet.inner + bridge.parapetWidth / 2)
			local position = centre + right * offset + Vector3.new(0, (top + bottom) / 2, 0)
			local part = Instance.new("Part")
			part.Name = "Parapet"
			part.Anchored = true
			part.CanTouch = false
			part.Material = Enum.Material.Concrete
			part.Color = PARAPET_COLOR
			part.Size =
				Vector3.new(studs(bridge.parapetWidth), top - bottom, studs(parapet.to - parapet.from))
			part.CFrame = CFrame.lookAt(position, position + along)
			part.Parent = parent
		end
	end
end

return Circuit
