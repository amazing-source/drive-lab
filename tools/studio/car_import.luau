--!strict
--[[
	Edit-mode import of a car from an uploaded model, driven by tools/studio/car_import_run.luau with
	the data tools/assets/car_import_data.py writes:
	    Import.resolveDecal(id)             -- a Decal id's image, by LoadAsset; changes nothing
	    Import.resolveData(data, decals)    -- every map in the data to an image uri, in place
	    Import.build(dev, opts)             -- one dev.record undo step
	    Import.compare(backup, car)         -- read only: piece by piece
	    Import.missing(car, names)          -- read only: the names with no BasePart in the car

	build clones the loaded upload, names and dresses every piece from the data (Part / Group
	attributes, RenderFidelity Precise, SurfaceAppearances, flat sets, emissive masks, overrides),
	gives every lamp the uniform white emissive mask at EmissiveStrength 0 (and the listed lamps the
	same white image as their colour map: Roblox multiplies a glow by it), and places the car:
	- a re-import by the offset its unchanged pieces had in the old car, keeping the old one's pivot,
	  attributes and tags; the old one goes to ServerStorage as a backup without its tags (Cars and
	  Track use GetTagged, which also finds ServerStorage);
	- a first import by the export's own origins, then moved so its bounding box sits where the
	  runner says, with its pivot at the box's centre, the Car attribute and the spawn tag.
	The raw upload is kept in ServerStorage in the same undo step.
]]
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local InsertService = game:GetService("InsertService")
local ServerStorage = game:GetService("ServerStorage")

local Import = {}

Import.SPAWN_TAG = "DriveLabCarSpawn"
Import.MAPS = { "ColorMap", "NormalMap", "RoughnessMap", "MetalnessMap" }

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function applyPart(p: BasePart, props: { [string]: any }?)
	if props == nil then
		return
	end
	if props.Material then
		p.Material = (Enum.Material :: any)[props.Material]
	end
	if props.Color then
		p.Color = rgb(props.Color)
	end
	if props.Transparency then
		p.Transparency = props.Transparency
	end
	if props.Reflectance then
		p.Reflectance = props.Reflectance
	end
end

local function saOf(p: Instance): SurfaceAppearance?
	return p:FindFirstChildOfClass("SurfaceAppearance")
end

-- The image a Decal id carries, as rbxassetid://<image id>.
function Import.resolveDecal(decalId: number): string
	local container = InsertService:LoadAsset(decalId)
	local decal = container:FindFirstChildWhichIsA("Decal", true)
	local texture = if decal then decal.Texture else nil
	container:Destroy()
	assert(texture, `asset {decalId} holds no Decal`)
	local id = string.match(texture, "(%d+)$")
	assert(id, `Decal {decalId} has no image id in {texture}`)
	return "rbxassetid://" .. id
end

-- A data uri: "rbxassetid://" as is; "decal:<id>" and "pending:<stem>" (its Decal id from `decals`,
-- the upload result) resolved through their Decal; anything unresolvable as "unresolved:<why>".
function Import.resolveUri(value: string, decals: { [string]: any }, cache: { [string]: string }): string
	if string.sub(value, 1, 13) == "rbxassetid://" then
		return value
	end
	local decal: number? = nil
	if string.sub(value, 1, 6) == "decal:" then
		decal = tonumber(string.sub(value, 7))
	elseif string.sub(value, 1, 8) == "pending:" then
		decal = tonumber(decals[string.sub(value, 9)])
	end
	if decal == nil or decal == 0 then
		return "unresolved:" .. value
	end
	local key = tostring(decal)
	if cache[key] == nil then
		cache[key] = Import.resolveDecal(decal)
	end
	return cache[key]
end

-- Every map uri in the data (sets, emissive masks, the lamp mask and colour maps) resolved in place.
-- Returns the values that stayed unresolved.
function Import.resolveData(data: any, decals: { [string]: any }, cache: { [string]: string }): { string }
	local unresolved = {}
	local function resolve(value: string): string
		local uri = Import.resolveUri(value, decals, cache)
		if string.sub(uri, 1, 11) == "unresolved:" then
			table.insert(unresolved, value)
		end
		return uri
	end
	for _, set in data.sets do
		local sap = set.SurfaceAppearance
		if sap then
			for _, key in Import.MAPS do
				if sap[key] then
					sap[key] = resolve(sap[key])
				end
			end
		end
	end
	for name, uri in data.emissive do
		data.emissive[name] = resolve(uri)
	end
	data.mask = resolve(data.mask)
	for name, uri in data.lampColorMaps do
		data.lampColorMaps[name] = resolve(uri)
	end
	table.sort(unresolved)
	return unresolved
end

-- Every lamp: the uniform white emissive mask at strength 0 (the lamp code drives it), and the
-- listed lamps that same white image as their colour map.
function Import.dressLamps(car: Model, data: any): (number, number)
	local masks, maps = 0, 0
	for _, name in data.lamps do
		local p = car:FindFirstChild(name)
		assert(p, "lamp missing: " .. name)
		local sa = saOf(p)
		assert(sa, "lamp without a SurfaceAppearance: " .. name)
		sa.EmissiveMaskContent = Content.fromUri(data.mask)
		sa.EmissiveStrength = 0
		masks += 1
		local map = data.lampColorMaps[name]
		if map then
			sa.ColorMapContent = Content.fromUri(map)
			maps += 1
		end
	end
	return masks, maps
end

-- The world offset of an upload against the export: each stable piece's position minus its export
-- origin (studs); they must agree.
local function uploadOffset(car: Model, data: any, stable: { string }): (Vector3, number)
	local origins: { [string]: { number } } = {}
	for _, info in data.pieces do
		origins[info.name] = info.origin
	end
	local offsets = {}
	for _, name in stable do
		local p = car:FindFirstChild(name) :: BasePart?
		local o = origins[name]
		assert(p and o, "stable piece missing: " .. name)
		assert(p.CFrame.Rotation:FuzzyEq(CFrame.identity, 1e-4), "the upload's piece is rotated: " .. name)
		table.insert(offsets, p.Position - Vector3.new(o[1], o[2], o[3]))
	end
	local first = offsets[1]
	local spread = 0
	for _, o in offsets do
		spread = math.max(spread, (o - first).Magnitude)
	end
	return first, spread
end

export type Options = {
	label: string,
	data: any,
	source: Instance,
	-- The Workspace model's name (the Car attribute comes from the data).
	modelName: string,
	-- The raw upload is kept in ServerStorage under this name, in the same undo step.
	keepRawAs: string,
	-- A re-import: the backup's name in ServerStorage.
	backupName: string?,
	-- A first import: where the bounding box goes (its centre's X and Z, its bottom's Y).
	place: { x: number, z: number, bottom: number }?,
}

function Import.build(dev: any, opts: Options): string
	local data = opts.data
	local old = workspace:FindFirstChild(opts.modelName) :: Model?
	if data.firstImport then
		assert(old == nil, `Workspace.{opts.modelName} exists: a first import does not replace a car`)
		assert(opts.place, "a first import needs a place")
	else
		assert(old and old:IsA("Model"), `no Workspace.{opts.modelName} to replace`)
		assert(
			opts.backupName and ServerStorage:FindFirstChild(opts.backupName) == nil,
			"the backup name is missing or taken"
		)
	end
	assert(ServerStorage:FindFirstChild(opts.keepRawAs) == nil, "the raw upload's name is taken")
	local function check(uri: string, where: string)
		assert(string.sub(uri, 1, 13) == "rbxassetid://", `{where}: {uri} was not resolved`)
	end
	for setName, set in data.sets do
		for key, uri in (set.SurfaceAppearance or {}) :: { [string]: string } do
			if string.sub(key, -3) == "Map" then
				check(uri, `{setName} {key}`)
			end
		end
	end
	for name, uri in data.emissive do
		check(uri, `emissive {name}`)
	end
	check(data.mask, "lamp mask")
	local root = opts.source:FindFirstChildWhichIsA("Model") or opts.source
	return dev.record(opts.label, function()
		local car = root:Clone() :: Model
		car.Name = opts.modelName
		local report = {
			missing = {},
			extra = {},
			sa = 0,
			flat = 0,
			fallback = 0,
			emissive = 0,
			masks = 0,
			colourMaps = 0,
		}
		local seen = {}
		for _, p in car:GetDescendants() do
			if not p:IsA("MeshPart") then
				continue
			end
			local info = data.pieces[p.Name]
			if info == nil then
				table.insert(report.extra, p.Name)
				continue
			end
			seen[p.Name] = true
			p.Name = info.name
			p:SetAttribute("Part", info.part)
			p:SetAttribute("Group", info.group)
			p.Anchored = true
			p.CanCollide = false
			p.RenderFidelity = Enum.RenderFidelity.Precise
			for _, child in p:GetChildren() do
				if child:IsA("SurfaceAppearance") then
					child:Destroy()
				end
			end
			p.TextureID = ""
			local set = data.sets[info.set]
			local sa: SurfaceAppearance? = nil
			if set then
				applyPart(p, set.MeshPart)
				local sap = set.SurfaceAppearance
				if sap then
					local made = Instance.new("SurfaceAppearance")
					for _, key in Import.MAPS do
						if sap[key] then
							local target: any = made
							target[key .. "Content"] = Content.fromUri(sap[key])
						end
					end
					made.AlphaMode = (Enum.AlphaMode :: any)[sap.AlphaMode or "Overlay"]
					made.Parent = p
					sa = made
				end
			else
				applyPart(p, data.fallback[info.set])
				report.fallback += 1
			end
			local mask = data.emissive[info.name]
			if mask then
				if sa == nil then
					local made = Instance.new("SurfaceAppearance")
					made.Parent = p
					sa = made
				end
				local target = sa :: SurfaceAppearance
				target.EmissiveMaskContent = Content.fromUri(mask)
				target.EmissiveStrength = 0
				report.emissive += 1
			end
			if sa then
				report.sa += 1
			elseif set then
				report.flat += 1
			end
			applyPart(p, data.overrides[info.name])
		end
		for name in data.pieces do
			if not seen[name] then
				table.insert(report.missing, name)
			end
		end
		for _, p in car:GetDescendants() do
			if p:IsA("BasePart") then
				p.Parent = car
			end
		end
		for _, c in car:GetChildren() do
			if not c:IsA("BasePart") then
				c:Destroy()
			end
		end
		report.masks, report.colourMaps = Import.dressLamps(car, data)

		local offset: Vector3, spread: number
		if old then
			-- The offset the old car's unchanged pieces had from the new upload's.
			local offsets = {}
			for _, name in data.stable do
				local a = old:FindFirstChild(name) :: BasePart?
				local b = car:FindFirstChild(name) :: BasePart?
				assert(a and b, "stable piece missing: " .. name)
				assert(a.CFrame.Rotation:FuzzyEq(CFrame.identity, 1e-4), "the old car is rotated: " .. name)
				table.insert(offsets, a.Position - b.Position)
			end
			offset = offsets[1]
			spread = 0
			for _, o in offsets do
				spread = math.max(spread, (o - offset).Magnitude)
			end
		else
			local upload
			upload, spread = uploadOffset(car, data, data.stable)
			-- The export's origin at the world's origin, then the box where the runner put it.
			for _, p in car:GetChildren() do
				(p :: BasePart).CFrame -= upload
			end
			local box, size = car:GetBoundingBox()
			local place = opts.place :: { x: number, z: number, bottom: number }
			offset = Vector3.new(
				place.x - box.Position.X,
				place.bottom - (box.Position.Y - size.Y / 2),
				place.z - box.Position.Z
			) - upload
			for _, p in car:GetChildren() do
				(p :: BasePart).CFrame += upload
			end
		end
		assert(spread < 1e-3, `stable pieces disagree on the offset by {spread} studs`)
		for _, p in car:GetChildren() do
			local part = p :: BasePart
			part.CFrame += offset
		end
		if old then
			car.WorldPivot = old.WorldPivot
			for key, value in old:GetAttributes() do
				car:SetAttribute(key, value)
			end
			for _, tag in CollectionService:GetTags(old) do
				CollectionService:AddTag(car, tag)
			end
			old.Name = opts.backupName :: string
			for _, tag in CollectionService:GetTags(old) do
				CollectionService:RemoveTag(old, tag)
			end
			old.Parent = ServerStorage
		else
			local box = car:GetBoundingBox()
			car.WorldPivot = CFrame.new(box.Position)
			car:SetAttribute("Car", data.car)
			CollectionService:AddTag(car, Import.SPAWN_TAG)
		end
		car.Parent = workspace
		opts.source.Name = opts.keepRawAs
		opts.source.Parent = ServerStorage

		local cf, size = car:GetBoundingBox()
		return HttpService:JSONEncode({
			missing = report.missing,
			extra = report.extra,
			withSA = report.sa,
			flat = report.flat,
			fallback = report.fallback,
			emissive = report.emissive,
			masks = report.masks,
			colourMaps = report.colourMaps,
			parts = #car:GetChildren(),
			offset = tostring(offset),
			spread = spread,
			centre = tostring(cf.Position),
			size = tostring(size),
			tags = CollectionService:GetTags(car),
			attrs = car:GetAttributes(),
		})
	end)
end

local function uri(content: Content): string
	return if content.SourceType == Enum.ContentSourceType.None then "" else tostring(content.Uri)
end

-- What a piece looks like and where it sits, for the compare; MeshId is left out (every piece of
-- a new upload has a new one).
local function signature(p: MeshPart): { [string]: any }
	local sa = saOf(p)
	return {
		Material = p.Material.Name,
		Color = p.Color:ToHex(),
		Transparency = p.Transparency,
		Reflectance = p.Reflectance,
		RenderFidelity = p.RenderFidelity.Name,
		Anchored = p.Anchored,
		CanCollide = p.CanCollide,
		Part = p:GetAttribute("Part"),
		Group = p:GetAttribute("Group"),
		SA = if sa
			then table.concat({
				uri(sa.ColorMapContent),
				uri(sa.NormalMapContent),
				uri(sa.RoughnessMapContent),
				uri(sa.MetalnessMapContent),
				uri(sa.EmissiveMaskContent),
				tostring(sa.EmissiveStrength),
				sa.AlphaMode.Name,
			}, "|")
			else "",
	}
end

-- Every piece of `car` against the piece of the same name in `backup`: size (1e-3 stud), place
-- (1e-3 stud, 1e-4 rad) and signature exactly. Read only.
function Import.compare(backup: Model, car: Model): { [string]: any }
	local function pieces(model: Model): { [string]: MeshPart }
		local out = {}
		for _, c in model:GetChildren() do
			if c:IsA("MeshPart") then
				assert(not out[c.Name], `{model.Name}: two pieces named {c.Name}`)
				out[c.Name] = c
			end
		end
		return out
	end
	local old, new = pieces(backup), pieces(car)
	local report = { identical = 0, changed = {}, new = {}, gone = {}, sa = 0 }
	for name, b in new do
		if saOf(b) then
			report.sa += 1
		end
		local a = old[name]
		if not a then
			table.insert(report.new, name)
			continue
		end
		local why = {}
		if (a.Size - b.Size).Magnitude > 1e-3 then
			table.insert(why, `size {a.Size} -> {b.Size}`)
		end
		local rel = a.CFrame:ToObjectSpace(b.CFrame)
		local _, angle = rel:ToAxisAngle()
		if rel.Position.Magnitude > 1e-3 or math.abs(angle) > 1e-4 then
			table.insert(why, string.format("moved %.4f studs, %.5f rad", rel.Position.Magnitude, angle))
		end
		local sa, sb = signature(a), signature(b)
		for key, value in sb do
			if sa[key] ~= value then
				table.insert(why, `{key} {tostring(sa[key])} -> {tostring(value)}`)
			end
		end
		if #why == 0 then
			report.identical += 1
		else
			report.changed[name] = table.concat(why, "; ")
		end
	end
	for name in old do
		if not new[name] then
			table.insert(report.gone, name)
		end
	end
	table.sort(report.new)
	table.sort(report.gone)
	return report
end

-- The names with no BasePart directly in the car.
function Import.missing(car: Model, names: { string }): { string }
	local out = {}
	for _, name in names do
		local p = car:FindFirstChild(name)
		if not (p and p:IsA("BasePart")) then
			table.insert(out, name)
		end
	end
	return out
end

return Import
