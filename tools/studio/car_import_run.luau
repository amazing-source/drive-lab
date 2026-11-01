--!strict
--[[
	Imports a car into the place from its uploaded model: paste into execute_luau, EDIT MODE only. The
	module (tools/studio/car_import.luau) and the data (tools/assets/car_import_data.py) are fetched
	from local servers, e.g. the repository on 8765 and the car's import folder on 8766:
	    python -I -m http.server 8766 --bind 127.0.0.1 --directory <car work>/import/studio

	Fill the CONFIG block, then run with MODE = "check" (changes nothing: maps resolved, the upload
	loaded and matched against the data, then destroyed), MODE = "build" (one undo step, then the
	checks of verify), and MODE = "verify" any time after (read only). Returns a JSON report; "ok" is
	false and "fail" lists why when any check fails. Resolved images come back in "images": record them
	in the work folder's ids file.
]]

-- CONFIG (the coordinator fills these after the upload) ------------------------------------------
local MODE = "check" -- "check" | "build" | "verify"
local MODEL_ID = 0 -- the car.glb's Model asset id
local MODEL_NAME = "Boss302" -- the Workspace model's name
local MODULE_URL = "http://localhost:8765/tools/studio/car_import.luau"
local DATA_URL = "http://127.0.0.1:8766/" -- serves the files below
local DATA_FILE = "import_data.json"
-- upload_images.py's output for the maps ({ label: Decal id }); "" when nothing new was uploaded.
local UPLOADS_FILE = "upload_result_maps.json"
-- A re-import only: the old car's backup name in ServerStorage.
local BACKUP_NAME = ""
-- A first import: where the car's bounding box goes; nil = beside BESIDE, as far again from it as it
-- is from FROM, its box's bottom level with BESIDE's.
local PLACE: { x: number, z: number, bottom: number }? = nil
local BESIDE, FROM = "DR458", "CarImport"
-- ------------------------------------------------------------------------------------------------

local ChangeHistoryService = game:GetService("ChangeHistoryService") :: any
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local report: { [string]: any } = { mode = MODE, fail = {} }
local function fail(message: string)
	table.insert(report.fail, message)
end
local function finish(): string
	report.ok = #report.fail == 0
	return HttpService:JSONEncode(report)
end

local function fetch(url: string): string
	return HttpService:GetAsync(url .. "?v=" .. os.clock())
end

-- The same undo step as tools/studio/dev.luau's record: committed whole, or cancelled on an error.
local dev = {}
function dev.record<T>(name: string, action: () -> T): T
	local recording = ChangeHistoryService:TryBeginRecording(name)
	local ok, result = pcall(action)
	if recording then
		ChangeHistoryService:FinishRecording(
			recording,
			if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
		)
	end
	if not ok then
		error(result, 2)
	end
	return result
end

if RunService:IsRunning() then
	fail("a playtest is running: edit mode only")
	return finish()
end
if MODE ~= "check" and MODE ~= "build" and MODE ~= "verify" then
	fail("MODE must be check, build or verify")
	return finish()
end

local moduleScript = Instance.new("ModuleScript")
moduleScript.Source = fetch(MODULE_URL)
local Import = (require :: any)(moduleScript)
local data = HttpService:JSONDecode(fetch(DATA_URL .. DATA_FILE))
local expect = data.expect
local rawName = `{MODEL_NAME}_Upload_{MODEL_ID}`
local SPAWN = Import.SPAWN_TAG

-- The spawn the road starts from and its Car attribute, by the place's own rule and config
-- (Rules/TrackPath.startIndex, Config/Driving.ROAD_START_CAR); nil when the place lacks them.
local function roadStart(): (Instance?, string?)
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local rules = shared and shared:FindFirstChild("Rules")
	local config = shared and shared:FindFirstChild("Config")
	local trackPath = rules and rules:FindFirstChild("TrackPath")
	local driving = config and config:FindFirstChild("Driving")
	if not (trackPath and trackPath:IsA("ModuleScript") and driving and driving:IsA("ModuleScript")) then
		return nil, nil
	end
	local preferred = (require :: any)(driving).ROAD_START_CAR
	if preferred == nil then
		return nil, nil
	end
	local spawns = CollectionService:GetTagged(SPAWN)
	local names, cars = {}, {}
	for index, m in spawns do
		names[index] = m:GetFullName()
		cars[index] = m:GetAttribute("Car")
	end
	local index = (require :: any)(trackPath).startIndex(names, cars, preferred)
	return if index then spawns[index] else nil, preferred
end

-- After a build: the rules every import keeps, and the car against its backup on a re-import.
local function verify()
	local car = workspace:FindFirstChild(MODEL_NAME)
	if not (car and car:IsA("Model")) then
		fail("verify: Workspace." .. MODEL_NAME .. " missing")
		return
	end
	local parts = #car:GetChildren()
	report.parts = parts
	if parts ~= expect.parts then
		fail(`verify: {parts} parts, want {expect.parts}`)
	end
	local withSA = 0
	for _, p in car:GetChildren() do
		if p:FindFirstChildOfClass("SurfaceAppearance") then
			withSA += 1
		end
	end
	report.withSA = withSA
	if withSA ~= expect.withSA then
		fail(`verify: {withSA} SurfaceAppearances, want {expect.withSA}`)
	end
	-- Every piece by its name with its attributes; every name the binding looks up.
	for _, info in data.pieces do
		local p = car:FindFirstChild(info.name)
		if not (p and p:IsA("MeshPart")) then
			fail("verify: piece missing " .. info.name)
		elseif p:GetAttribute("Part") ~= info.part or p:GetAttribute("Group") ~= info.group then
			fail(`verify: {info.name} Part/Group attributes`)
		end
	end
	local missing = Import.missing(car, data.bindingNames)
	report.bindingNames = { checked = #data.bindingNames, missing = missing }
	if #missing > 0 then
		fail("verify: the binding names parts the car lacks: " .. table.concat(missing, ", "))
	end
	-- Lamps: every one masked white at strength 0; the listed ones the white colour map.
	for _, name in data.lamps do
		local p = car:FindFirstChild(name)
		local sa = p and p:FindFirstChildOfClass("SurfaceAppearance")
		if not sa or tostring(sa.EmissiveMaskContent.Uri) ~= data.mask or sa.EmissiveStrength ~= 0 then
			fail("verify: lamp mask " .. name)
		end
		local map = data.lampColorMaps[name]
		if map and (not sa or tostring(sa.ColorMapContent.Uri) ~= map) then
			fail("verify: lamp colour map " .. name)
		end
	end
	-- Emissive masks (the live cluster lights them) at strength 0.
	local emissive = 0
	for name, mask in data.emissive do
		local p = car:FindFirstChild(name)
		local sa = p and p:FindFirstChildOfClass("SurfaceAppearance")
		if not sa or tostring(sa.EmissiveMaskContent.Uri) ~= mask or sa.EmissiveStrength ~= 0 then
			fail("verify: emissive mask " .. name)
		else
			emissive += 1
		end
	end
	report.emissive = emissive
	-- The car is a spawn; nothing tagged sits in ServerStorage; the road starts where it did.
	if car:GetAttribute("Car") ~= data.car then
		fail("verify: Car attribute " .. tostring(car:GetAttribute("Car")))
	end
	if not CollectionService:HasTag(car, SPAWN) then
		fail("verify: the car lacks the spawn tag")
	end
	local spawns = {}
	for _, m in CollectionService:GetTagged(SPAWN) do
		table.insert(spawns, m:GetFullName())
		if m:IsDescendantOf(ServerStorage) then
			fail("verify: a spawn-tagged model in ServerStorage: " .. m:GetFullName())
		end
	end
	table.sort(spawns)
	report.spawns = spawns
	local start, preferred = roadStart()
	report.roadStart = if start then start:GetFullName() else nil
	if preferred == nil then
		fail("verify: the place has no road-start rule (Config/Driving.ROAD_START_CAR): sync main first")
	elseif start == nil or start:GetAttribute("Car") ~= preferred then
		fail(`verify: the road starts from {report.roadStart}, not from the {preferred}'s spawn`)
	elseif report.roadStartBefore and report.roadStart ~= report.roadStartBefore then
		fail(`verify: the road start moved from {report.roadStartBefore} to {report.roadStart}`)
	end
	if not ServerStorage:FindFirstChild(rawName) then
		fail("verify: raw upload not kept as ServerStorage." .. rawName)
	end
	if not data.firstImport then
		local backup = ServerStorage:FindFirstChild(BACKUP_NAME)
		if not (backup and backup:IsA("Model")) then
			fail("verify: the backup ServerStorage." .. BACKUP_NAME .. " is missing")
		else
			local cmp = Import.compare(backup, car)
			report.compare = cmp
			local changed = {}
			for name in cmp.changed do
				table.insert(changed, name)
			end
			table.sort(changed)
			local found: { [string]: { string } } = { new = cmp.new, gone = cmp.gone, changed = changed }
			for key, list in found do
				if table.concat(list, ",") ~= table.concat(expect[key], ",") then
					fail(
						`verify: {key} pieces {table.concat(list, ",")}, want {table.concat(expect[key], ",")}`
					)
				end
			end
			if #CollectionService:GetTags(backup) ~= 0 then
				fail("verify: the backup still has tags")
			end
		end
	end
	local cf, size = car:GetBoundingBox()
	report.bbox =
		{ centre = tostring(cf.Position), size = tostring(size), pivot = tostring(car:GetPivot().Position) }
end

local decals: { [string]: any } = {}
if UPLOADS_FILE ~= "" then
	decals = HttpService:JSONDecode(fetch(DATA_URL .. UPLOADS_FILE))
end
local cache: { [string]: string } = {}

if MODE == "verify" then
	-- The data's maps as the build resolved them, so a new map is compared by its image.
	local unresolved = Import.resolveData(data, decals, cache)
	if #unresolved > 0 then
		fail(`verify: {#unresolved} maps unresolved: {table.concat(unresolved, ", "):sub(1, 400)}`)
	end
	verify()
	return finish()
end

-- Preconditions for check and build.
if MODEL_ID == 0 then
	fail("MODEL_ID not filled")
end
for _, stem in data.pendingMaps do
	local id = decals[stem]
	if type(id) ~= "number" and not (type(id) == "string" and string.match(id, "^%d+$")) then
		fail(`{UPLOADS_FILE} has no Decal id for {stem} ({tostring(id)})`)
	end
end
local old = workspace:FindFirstChild(MODEL_NAME)
if data.firstImport then
	if old then
		fail(`Workspace.{MODEL_NAME} exists: a first import does not replace a car`)
	end
	for _, m in CollectionService:GetTagged(SPAWN) do
		if m:GetAttribute("Car") == data.car then
			fail(`{m:GetFullName()} is already a {data.car}`)
		end
	end
	if PLACE == nil then
		local beside, from = workspace:FindFirstChild(BESIDE), workspace:FindFirstChild(FROM)
		if not (beside and beside:IsA("Model") and from and from:IsA("Model")) then
			fail(`PLACE is nil and Workspace.{BESIDE} or Workspace.{FROM} is missing: fill PLACE`)
		else
			local largest: BasePart? = nil
			for _, p in beside:GetChildren() do
				if p:IsA("BasePart") and (largest == nil or p.Size.Magnitude > largest.Size.Magnitude) then
					largest = p
				end
			end
			if largest == nil or not largest.CFrame.Rotation:FuzzyEq(CFrame.identity, 1e-4) then
				fail(`Workspace.{BESIDE} is rotated: the import places cars unrotated, fill PLACE`)
			end
			local a, b = beside:GetPivot().Position, from:GetPivot().Position
			local box, size = beside:GetBoundingBox()
			PLACE = { x = a.X + (a.X - b.X), z = a.Z + (a.Z - b.Z), bottom = box.Position.Y - size.Y / 2 }
		end
	end
	report.place = PLACE
elseif not (old and old:IsA("Model")) then
	fail("no Workspace." .. MODEL_NAME .. " model to re-import")
elseif BACKUP_NAME == "" or ServerStorage:FindFirstChild(BACKUP_NAME) then
	fail("BACKUP_NAME empty or taken in ServerStorage")
end
if ServerStorage:FindFirstChild(rawName) then
	fail("ServerStorage." .. rawName .. " exists already")
end
local startBefore = roadStart()
report.roadStartBefore = if startBefore then startBefore:GetFullName() else nil
if #report.fail > 0 then
	return finish()
end

-- Maps to images, then the upload against the data.
local t0 = os.clock()
local unresolved = Import.resolveData(data, decals, cache)
report.images = cache
report.resolveSeconds = os.clock() - t0
if #unresolved > 0 then
	fail(`{#unresolved} maps unresolved: {table.concat(unresolved, ", "):sub(1, 400)}`)
end
local source = InsertService:LoadAsset(MODEL_ID)
report.loadSeconds = os.clock() - t0
local loaded, extra, seen = 0, {}, {}
for _, d in source:GetDescendants() do
	if d:IsA("MeshPart") then
		loaded += 1
		if data.pieces[d.Name] then
			seen[d.Name] = true
		else
			table.insert(extra, d.Name)
		end
	end
end
local missing = {}
for name in data.pieces do
	if not seen[name] then
		table.insert(missing, name)
	end
end
report.upload = { meshParts = loaded, missing = missing, extra = extra }
if loaded ~= expect.parts or #missing > 0 or #extra > 0 then
	fail(`the upload has {loaded} MeshParts ({#missing} missing, {#extra} extra), want {expect.parts}`)
end
if #report.fail > 0 or MODE == "check" then
	source:Destroy()
	return finish()
end

local built = Import.build(dev, {
	label = `Import {MODEL_NAME} ({MODEL_ID})`,
	data = data,
	source = source,
	modelName = MODEL_NAME,
	keepRawAs = rawName,
	backupName = if BACKUP_NAME ~= "" then BACKUP_NAME else nil,
	place = PLACE,
})
report.build = HttpService:JSONDecode(built)
if #report.build.missing > 0 or #report.build.extra > 0 then
	fail("build: missing or extra pieces")
end
verify()
return finish()
