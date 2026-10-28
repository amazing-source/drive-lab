--!strict
--[[
	Studio side of the dev loop. Studio pulls source from the repo over localhost, so
	git stays the single source of truth and syncing needs no plugin click.

	Repo root:  python -I -m http.server 8765 --bind 127.0.0.1
	Game dir:   rojo sourcemap default.project.json -o sourcemap.json --watch
	MCP:        local m = Instance.new("ModuleScript")
	            m.Source = game:GetService("HttpService"):GetAsync("http://localhost:8765/tools/studio/dev.luau")
	            require(m).sync("games/<game>")
]]

-- The recording API is plugin-only and missing from the type definitions.
local ChangeHistoryService = game:GetService("ChangeHistoryService") :: any
local HttpService = game:GetService("HttpService")
local ScriptEditorService = game:GetService("ScriptEditorService")
local ServerStorage = game:GetService("ServerStorage")

local ORIGIN = "http://localhost:8765/"

local CONTAINER_CLASSES = {
	ReplicatedFirst = true,
	ReplicatedStorage = true,
	ServerScriptService = true,
	ServerStorage = true,
	StarterGui = true,
	StarterPlayer = true,
	StarterPlayerScripts = true,
	StarterCharacterScripts = true,
	Workspace = true,
}

type SourcemapNode = {
	name: string,
	className: string,
	filePaths: { string }?,
	children: { SourcemapNode }?,
}

type SyncStats = { written: number, removed: number, unchanged: number, roots: { Instance } }

local function fetch(path: string): string
	return HttpService:GetAsync(ORIGIN .. path .. "?v=" .. os.clock())
end

local function resolvePath(base: string, relative: string): string
	local segments = string.split(base, "/")
	for _, segment in string.split(relative, "/") do
		if segment == ".." then
			table.remove(segments)
		elseif segment ~= "." and segment ~= "" then
			table.insert(segments, segment)
		end
	end
	return table.concat(segments, "/")
end

local function syncOwned(
	node: SourcemapNode,
	parent: Instance,
	projectDir: string,
	stats: SyncStats
): Instance
	local instance = parent:FindFirstChild(node.name)
	if instance and instance.ClassName ~= node.className then
		instance:Destroy()
		instance = nil
	end
	local target = instance or Instance.new(node.className)
	target.Name = node.name

	local file = node.filePaths and node.filePaths[1]
	if file and target:IsA("LuaSourceContainer") then
		local source = fetch(resolvePath(projectDir, file))
		local script = target :: any
		if script.Source == source then
			stats.unchanged += 1
		else
			-- A script open in an editor tab keeps its own buffer and can write it back over a
			-- plain Source assignment; the editor service updates the tab as well.
			if instance then
				ScriptEditorService:UpdateSourceAsync(target :: LuaSourceContainer, function()
					return source
				end)
			else
				script.Source = source
			end
			stats.written += 1
		end
	end

	local kept: { [Instance]: boolean } = {}
	for _, child in (node.children or {}) :: { SourcemapNode } do
		kept[syncOwned(child, target, projectDir, stats)] = true
	end
	for _, child in target:GetChildren() do
		if not kept[child] then
			child:Destroy()
			stats.removed += 1
		end
	end

	target.Parent = parent
	return target
end

local function syncContainer(node: SourcemapNode, container: Instance, projectDir: string, stats: SyncStats)
	for _, child in (node.children or {}) :: { SourcemapNode } do
		if CONTAINER_CLASSES[child.className] then
			local nested = if container == game
				then game:GetService(child.className)
				else container:FindFirstChildOfClass(child.className)
			assert(nested, `missing container {child.className} under {container:GetFullName()}`)
			syncContainer(child, nested, projectDir, stats)
		else
			table.insert(stats.roots, syncOwned(child, container, projectDir, stats))
		end
	end
end

-- Studio caches a module's result per ModuleScript instance, even across edits to its
-- Source, so an edit-mode require after a sync would still run the old code. Swapping
-- every synced tree for a copy gives each module a fresh instance and an empty cache.
local function refresh(roots: { Instance })
	for _, root in roots do
		local parent = root.Parent
		local copy = root:Clone()
		root:Destroy()
		copy.Parent = parent
	end
end

local dev = {}

-- Studio folds plugin edits made outside a recording into the user's previous undo step,
-- so a single Ctrl+Z rolled back every sync and build since the last drag. Each operation
-- run through here is its own step instead, and one that fails is rolled back whole.
function dev.record<T>(name: string, action: () -> T): T
	local recording = ChangeHistoryService:TryBeginRecording(name)
	local ok, result = pcall(action)
	if recording then
		local operation = if ok
			then Enum.FinishRecordingOperation.Commit
			else Enum.FinishRecordingOperation.Cancel
		ChangeHistoryService:FinishRecording(recording, operation)
	end
	if not ok then
		error(result, 2)
	end
	return result
end

function dev.sync(projectDir: string): string
	return dev.record(`Sync {projectDir}`, function()
		local root = HttpService:JSONDecode(fetch(`{projectDir}/sourcemap.json`)) :: SourcemapNode
		local stats: SyncStats = { written = 0, removed = 0, unchanged = 0, roots = {} }
		syncContainer(root, game, projectDir, stats)
		refresh(stats.roots)
		return `synced {projectDir}: {stats.written} written, {stats.unchanged} unchanged, {stats.removed} removed`
	end)
end

function dev.load(path: string): any
	local module = Instance.new("ModuleScript")
	module.Name = string.match(path, "([^/]+)%.luau$") or path
	module.Source = fetch(path)
	module.Parent = ServerStorage
	local ok, result = pcall(require, module)
	module:Destroy()
	if not ok then
		error(`{path}: {result}`, 2)
	end
	return result
end

local function toSwatches(palette: { [string]: { [string]: any } }): { [string]: any }
	local swatches = {}
	for key, swatch in palette do
		swatches[key] = {
			color = Color3.fromHex(swatch.color),
			material = if swatch.material then (Enum.Material :: any)[swatch.material] else nil,
			reflectance = swatch.reflectance,
			transparency = swatch.transparency,
		}
	end
	return swatches
end

function dev.voxelModel(specPath: string, at: CFrame, parent: Instance?): Model
	local VoxelGrid = dev.load("kit/src/Voxel/VoxelGrid.luau")
	local VoxelBuild = dev.load("kit/src/Voxel/VoxelBuild.luau")
	local spec = dev.load(specPath)(VoxelGrid)

	local voxel = spec.voxel
	local palette = toSwatches(spec.palette)
	local origin = at * CFrame.new(-spec.size[1] * voxel / 2, 0, -spec.size[2] * voxel / 2)
	local container = parent or workspace
	local previous = container:FindFirstChild(spec.name)
	if previous then
		previous:Destroy()
	end

	local model = Instance.new("Model")
	model.Name = spec.name
	local body = Instance.new("Model")
	body.Name = "Body"
	body.Parent = model
	VoxelBuild.boxes(spec.body:greedy(), palette, voxel, origin, Vector3.zero, body)
	VoxelBuild.ramps(spec.ramps or {}, palette, voxel, origin, Vector3.zero, body)
	for _, wheel in spec.wheels or {} do
		local wheelModel = Instance.new("Model")
		wheelModel.Name = wheel.name
		wheelModel.Parent = model
		local wheelVoxel = wheel.voxel or voxel
		local offset = Vector3.new(wheel.at[1], wheel.at[2], wheel.at[3]) * (voxel / wheelVoxel)
		VoxelBuild.boxes(wheel.grid:greedy(), palette, wheelVoxel, origin, offset, wheelModel)
	end
	model.Parent = container
	return model
end

return dev
