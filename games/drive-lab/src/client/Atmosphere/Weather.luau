--!strict
--[[
	Puts a look on screen: Lighting, its Atmosphere, bloom, sun rays, a colour grade and the
	terrain's clouds. In rain the Atmosphere's density follows the rain's real visibility
	(Rules/RainHaze) rather than the preset's. The client's writes are local. An Atmosphere, bloom, sun rays or clouds the
	place already has are driven rather than doubled (two Atmospheres fight); every property
	written is put back on destroy, and what this module created it removes.
]]
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config.Atmosphere)
local Log = require(ReplicatedStorage.Kit.Log)
local RainHaze = require(ReplicatedStorage.Shared.Rules.RainHaze)

type Saved = { instance: Instance, property: string, value: unknown }

export type Weather = {
	atmosphere: Atmosphere,
	clouds: Clouds,
	grade: ColorCorrectionEffect,
	bloom: BloomEffect,
	sunRays: SunRaysEffect,
	saved: { Saved },
	created: { Instance },
}

local LIGHTING_PROPERTIES = {
	"Brightness",
	"ClockTime",
	"ExposureCompensation",
	"Ambient",
	"OutdoorAmbient",
	"EnvironmentDiffuseScale",
	"EnvironmentSpecularScale",
	"GlobalShadows",
}

local log = Log.scope("Atmosphere")

local function colour(value: Config.Rgb): Color3
	return Color3.fromRGB(value.r, value.g, value.b)
end

local function remember(saved: { Saved }, instance: Instance, properties: { string })
	for _, property in properties do
		-- Read by name so the same list restores them; each name is a property of this class.
		table.insert(saved, { instance = instance, property = property, value = (instance :: any)[property] })
	end
end

-- The place's own instance of a class under `parent`, or a new one this module owns.
local function adopt(parent: Instance, className: string, name: string, created: { Instance }): Instance
	local existing = parent:FindFirstChildOfClass(className)
	if existing then
		return existing
	end
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = parent
	table.insert(created, instance)
	return instance
end

-- LightingStyle and PrioritizeLightingQuality are set in the place; the docs disagree on
-- whether a script may write them, so the client only reads them, and only warns.
local function checkStyle()
	local ok, style, prioritised = pcall(function(): (Enum.LightingStyle, boolean)
		return Lighting.LightingStyle, Lighting.PrioritizeLightingQuality
	end)
	if not ok then
		log.warn("cannot read LightingStyle here; set Realistic and PrioritizeLightingQuality in the place")
	elseif style ~= Enum.LightingStyle.Realistic or not prioritised then
		log.warn(
			`LightingStyle is {style}, PrioritizeLightingQuality {prioritised}: the look expects Realistic and true`
		)
	end
end

local Weather = {}

function Weather.new(): Weather
	checkStyle()
	local saved: { Saved } = {}
	local created: { Instance } = {}
	remember(saved, Lighting, LIGHTING_PROPERTIES)
	local atmosphere = adopt(Lighting, "Atmosphere", "Atmosphere", created) :: Atmosphere
	remember(saved, atmosphere, { "Density", "Offset", "Haze", "Glare", "Color", "Decay" })
	local bloom = adopt(Lighting, "BloomEffect", "Bloom", created) :: BloomEffect
	remember(saved, bloom, { "Intensity", "Size", "Threshold" })
	local sunRays = adopt(Lighting, "SunRaysEffect", "SunRays", created) :: SunRaysEffect
	remember(saved, sunRays, { "Intensity", "Spread" })
	local clouds = adopt(Workspace.Terrain, "Clouds", "Clouds", created) :: Clouds
	remember(saved, clouds, { "Cover", "Density", "Color" })
	-- A grade of its own: colour corrections stack, so one the place has for other reasons is
	-- left alone.
	local base = Config.LIGHTING
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "DriveLabWeatherGrade"
	grade.Brightness = base.colorCorrectionBrightness
	grade.Parent = Lighting
	table.insert(created, grade)

	Lighting.EnvironmentDiffuseScale = base.environmentDiffuseScale
	Lighting.EnvironmentSpecularScale = base.environmentSpecularScale
	Lighting.GlobalShadows = base.globalShadows
	bloom.Threshold = base.bloomThreshold
	bloom.Size = base.bloomSize
	sunRays.Spread = base.sunRaysSpread
	return {
		atmosphere = atmosphere,
		clouds = clouds,
		grade = grade,
		bloom = bloom,
		sunRays = sunRays,
		saved = saved,
		created = created,
	}
end

function Weather.apply(weather: Weather, look: Config.Look)
	Lighting.ClockTime = look.clockTime
	Lighting.Brightness = look.brightness
	Lighting.ExposureCompensation = look.exposureCompensation
	Lighting.Ambient = colour(look.ambient)
	Lighting.OutdoorAmbient = colour(look.outdoorAmbient)
	local atmosphere = weather.atmosphere
	atmosphere.Density = RainHaze.density(look.atmosphereDensity, look.rainIntensity, Config.HAZE)
	atmosphere.Offset = look.atmosphereOffset
	atmosphere.Haze = look.atmosphereHaze
	atmosphere.Glare = look.atmosphereGlare
	atmosphere.Color = colour(look.atmosphereColor)
	atmosphere.Decay = colour(look.atmosphereDecay)
	weather.clouds.Cover = look.cloudCover
	weather.clouds.Density = look.cloudDensity
	weather.clouds.Color = colour(look.cloudColor)
	weather.grade.Contrast = look.contrast
	weather.grade.Saturation = look.saturation
	weather.grade.TintColor = colour(look.tint)
	weather.bloom.Intensity = look.bloomIntensity
	weather.sunRays.Intensity = look.sunRaysIntensity
end

function Weather.destroy(weather: Weather)
	for index = #weather.saved, 1, -1 do
		local entry = weather.saved[index]
		-- Written back by name, as remember read it.
		local instance: any = entry.instance
		instance[entry.property] = entry.value
	end
	for _, instance in weather.created do
		instance:Destroy()
	end
	table.clear(weather.saved)
	table.clear(weather.created)
end

return Weather
