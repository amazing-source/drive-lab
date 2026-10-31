--!strict
--[[
	Writes a car's model binding from its 3D manifest (tools/CarBindings, tools/ManifestBinding):
	Model.luau, ModelPending.luau, and the redacted copy the specs read (names, groups, motions and
	geometry, without sources or file paths). Without `--write` it only reports whether the committed
	binding matches the manifest; with no manifest on this machine (in CI) it says so and stops.
]]
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local CarBindings = require("./CarBindings")
local ManifestBinding = require("./ManifestBinding")

-- The fields of a part the binding and its specs read; everything else stays out of the repo.
local KEPT = {
	"name",
	"group",
	"motion",
	"pivot",
	"axis",
	"range",
	"positive",
	"mesh",
	"screen",
	"outlet",
	"axis_fore",
	"axis_side",
	"gates_rad",
	"knob",
	"push_m",
}

local CarBindingTool = {}

-- As the format gate would leave it: through stylua with the repo's settings, by way of a scratch
-- file in the system's temporary folder.
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

local function found(car: CarBindings.Car, asked: string?): string?
	if asked then
		return if fs.isFile(asked) then asked else nil
	end
	for _, candidate in car.manifests do
		if fs.isFile(candidate) then
			return candidate
		end
	end
	return nil
end

-- Checks or writes the binding of the car `name`, from `manifestPath` or the first of its known
-- places that exists.
function CarBindingTool.run(name: string, write: boolean, manifestPath: string?)
	local car = assert(CarBindings[name], `no car {name} in tools/CarBindings`)
	local label = `car_binding {name}`
	local path = found(car, manifestPath)
	if path == nil then
		print(`{label}: no manifest here (drive-lab-assets is not in this checkout); nothing checked`)
		return
	end
	local raw = serde.decode("json", fs.readFile(path))
	local manifest: ManifestBinding.Manifest = { parts = {}, points = {} }
	for point, value in raw.points or {} do
		(manifest.points :: any)[point] = { forward = value.forward, right = value.right, up = value.up }
	end
	for _, part in raw.parts do
		local kept = {}
		for _, key in KEPT do
			kept[key] = part[key]
		end
		-- Of the knob only its ball's geometry: no source object names leave drive-lab-assets.
		local knob = part.knob
		if knob then
			kept.knob = { centre = knob.centre, radius_m = knob.radius_m }
		end
		table.insert(manifest.parts, kept :: any)
	end

	local problems = ManifestBinding.problems(manifest, car.settings)
	if #problems > 0 then
		print(`{label}: the manifest has problems:\n  {table.concat(problems, "\n  ")}`)
		if write then
			process.exit(1)
		end
		return
	end

	local model, pending = ManifestBinding.binding(manifest, car.physics, car.settings)
	for _, note in car.notes do
		table.insert(pending, note)
	end
	table.sort(pending)
	local modelText, pendingText = ManifestBinding.render(model, pending, car.tool)
	modelText = formatted(modelText, `{name}_Model.luau`)
	pendingText = formatted(pendingText, `{name}_ModelPending.luau`)
	if write then
		fs.writeFile(car.model, modelText)
		fs.writeFile(car.pending, pendingText)
		fs.writeFile(car.fixture, serde.encode("json", manifest, true) .. "\n")
		print(
			`{label}: wrote {car.model}, {car.pending} and {car.fixture} from {path}; {#pending} still pending`
		)
		return
	end
	local current = if fs.isFile(car.model) then fs.readFile(car.model) else ""
	local currentPending = if fs.isFile(car.pending) then fs.readFile(car.pending) else ""
	if current == modelText and currentPending == pendingText then
		print(`{label}: the binding matches {path}`)
	else
		print(`{label}: STALE, the binding no longer matches {path}; run it again with --write`)
	end
end

return table.freeze(CarBindingTool)
