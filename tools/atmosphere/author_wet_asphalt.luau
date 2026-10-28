--!strict
--[[
	Authors the wet road's MaterialVariant states into the open place's MaterialService, from
	Config.Atmosphere.WET_ROAD (ids, names, tile size). MaterialVariant maps can only be set by a
	plugin, so this runs in Studio edit mode (command bar or the MCP execute tool), after a sync
	has put Config/Atmosphere into ReplicatedStorage. Idempotent: it replaces the folder it owns.
	Save the place afterwards for the states to exist in playtests. Belongs in tools/studio/ once
	the owner accepts it; kept here meanwhile so nothing outside the atmosphere files changed.
]]
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local MaterialService = game:GetService("MaterialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FOLDER = "DriveLabWetRoad"

local configModule =
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Atmosphere")
local road = (require :: any)(configModule).WET_ROAD
local base = Enum.Material:FromName(road.material)
assert(base, `unknown material {road.material}`)

local recording = ChangeHistoryService:TryBeginRecording("Author wet road MaterialVariants")
local ok, problem = pcall(function()
	local previous = MaterialService:FindFirstChild(FOLDER)
	if previous then
		previous:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER
	for _, stage in road.stages do
		local variant = Instance.new("MaterialVariant")
		variant.Name = stage.variant
		variant.BaseMaterial = base
		variant.ColorMap = stage.color
		variant.NormalMap = stage.normal
		variant.RoughnessMap = stage.roughness
		variant.StudsPerTile = road.studsPerTile
		variant.Parent = folder
	end
	folder.Parent = MaterialService
end)
if recording then
	ChangeHistoryService:FinishRecording(
		recording,
		if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
	)
end
if not ok then
	error(problem)
end
return `authored {#road.stages} wet road states under MaterialService.{FOLDER}`
