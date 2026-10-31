local stdio = require("@lune/stdio")
local Bridges = require("./src/shared/Rules/Bridges")
local Circuit = require("./src/shared/Rules/Circuit")
local CircuitConfig = require("./src/shared/Config/Circuit")
local Roadside = require("./src/shared/Rules/Roadside")
local RoadsideConfig = require("./src/shared/Config/Roadside")
local StreetLamps = require("./src/shared/Rules/StreetLamps")
local Track = require("./src/shared/Config/Track")
local TrackPath = require("./src/shared/Rules/TrackPath")
local out = {}
local function f(v) table.insert(out, string.format("%.17g", v)) end
local start = { x = 0, z = 0, dirX = 0, dirZ = -1, s = 0 }
for _, bends in { true, false } do
	for _, p in TrackPath.generate(start, 6000, Track.STEP, Track.SEED, bends) do f(p.x) f(p.z) f(p.dirX) f(p.dirZ) f(p.s) end
end
for s = 0, 40000, 7 do f(TrackPath.curvature(s, Track.SEED)) end
for _, p in Roadside.guardrailPieces(0, 40000, Track.SEED, RoadsideConfig.GUARDRAILS) do f(p.s) f(p.side) table.insert(out, p.kind) f(p.variant) end
for _, p in Roadside.delineators(0, 40000, Track.SEED, RoadsideConfig.DELINEATORS, RoadsideConfig.GUARDRAILS, RoadsideConfig.DELINEATOR_CLEARANCE) do f(p.s) f(p.side) end
for _, s in Roadside.gantries(0, 40000, Track.SEED, RoadsideConfig.GANTRIES) do f(s) end
for _, m in Roadside.marks(0, 40000, Track.SEED, RoadsideConfig.MARKS) do f(m.s) f(m.offset) f(m.length) f(m.width) f(m.yaw) f(m.shade) end
for _, p in StreetLamps.spots(0, 40000, Track.SEED, Track.LAMPS) do f(p.s) f(p.side) end
local lap = Circuit.build(CircuitConfig.SEGMENTS, start)
for _, p in Circuit.points(lap, 0, lap.length, 1) do f(p.x) f(p.z) f(p.dirX) f(p.dirZ) f(p.s) end
local spans = Bridges.spans(lap, CircuitConfig.RIVER, CircuitConfig.BRIDGE, Track.ROAD_WIDTH, RoadsideConfig.GUARDRAILS)
for _, s in spans do f(s.from) f(s.to) f(s.channelFrom) f(s.channelTo) end
for _, z in Bridges.keepOut(spans, CircuitConfig.BRIDGE, RoadsideConfig.GUARDRAILS) do f(z.from) f(z.to) end
for _, p in Bridges.guardrailPieces(spans, 0, lap.length, CircuitConfig.BRIDGE, RoadsideConfig.GUARDRAILS) do f(p.s) f(p.side) table.insert(out, p.kind) end
local b = Circuit.bounds(lap, CircuitConfig.FIELD_MARGIN, Track.STEP)
for _, t in Circuit.tiles(b.alongMin, b.alongMax, CircuitConfig.FIELD_TILE, CircuitConfig.TILE_OVERLAP) do f(t.from) f(t.to) end
for _, t in Circuit.tiles(b.acrossMin, b.acrossMax, CircuitConfig.FIELD_TILE, CircuitConfig.TILE_OVERLAP) do f(t.from) f(t.to) end
stdio.write(table.concat(out, "\n") .. "\n")
stdio.ewrite(`values {#out}\n`)
