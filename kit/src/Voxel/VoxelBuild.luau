--!strict
--[[
	Turns voxel boxes and ramps into Parts. `origin` is the CFrame of voxel (0, 0, 0) after
	`offset` (in voxels), so a body and its separately spinning wheels share one frame.
	Every part carries a `Swatch` attribute naming its palette key, which lets paint
	finishes recolour a model at runtime without rebuilding it.
]]

export type Swatch = {
	color: Color3,
	material: Enum.Material?,
	reflectance: number?,
	transparency: number?,
}

export type Box = { x1: number, y1: number, z1: number, x2: number, y2: number, z2: number, key: string }

export type Ramp = Box & { dir: "+x" | "-x" }

-- A WedgePart is full height at +Z and zero at -Z; these turns aim the low edge along x.
local RAMP_TURN = {
	["+x"] = CFrame.Angles(0, -math.pi / 2, 0),
	["-x"] = CFrame.Angles(0, math.pi / 2, 0),
}

local function apply(part: BasePart, key: string, swatch: Swatch)
	part.Color = swatch.color
	part.Material = swatch.material or Enum.Material.SmoothPlastic
	part.Reflectance = swatch.reflectance or 0
	part.Transparency = swatch.transparency or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part:SetAttribute("Swatch", key)
end

local function extent(box: Box): (Vector3, Vector3)
	local size = Vector3.new(box.x2 - box.x1 + 1, box.y2 - box.y1 + 1, box.z2 - box.z1 + 1)
	return size, Vector3.new(box.x1, box.y1, box.z1) + size / 2
end

local function swatchFor(palette: { [string]: Swatch }, key: string): Swatch
	local swatch = palette[key]
	assert(swatch, `no palette entry for "{key}"`)
	return swatch
end

export type SwatchSpec = {
	color: string,
	material: string?,
	reflectance: number?,
	transparency: number?,
}

local VoxelBuild = {}

function VoxelBuild.swatches(palette: { [string]: SwatchSpec }): { [string]: Swatch }
	local swatches: { [string]: Swatch } = {}
	for key, spec in palette do
		local material = if spec.material then Enum.Material:FromName(spec.material) else nil
		assert(spec.material == nil or material, `unknown material "{spec.material}"`)
		swatches[key] = {
			color = Color3.fromHex(spec.color),
			material = material,
			reflectance = spec.reflectance,
			transparency = spec.transparency,
		}
	end
	return swatches
end

function VoxelBuild.boxes(
	boxes: { Box },
	palette: { [string]: Swatch },
	voxel: number,
	origin: CFrame,
	offset: Vector3,
	parent: Instance
): number
	for _, box in boxes do
		local size, center = extent(box)
		local part = Instance.new("Part")
		part.Name = box.key
		part.Size = size * voxel
		part.CFrame = origin * CFrame.new((center + offset) * voxel)
		apply(part, box.key, swatchFor(palette, box.key))
		part.Parent = parent
	end
	return #boxes
end

function VoxelBuild.ramps(
	ramps: { Ramp },
	palette: { [string]: Swatch },
	voxel: number,
	origin: CFrame,
	offset: Vector3,
	parent: Instance
): number
	for _, ramp in ramps do
		local size, center = extent(ramp)
		local wedge = Instance.new("WedgePart")
		wedge.Name = ramp.key
		wedge.Size = Vector3.new(size.Z, size.Y, size.X) * voxel
		wedge.CFrame = origin * CFrame.new((center + offset) * voxel) * RAMP_TURN[ramp.dir]
		apply(wedge, ramp.key, swatchFor(palette, ramp.key))
		wedge.Parent = parent
	end
	return #ramps
end

return VoxelBuild
