local stdio = require("@lune/stdio")
local Roadside = require("./src/shared/Rules/Roadside")
local RoadsideConfig = require("./src/shared/Config/Roadside")
local StreetLamps = require("./src/shared/Rules/StreetLamps")
local Track = require("./src/shared/Config/Track")
local TrackPath = require("./src/shared/Rules/TrackPath")
local out = {}
local function f(v) table.insert(out, string.format("%.17g", v)) end
local start = { x = 0, z = 0, dirX = 0, dirZ = -1, s = 0 }
local steps = 0
for _, bends in { true, false } do
	local previous = start
	for _, p in TrackPath.generate(start, 6000, Track.STEP, Track.SEED, bends) do
		f(p.x) f(p.z) f(p.dirX) f(p.dirZ) f(p.s)
		if p.s - previous.s ~= Track.STEP then steps += 1 end
		previous = p
	end
end
for s = 0, 40000, 7 do f(TrackPath.curvature(s, Track.SEED)) end
for _, p in Roadside.guardrailPieces(0, 40000, Track.SEED, RoadsideConfig.GUARDRAILS) do f(p.s) f(p.side) table.insert(out, p.kind) f(p.variant) end
for _, p in Roadside.delineators(0, 40000, Track.SEED, RoadsideConfig.DELINEATORS, RoadsideConfig.GUARDRAILS, RoadsideConfig.DELINEATOR_CLEARANCE) do f(p.s) f(p.side) end
for _, s in Roadside.gantries(0, 40000, Track.SEED, RoadsideConfig.GANTRIES) do f(s) end
for _, m in Roadside.marks(0, 40000, Track.SEED, RoadsideConfig.MARKS) do f(m.s) f(m.offset) f(m.length) f(m.width) f(m.yaw) f(m.shade) end
for _, p in StreetLamps.spots(0, 40000, Track.SEED, Track.LAMPS) do f(p.s) f(p.side) end
stdio.write(table.concat(out, "\n") .. "\n")
stdio.ewrite(`values {#out}, steps not exactly STEP: {steps}\n`)
