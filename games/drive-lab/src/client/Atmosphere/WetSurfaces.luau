--!strict
--[[
	The road's wet look, on terrain. Two layers:
	- each terrain material listed in the config darkens continuously toward its soaked factor
	  (Terrain:SetMaterialColor tints the material and multiplies a MaterialVariant's colour map:
	  seen in Studio, 2026-10-27);
	- the asphalt steps through authored MaterialVariant states, rougher to glossier and then
	  pooled water, chosen by wetness with hysteresis through MaterialService's base-material
	  override.
	A MaterialVariant's maps can only be set by a plugin, so the states must be authored into the
	place's MaterialService; without them the road keeps the built-in asphalt and only darkens.
	A state whose textures have not loaded draws as flat colour, so the states are preloaded and
	the override is left alone until that has run. Even then, on this Studio build every switch
	of the override drew the road flat for 1.5 to 4 s while terrain rebuilt the material, so the
	config keeps the states few.
]]
local ContentProvider = game:GetService("ContentProvider")
local MaterialService = game:GetService("MaterialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config.Atmosphere)
local Log = require(ReplicatedStorage.Kit.Log)
local Wetness = require(script.Parent.Wetness)

export type WetSurfaces = {
	original: { [Enum.Material]: Color3 },
	soaked: { [Enum.Material]: number },
	material: Enum.Material,
	originalOverride: string,
	-- Authored state names in stage order; empty when the place has none.
	variants: { string },
	starts: { number },
	ready: boolean,
	destroyed: boolean,
	stage: number,
	shownStage: number,
	-- The wetness the colours were last set for; negative forces the next recolour.
	shownWetness: number,
}

local log = Log.scope("Atmosphere")

local function material(name: string): Enum.Material
	local found = Enum.Material:FromName(name)
	assert(found, `Config.Atmosphere names an unknown material: {name}`)
	return found
end

local function authored(road: Config.WetRoad, base: Enum.Material): { string }
	local names = {}
	for _, stage in road.stages do
		if MaterialService:GetMaterialVariant(base, stage.variant) == nil then
			return {}
		end
		table.insert(names, stage.variant)
	end
	return names
end

local function dryColour(surfaces: WetSurfaces, terrainMaterial: Enum.Material): Color3
	if surfaces.ready and terrainMaterial == surfaces.material then
		local tint = Config.WET_ROAD.variantColor
		return Color3.fromRGB(tint.r, tint.g, tint.b)
	end
	return surfaces.original[terrainMaterial]
end

local WetSurfaces = {}

function WetSurfaces.new(): WetSurfaces
	local road = Config.WET_ROAD
	local terrain = Workspace.Terrain
	local base = material(road.material)
	local original, soaked, starts = {}, {}, {}
	for name, factor in road.soaked do
		local terrainMaterial = material(name)
		original[terrainMaterial] = terrain:GetMaterialColor(terrainMaterial)
		soaked[terrainMaterial] = factor
	end
	for _, stage in road.stages do
		table.insert(starts, stage.from)
	end
	local variants = authored(road, base)
	if #variants == 0 then
		log.info("wet road states are not authored in MaterialService: the road only darkens")
	end
	return {
		original = original,
		soaked = soaked,
		material = base,
		originalOverride = MaterialService:GetBaseMaterialOverride(base),
		variants = variants,
		starts = starts,
		ready = false,
		destroyed = false,
		stage = 1,
		shownStage = 0,
		shownWetness = -1,
	}
end

-- Yields while every state's textures are fetched, then lets apply switch states. Call it on
-- its own thread. The fetch statuses are reported, not obeyed: in Studio edit mode PreloadAsync
-- reported Failure for these maps while the viewport drew them (2026-10-27), so a status alone
-- is no proof that a state cannot show.
function WetSurfaces.prepare(surfaces: WetSurfaces)
	if #surfaces.variants == 0 then
		return
	end
	local content = {}
	for _, stage in Config.WET_ROAD.stages do
		table.insert(content, stage.color)
		table.insert(content, stage.normal)
		table.insert(content, stage.roughness)
	end
	local unconfirmed = 0
	ContentProvider:PreloadAsync(content, function(_, status: Enum.AssetFetchStatus)
		if status ~= Enum.AssetFetchStatus.Success then
			unconfirmed += 1
		end
	end)
	if surfaces.destroyed then
		return
	end
	if unconfirmed > 0 then
		log.info(
			`wet road: {unconfirmed} of {#content} textures not confirmed loaded; a first switch may flash`
		)
	end
	surfaces.ready = true
	surfaces.shownWetness = -1
end

function WetSurfaces.apply(surfaces: WetSurfaces, wetness: number)
	local road = Config.WET_ROAD
	if surfaces.ready then
		surfaces.stage = Wetness.stage(surfaces.stage, wetness, surfaces.starts, road.hysteresis)
		if surfaces.stage ~= surfaces.shownStage then
			MaterialService:SetBaseMaterialOverride(surfaces.material, surfaces.variants[surfaces.stage])
			surfaces.shownStage = surfaces.stage
		end
	end
	if surfaces.shownWetness >= 0 and math.abs(wetness - surfaces.shownWetness) < road.colourStep then
		return
	end
	local terrain = Workspace.Terrain
	for terrainMaterial, factor in surfaces.soaked do
		local scale = Wetness.darkening(wetness, factor, road.darkenExponent)
		terrain:SetMaterialColor(
			terrainMaterial,
			dryColour(surfaces, terrainMaterial):Lerp(Color3.new(), 1 - scale)
		)
	end
	surfaces.shownWetness = wetness
end

function WetSurfaces.destroy(surfaces: WetSurfaces)
	surfaces.destroyed = true
	local terrain = Workspace.Terrain
	for terrainMaterial, colour in surfaces.original do
		terrain:SetMaterialColor(terrainMaterial, colour)
	end
	if surfaces.shownStage ~= 0 then
		MaterialService:SetBaseMaterialOverride(surfaces.material, surfaces.originalOverride)
	end
end

return WetSurfaces
