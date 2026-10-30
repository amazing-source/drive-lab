--!strict
--[[
	Writes the DR458's model binding from its 3D manifest, which stays in drive-lab-assets:
	Config/Cars/DR458/Model.luau, Config/Cars/DR458/ModelPending.luau, and the redacted copy the
	specs read (tests/fixtures/dr458_manifest.json: names, groups, motions and geometry, without
	sources or file paths). Run it from the repo root whenever the manifest changes:

	    lune run games/drive-lab/tools/dr458_binding --write [path to dr458_manifest.json]

	Without --write it only reports whether the committed binding matches the manifest; without a
	manifest (in CI) it reports that and stops.
]]
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local DR458 = require("../src/shared/Config/Cars/DR458/Physics")
local ManifestBinding = require("./ManifestBinding")
local Settings = require("./DR458Binding")

local TOOL = "games/drive-lab/tools/dr458_binding.luau"
local MODEL = "games/drive-lab/src/shared/Config/Cars/DR458/Model.luau"
local PENDING = "games/drive-lab/src/shared/Config/Cars/DR458/ModelPending.luau"
local FIXTURE = "games/drive-lab/tests/fixtures/dr458_manifest.json"
local CANDIDATES = {
	"../drive-lab-assets/dr458/work/manifest/dr458_manifest.json",
	"../../../drive-lab-assets/dr458/work/manifest/dr458_manifest.json",
}
-- The fields of a part the binding and its specs read; everything else stays out of the repo.
local KEPT = { "name", "group", "motion", "pivot", "axis", "range", "positive", "mesh", "screen", "outlet" }

local write = false
local path: string? = process.env.DR458_MANIFEST
for _, argument in process.args do
	if argument == "--write" then
		write = true
	else
		path = argument
	end
end
if path == nil then
	for _, candidate in CANDIDATES do
		if fs.isFile(candidate) then
			path = candidate
			break
		end
	end
end
if path == nil or not fs.isFile(path) then
	print("dr458_binding: no manifest here (drive-lab-assets is not in this checkout); nothing checked")
	return
end

local raw = serde.decode("json", fs.readFile(path))
local manifest: ManifestBinding.Manifest = { parts = {}, points = {} }
for name, point in raw.points or {} do
	(manifest.points :: any)[name] = { forward = point.forward, right = point.right, up = point.up }
end
for _, part in raw.parts do
	local kept = {}
	for _, key in KEPT do
		kept[key] = part[key]
	end
	table.insert(manifest.parts, kept :: any)
end

local problems = ManifestBinding.problems(manifest, Settings)
if #problems > 0 then
	print(`dr458_binding: the manifest has problems:\n  {table.concat(problems, "\n  ")}`)
	if write then
		process.exit(1)
	end
	return
end

local model, pending = ManifestBinding.binding(manifest, DR458, Settings)
local modelText, pendingText = ManifestBinding.render(model, pending, TOOL)

-- As the format gate would leave it: through stylua with the repo's settings, by way of a
-- scratch file in the system's temporary folder.
local function formatted(text: string, name: string): string
	local folder = process.env.TEMP or process.env.TMPDIR or "."
	local scratch = `{folder}/{name}`
	fs.writeFile(scratch, text)
	local result = process.exec("stylua", { "--config-path", "stylua.toml", scratch })
	assert(result.ok, `stylua failed: {result.stderr}`)
	local out = fs.readFile(scratch)
	fs.removeFile(scratch)
	return out
end

modelText, pendingText =
	formatted(modelText, "dr458_Model.luau"), formatted(pendingText, "dr458_ModelPending.luau")
if write then
	fs.writeFile(MODEL, modelText)
	fs.writeFile(PENDING, pendingText)
	fs.writeFile(FIXTURE, serde.encode("json", manifest, true) .. "\n")
	print(`dr458_binding: wrote {MODEL}, {PENDING} and {FIXTURE} from {path}; {#pending} still pending`)
	return
end
local current = if fs.isFile(MODEL) then fs.readFile(MODEL) else ""
local currentPending = if fs.isFile(PENDING) then fs.readFile(PENDING) else ""
if current == modelText and currentPending == pendingText then
	print(`dr458_binding: the binding matches {path}`)
else
	print(`dr458_binding: STALE, the binding no longer matches {path}; run it again with --write`)
end
