--!strict
--[[
	Studio side of tools/blender/split_lights.py: puts the split light pieces, uploaded as one
	model, into a car model in the place (docs/pipelines/HERO_CAR.md section 8). Each piece goes
	at the place part it was cut from, moved by its box centre minus that part's: the export's
	axes are the place's at import scale. dry() checks without touching the car; apply() backs up
	the parts it changes into ServerStorage, swaps the housings and windows with ApplyMesh (which
	sets neither Size nor CFrame), adds the lamp pieces with their corner's SurfaceAppearance and a
	uniform white emissive mask, and makes the lamp glass clear, as one undo step.

	From the MCP, with the repo served on localhost and lights.json read by the caller:
	    local m = Instance.new("ModuleScript")
	    m.Source = game:GetService("HttpService"):GetAsync("http://localhost:8765/tools/studio/lights_place.luau")
	    local Place = require(m)
	    Place.dry(workspace.CarImport, 104309398981863, report)
	    Place.apply(workspace.CarImport, 104309398981863, report, "rbxassetid://122009556688821")
]]
local ChangeHistoryService = game:GetService("ChangeHistoryService") :: any
local InsertService = game:GetService("InsertService")
local ServerStorage = game:GetService("ServerStorage")

export type Box = { min: { number }, max: { number } }
export type Report = { sources: { [string]: Box }, pieces: { [string]: Box } }

type Target = { cframe: CFrame, size: Vector3, source: MeshPart }

local CORNERS = { "FrontLeft", "FrontRight", "RearLeft", "RearRight" }
local BACKUP = "CarImport_lights_backup"
local CHANGED = {
	"Light_FrontLeft",
	"Light_FrontRight",
	"Light_RearLeft",
	"Light_RearRight",
	"Window_Window_Material_1",
	"WindowInside_Window_Material_1",
}
-- Clear polycarbonate: the covers were the windows' near-black Glass at 0.55.
local LAMP_GLASS = { color = Color3.fromRGB(222, 228, 234), transparency = 0.85 }

local function vector(values: { number }): Vector3
	return Vector3.new(values[1], values[2], values[3])
end

local function centre(box: Box): Vector3
	return (vector(box.min) + vector(box.max)) / 2
end

-- The place part a piece was cut from: a lamp from its corner, the lamp glass from the outer
-- window, a housing or a window from itself.
local function sourceOf(name: string): string
	if name == "LampGlass" then
		return "Window_Window_Material_1"
	end
	return string.match(name, "^(Light_%a+)_%a+$") or name
end

local function meshPart(model: Instance, name: string): MeshPart
	local found = model:FindFirstChild(name, true)
	assert(found and found:IsA("MeshPart"), `{model:GetFullName()} has no MeshPart {name}`)
	return found
end

local function load(modelId: number): (Instance, { [string]: MeshPart })
	local container = InsertService:LoadAsset(modelId)
	local parts: { [string]: MeshPart } = {}
	for _, descendant in container:GetDescendants() do
		if descendant:IsA("MeshPart") then
			parts[descendant.Name] = descendant
		end
	end
	return container, parts
end

local function targets(car: Model, report: Report): { [string]: Target }
	local found: { [string]: Target } = {}
	for name, box in report.pieces do
		local sourceName = sourceOf(name)
		local source = meshPart(car, sourceName)
		local sourceBox = report.sources[sourceName]
		assert(sourceBox, `lights.json has no source box for {sourceName}`)
		found[name] = {
			cframe = source.CFrame * CFrame.new(centre(box) - centre(sourceBox)),
			size = vector(box.max) - vector(box.min),
			source = source,
		}
	end
	return found
end

local Place = {}

-- Every piece present at its box's size, and each corner's pieces rebuilding its part's box;
-- returns one line per check.
function Place.dry(car: Model, modelId: number, report: Report): string
	local container, parts = load(modelId)
	local found = targets(car, report)
	local lines = {}
	for name, target in found do
		local piece: MeshPart? = parts[name]
		if piece == nil then
			table.insert(lines, `MISSING {name}`)
		elseif (piece.Size - target.size).Magnitude > 2e-3 then
			table.insert(lines, `{name} size {piece.Size} against {target.size}`)
		end
	end
	for _, corner in CORNERS do
		local housing = meshPart(car, `Light_{corner}`)
		local low, high = Vector3.one * math.huge, -Vector3.one * math.huge
		for name, target in found do
			if sourceOf(name) == housing.Name then
				local at = housing.CFrame:PointToObjectSpace(target.cframe.Position)
				low = low:Min(at - target.size / 2)
				high = high:Max(at + target.size / 2)
			end
		end
		local off = math.max(((low + high) / 2).Magnitude, ((high - low) - housing.Size).Magnitude)
		table.insert(lines, string.format("%s: pieces rebuild its box within %.5f studs", corner, off))
	end
	container:Destroy()
	return table.concat(lines, "\n")
end

local function addPiece(name: string, piece: MeshPart, target: Target, whiteMask: string)
	local source = target.source
	local new = piece:Clone()
	new:ClearAllChildren()
	new.Name = name
	new.Material = source.Material
	new.Color = source.Color
	new.Transparency = source.Transparency
	new.Reflectance = source.Reflectance
	new.CastShadow = source.CastShadow
	new.DoubleSided = source.DoubleSided
	new.RenderFidelity = source.RenderFidelity
	new.Anchored = source.Anchored
	new.CanCollide = source.CanCollide
	new.Size = target.size
	new.CFrame = target.cframe
	if name == "LampGlass" then
		new.Color = LAMP_GLASS.color
		new.Transparency = LAMP_GLASS.transparency
		new.Reflectance = 0
	else
		local look = source:FindFirstChildOfClass("SurfaceAppearance")
		if look then
			local copy = look:Clone()
			copy.EmissiveMaskContent = Content.fromUri(whiteMask)
			copy.EmissiveStrength = 0
			copy.Parent = new
		end
	end
	new.Parent = source.Parent
end

-- whiteMask: a uniform white image, the lamp pieces' emissive mask, so a lamp glows over its
-- whole surface, shaded by its colour map.
function Place.apply(car: Model, modelId: number, report: Report, whiteMask: string): string
	assert(ServerStorage:FindFirstChild(BACKUP) == nil, `ServerStorage.{BACKUP} exists: already applied?`)
	local container, parts = load(modelId)
	local found = targets(car, report)
	local recording = ChangeHistoryService:TryBeginRecording("Split car lights (#41)")
	local backup = Instance.new("Folder")
	backup.Name = BACKUP
	for _, name in CHANGED do
		meshPart(car, name):Clone().Parent = backup
	end
	backup.Parent = ServerStorage
	local added = 0
	for name, target in found do
		local piece = parts[name]
		assert(piece, `the uploaded model has no {name}`)
		local existing = car:FindFirstChild(name, true)
		if existing and existing:IsA("MeshPart") then
			existing:ApplyMesh(piece)
			existing.Size = target.size
			existing.CFrame = target.cframe
		else
			addPiece(name, piece, target, whiteMask)
			added += 1
		end
	end
	container:Destroy()
	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
	return `swapped {#CHANGED}, added {added}; backup in ServerStorage.{BACKUP}`
end

return Place
