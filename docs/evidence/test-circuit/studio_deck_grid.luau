-- Edit-mode measurement of the laid circuit's bridge decks (run after the Track service laid it).
local RS = game:GetService("ReplicatedStorage")
local Bridges = require(RS.Shared.Rules.Bridges)
local Circuit = require(RS.Shared.Rules.Circuit)
local Config = require(RS.Shared.Config.Circuit)
local RoadsideConfig = require(RS.Shared.Config.Roadside)
local Track = require(RS.Shared.Config.Track)
local Units = require(RS.Shared.Units)
local function studs(m) return Units.metresToStuds(m) end

local car = workspace:FindFirstChild("CarImport")
local at = car:GetPivot()
local direction = Vector3.new(at.LookVector.X, 0, at.LookVector.Z).Unit
local right = Vector3.new(-direction.Z, 0, direction.X)
local origin = Vector3.new(at.X, 0, at.Z) - direction * studs(30) + right * studs(Config.OFFSET)
local course = Circuit.build(Config.SEGMENTS, { x = 0, z = 0, dirX = direction.X, dirZ = direction.Z, s = 0 })
local spans = Bridges.spans(course, Config.RIVER, Config.BRIDGE, Track.ROAD_WIDTH, RoadsideConfig.GUARDRAILS)

local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { workspace.Terrain }
terrainOnly.IgnoreWater = true
local withWater = RaycastParams.new()
withWater.FilterType = Enum.RaycastFilterType.Include
withWater.FilterDescendantsInstances = { workspace.Terrain }
withWater.IgnoreWater = false

local function worldAt(s, lateral)
	local p = Circuit.pointAt(course, s)
	local r = Vector3.new(-p.dirZ, 0, p.dirX)
	return origin + Vector3.new(studs(p.x), 0, studs(p.z)) + r * studs(lateral)
end

local function surface(s, lateral)
	local top = worldAt(s, lateral)
	local hit = workspace:Raycast(top + Vector3.new(0, 30, 0), Vector3.new(0, -80, 0), terrainOnly)
	return hit
end

local out = {}
local function say(text) table.insert(out, text) end
say(string.format("origin (%.2f, %.2f, %.2f), lap %.2f m, %d spans", origin.X, origin.Y, origin.Z, course.length, #spans))
local refs = {}
for _, s in { 100, 300, 640, 1200, 1700, 2600 } do
	local hit = surface(s, 0)
	table.insert(refs, if hit then string.format("s=%d y=%.3f %s", s, hit.Position.Y, hit.Material.Name) else string.format("s=%d HOLE", s))
end
say("road surface elsewhere (centre line): " .. table.concat(refs, "; "))
for index, span in spans do
	local holes, samples, materials = 0, 0, {}
	local yMin, yMax, deckMin, deckMax = math.huge, -math.huge, math.huge, -math.huge
	local worstStep, worstAt = 0, ""
	for lateral = -Track.ROAD_WIDTH / 2, Track.ROAD_WIDTH / 2 + 1e-9, 0.5 do
		local previous = nil
		for s = span.from - 12, span.to + 12, 0.5 do
			samples += 1
			local hit = surface(s, lateral)
			if hit == nil then
				holes += 1
				previous = nil
			else
				local y = hit.Position.Y
				materials[hit.Material.Name] = (materials[hit.Material.Name] or 0) + 1
				yMin, yMax = math.min(yMin, y), math.max(yMax, y)
				if s >= span.channelFrom and s <= span.channelTo then
					deckMin, deckMax = math.min(deckMin, y), math.max(deckMax, y)
				end
				if previous and math.abs(y - previous) > worstStep then
					worstStep = math.abs(y - previous)
					worstAt = string.format("s=%.1f lateral=%.1f", s, lateral)
				end
				previous = y
			end
		end
	end
	local mats = {}
	for name, count in materials do table.insert(mats, name .. "=" .. count) end
	say(string.format(
		"bridge %d (deck s %.1f-%.1f, channel %.1f-%.1f): %d rays over the road's width from 12 m before to 12 m after, %d holes, materials %s; surface y %.3f to %.3f studs (over the channel %.3f to %.3f); largest step between rays 0.5 m apart %.4f studs (%.1f mm) at %s",
		index, span.from, span.to, span.channelFrom, span.channelTo, samples, holes, table.concat(mats, " "), yMin, yMax, deckMin, deckMax, worstStep, Units.studsToMetres(worstStep) * 1000, worstAt))
	-- Under the deck: air, then the water's surface, then the bed.
	local below = worldAt(span.crossing, 0) + Vector3.new(0, -studs(Config.BRIDGE.thickness) - 1.5, 0)
	local water = workspace:Raycast(below, Vector3.new(0, -60, 0), withWater)
	local bed = workspace:Raycast(below, Vector3.new(0, -60, 0), terrainOnly)
	say(string.format("  under the deck at the crossing: first hit %s at y %.2f, bed %s at y %.2f",
		water and water.Material.Name or "none", water and water.Position.Y or 0,
		bed and bed.Material.Name or "none", bed and bed.Position.Y or 0))
	-- The river beside the bridge: water 30 m upstream.
	local upstream = worldAt(span.crossing, 0) + direction * studs(30) + Vector3.new(0, 20, 0)
	local river = workspace:Raycast(upstream, Vector3.new(0, -80, 0), withWater)
	say(string.format("  30 m along the river: %s at y %.2f", river and river.Material.Name or "none", river and river.Position.Y or 0))
end
local parapets = {}
local bridgesFolder = workspace:FindFirstChild("Bridges")
if bridgesFolder then
	for _, part in bridgesFolder:GetChildren() do
		table.insert(parapets, string.format("%s size (%.2f, %.2f, %.2f) top y %.2f collide %s", part.Name, part.Size.X, part.Size.Y, part.Size.Z, part.Position.Y + part.Size.Y / 2, tostring(part.CanCollide)))
	end
end
say("parapets: " .. #parapets .. "\n  " .. table.concat(parapets, "\n  "))
return table.concat(out, "\n")
