--!nonstrict
-- Edit-mode capture harness for the car lights (issue #41). Rigs a copy of CarImport beside it,
-- applies the game's own looks, poses lamps, aims the camera; teardown restores every property it
-- wrote and destroys everything it made.
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Probe = {}
local saved = {}
local created = {}

local function remember(instance, properties)
	for _, property in properties do
		table.insert(saved, { instance = instance, property = property, value = instance[property] })
	end
end

local function rgb(value)
	return Color3.fromRGB(value.r, value.g, value.b)
end

-- Remembers the camera and the lighting it will change; once per session.
function Probe.scene()
	if Probe.grade then
		return
	end
	local camera = workspace.CurrentCamera
	remember(camera, { "CFrame", "FieldOfView", "Focus" })
	remember(Lighting, {
		"Brightness",
		"ClockTime",
		"ExposureCompensation",
		"Ambient",
		"OutdoorAmbient",
		"EnvironmentDiffuseScale",
		"EnvironmentSpecularScale",
		"GlobalShadows",
	})
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	remember(bloom, { "Intensity", "Size", "Threshold" })
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	remember(atmosphere, { "Density", "Offset", "Haze", "Glare", "Color", "Decay" })
	local sunRays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	remember(sunRays, { "Intensity", "Spread" })
	local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	if dof then
		remember(dof, { "Enabled" })
		dof.Enabled = false
	end
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "LightsProbeGrade"
	grade.Parent = Lighting
	table.insert(created, grade)
	Probe.grade = grade
	Probe.bloom = bloom
	Probe.atmosphere = atmosphere
	Probe.sunRays = sunRays
end

function Probe.setup(offset: Vector3)
	Probe.scene()
	local source = workspace:FindFirstChild("CarImport")
	local car = source:Clone()
	car.Name = "LightsProbeCar"
	for _, tag in CollectionService:GetTags(car) do
		CollectionService:RemoveTag(car, tag)
	end
	car:PivotTo(source:GetPivot() + offset)
	car.Parent = workspace
	table.insert(created, car)
	local Catalog = require(ReplicatedStorage.Shared.Config.Cars.Catalog)
	local CarRig = require(ReplicatedStorage.Shared.Car.CarRig)
	local entry = Catalog.SVJ
	CarRig.build(car, entry.physics, entry.model)
	for _, tag in CollectionService:GetTags(car) do
		CollectionService:RemoveTag(car, tag)
	end
	for _, part in car:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
	Probe.car = car
	Probe.chassis = car:FindFirstChild("Chassis")
	return car
end

function Probe.look(name: string)
	local Atmosphere = require(ReplicatedStorage.Shared.Config.Atmosphere)
	local look
	for _, preset in Atmosphere.PRESETS do
		if preset.name == name then
			look = preset.look
		end
	end
	assert(look, "no preset " .. name)
	local base = Atmosphere.LIGHTING
	Lighting.EnvironmentDiffuseScale = base.environmentDiffuseScale
	Lighting.EnvironmentSpecularScale = base.environmentSpecularScale
	Lighting.GlobalShadows = base.globalShadows
	Probe.bloom.Threshold = base.bloomThreshold
	Probe.bloom.Size = base.bloomSize
	Probe.sunRays.Spread = base.sunRaysSpread
	Lighting.ClockTime = look.clockTime
	Lighting.Brightness = look.brightness
	Lighting.ExposureCompensation = look.exposureCompensation
	Lighting.Ambient = rgb(look.ambient)
	Lighting.OutdoorAmbient = rgb(look.outdoorAmbient)
	local atmosphere = Probe.atmosphere
	atmosphere.Density = look.atmosphereDensity
	atmosphere.Offset = look.atmosphereOffset
	atmosphere.Haze = look.atmosphereHaze
	atmosphere.Glare = look.atmosphereGlare
	atmosphere.Color = rgb(look.atmosphereColor)
	atmosphere.Decay = rgb(look.atmosphereDecay)
	Probe.grade.Contrast = look.contrast
	Probe.grade.Saturation = look.saturation
	Probe.grade.TintColor = rgb(look.tint)
	Probe.bloom.Intensity = look.bloomIntensity
	Probe.sunRays.Intensity = look.sunRaysIntensity
end

-- Camera from the chassis frame: right, up, forward offsets in studs, looking at a point given
-- the same way.
function Probe.view(eye: Vector3, target: Vector3, fov: number?)
	local frame = Probe.chassis.CFrame
	local function at(v)
		return frame.Position + frame.RightVector * v.X + frame.UpVector * v.Y + frame.LookVector * v.Z
	end
	local camera = workspace.CurrentCamera
	camera.FieldOfView = fov or 50
	camera.CFrame = CFrame.lookAt(at(eye), at(target))
	camera.Focus = CFrame.new(at(target))
end

-- The lights as main's Controllers/CarLights draws them (the "before"), rebuilt from the
-- place's own Config.CarLights so the numbers are the shipped ones.
function Probe.oldLights()
	local Config = require(ReplicatedStorage.Shared.Config.CarLights)
	local model = Probe.car
	local function attach(part, name, offset)
		local a = Instance.new("Attachment")
		a.Name = name
		a.CFrame = offset
		a.Parent = part
		return a
	end
	local function pointLight(parent, range, brightness, color)
		local l = Instance.new("PointLight")
		l.Range = range
		l.Brightness = brightness
		l.Color = color
		l.Shadows = false
		l.Enabled = false
		l.Parent = parent
		return l
	end
	local function cluster(part, front)
		local size = part.Size
		local lamp = if front then CFrame.new(0, 0, -size.Z / 2 + Config.HEADLIGHT.inset) else CFrame.new()
		local point = attach(part, "LightPoint", lamp)
		local beam
		if front then
			local aim = attach(part, "HeadlightBeam", lamp * CFrame.Angles(Config.HEADLIGHT.pitch, 0, 0))
			local spot = Instance.new("SpotLight")
			spot.Face = Enum.NormalId.Front
			spot.Range = Config.HEADLIGHT.range
			spot.Angle = Config.HEADLIGHT.angle
			spot.Brightness = Config.HEADLIGHT.brightness
			spot.Color = Config.HEADLIGHT.color
			spot.Enabled = false
			spot.Parent = aim
			beam = spot
		end
		return {
			look = part:FindFirstChildOfClass("SurfaceAppearance"),
			glow = if front then nil else pointLight(point, Config.TAIL.range, Config.TAIL.brightness, Config.TAIL.color),
			blink = pointLight(point, Config.INDICATOR.range, Config.INDICATOR.brightness, Config.INDICATOR.color),
			beam = beam,
		}
	end
	local function find(name)
		return model:FindFirstChild(name, true)
	end
	local names = Config.PARTS
	local rearLeft, rearRight = find(names.rearLeft), find(names.rearRight)
	local fl, fr = cluster(find(names.frontLeft), true), cluster(find(names.frontRight), true)
	local rl, rr = cluster(rearLeft, false), cluster(rearRight, false)
	local middle = (rearLeft.Position + rearRight.Position) / 2 - rearLeft.CFrame.UpVector * Config.REVERSE.drop
	local reverseAt = attach(rearLeft, "ReverseLight", CFrame.new(rearLeft.CFrame:PointToObjectSpace(middle)))
	local reverse = Instance.new("SpotLight")
	reverse.Face = Enum.NormalId.Back
	reverse.Range = Config.REVERSE.range
	reverse.Angle = Config.REVERSE.angle
	reverse.Brightness = Config.REVERSE.brightness
	reverse.Color = Config.REVERSE.color
	reverse.Enabled = false
	reverse.Parent = reverseAt
	Probe.old = { left = { fl, rl }, right = { fr, rr }, front = { fl, fr }, reverse = reverse, config = Config }
end

-- lit: { headlights, brake, reverse, left, right } as Rules.CarLights.decide returns it.
function Probe.oldShow(lit)
	local car = Probe.old
	local Config = car.config
	for _, front in car.front do
		front.beam.Enabled = lit.headlights
		front.beam.Shadows = true
	end
	for _, side in { car.left, car.right } do
		local on = if side == car.left then lit.left else lit.right
		for index, lamp in side do
			local isFront = index == 1
			local strength = if isFront
				then (if lit.headlights then Config.FRONT_HEADLIGHTS else Config.FRONT_DRL)
				else (if lit.brake then Config.REAR_BRAKE else Config.REAR_POSITION)
			local tint = if on then Config.INDICATOR_TINT elseif isFront then Color3.new(1, 1, 1) else Config.REAR_TINT
			if lamp.look.EmissiveStrength ~= strength then
				lamp.look.EmissiveStrength = strength
			end
			if lamp.look.EmissiveTint ~= tint then
				lamp.look.EmissiveTint = tint
			end
			lamp.blink.Enabled = on
			if lamp.glow then
				lamp.glow.Enabled = lit.headlights or lit.brake
				lamp.glow.Range = if lit.brake then Config.TAIL.brakeRange else Config.TAIL.range
				lamp.glow.Brightness = if lit.brake then Config.TAIL.brakeBrightness else Config.TAIL.brightness
			end
		end
	end
	car.reverse.Enabled = lit.reverse
end

-- The branch's lamps (Effects/CarLamps, synced into the place) on the probe car.
function Probe.newLights()
	local client = game:GetService("StarterPlayer").StarterPlayerScripts.Client
	Probe.CarLamps = require(client.Effects.CarLamps)
	Probe.Rules = require(ReplicatedStorage.Shared.Rules.CarLights)
	Probe.Config = require(ReplicatedStorage.Shared.Config.CarLights)
	Probe.carLamps = Probe.CarLamps.build(Probe.car)
	return Probe.carLamps ~= nil
end

function Probe.newShow(overrides)
	local state = {
		running = true,
		mode = "Auto",
		night = false,
		rain = 0,
		brake = 0,
		gear = 1,
		indicator = nil,
		indicating = 0,
		cabin = false,
	}
	for key, value in overrides do
		state[key] = value
	end
	local daylight = Probe.Rules.daylight(Lighting.Brightness, Probe.Config.NIGHT_BRIGHTNESS, Probe.Config.DAY_BRIGHTNESS)
	local lit = Probe.Rules.decide(state, Probe.Config.TUNING)
	Probe.CarLamps.apply(Probe.carLamps, lit, daylight, true)
	return lit, daylight
end

-- Per-frame cost of one car's lights, `seconds` long, one call per render step: "old" is main's
-- decide + show, "new" the branch's controller body for the driven car, "empty" the slot alone.
function Probe.time(kind: string, seconds: number)
	local RunService = game:GetService("RunService")
	local samples = {}
	local started = os.clock()
	local name = "LightsProbeTiming"
	local done = false
	local CarState, CarEntry, StreetLamps, StreetLights
	if kind == "new" then
		CarState = require(ReplicatedStorage.Shared.Car.CarState)
		CarEntry = require(ReplicatedStorage.Shared.Rules.CarEntry)
	end
	StreetLamps = require(ReplicatedStorage.Shared.Rules.StreetLamps)
	StreetLights = require(ReplicatedStorage.Shared.Config.StreetLights)
	local oldRules = if kind == "old" then require(ReplicatedStorage.Shared.Rules.CarLights) else nil
	local model = Probe.car
	RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 3, function()
		local t = os.clock()
		local elapsed = t - started
		local brake = if elapsed % 1 < 0.5 then 1 else 0
		if kind == "old" then
			local night = StreetLamps.isNight(Lighting.ClockTime, StreetLights.DUSK, StreetLights.DAWN)
			local lit = oldRules.decide({ mode = "Auto", night = night, rain = 0, brake = brake, gear = 1, indicator = "Left", time = t }, Probe.old.config.TUNING)
			Probe.oldShow(lit)
			model:SetAttribute("HeadlightsOn", lit.headlights)
			model:SetAttribute("IndicatorLeft", lit.left)
			model:SetAttribute("IndicatorRight", lit.right)
		elseif kind == "new" then
			local night = StreetLamps.isNight(Lighting.ClockTime, StreetLights.DUSK, StreetLights.DAWN)
			local daylight = Probe.Rules.daylight(Lighting.Brightness, Probe.Config.NIGHT_BRIGHTNESS, Probe.Config.DAY_BRIGHTNESS)
			local _running = CarEntry.startup(CarState.read(model), workspace:GetServerTimeNow()).sincePress ~= nil
			local lit = Probe.Rules.decide({
				running = true, mode = "Auto", night = night, rain = 0, brake = brake, gear = 1,
				indicator = "Left", indicating = elapsed, cabin = true,
			}, Probe.Config.TUNING)
			Probe.CarLamps.apply(Probe.carLamps, lit, daylight, true)
			model:SetAttribute("HeadlightsOn", lit.headlights)
			model:SetAttribute("IndicatorLeft", lit.left)
			model:SetAttribute("IndicatorRight", lit.right)
		end
		table.insert(samples, (os.clock() - t) * 1000)
		if elapsed > seconds then
			done = true
		end
	end)
	while not done do
		task.wait(0.1)
	end
	RunService:UnbindFromRenderStep(name)
	table.sort(samples)
	local function q(f)
		return samples[math.max(1, math.ceil(#samples * f))]
	end
	return string.format("%s: %d frames, p50 %.4f ms, p95 %.4f ms, max %.4f ms", kind, #samples, q(0.5), q(0.95), samples[#samples])
end

-- Night lamps (#44): `count` lamps from the place's asset in a row along a dark road patch beside
-- the probe area, lit as Controllers/StreetLights lights them.
function Probe.lamps(origin: Vector3, count: number, spacing: number)
	local ReplicatedStorageService = game:GetService("ReplicatedStorage")
	local StreetLights = require(ReplicatedStorageService.Shared.Config.StreetLights)
	local asset = ReplicatedStorageService.DriveLabAssets.StreetLamp
	local road = Instance.new("Part")
	road.Name = "LightsProbeRoad"
	road.Anchored = true
	road.Material = Enum.Material.Asphalt
	road.Color = Color3.fromRGB(46, 46, 48)
	road.Size = Vector3.new(40, 0.2, spacing * (count + 2))
	road.CFrame = CFrame.new(origin + Vector3.new(0, 0.1, spacing * (count - 1) / 2))
	road.Parent = workspace
	table.insert(created, road)
	Probe.scene()
	Probe.streetLamps = {}
	for index = 1, count do
		local lamp = asset:Clone()
		for _, tag in CollectionService:GetTags(lamp) do
			CollectionService:RemoveTag(lamp, tag)
		end
		lamp:PivotTo(CFrame.new(origin + Vector3.new(-12, 0.2, spacing * (index - 1))))
		lamp.Parent = workspace
		table.insert(created, lamp)
		local bulb = lamp:FindFirstChild("Bulb")
		bulb.Material = Enum.Material.Neon
		bulb.Color = StreetLights.BULB_ON
		for _, light in lamp:GetDescendants() do
			if light:IsA("Light") then
				light.Enabled = true
			end
		end
		table.insert(Probe.streetLamps, lamp)
	end
end

function Probe.lampShadows(on: boolean, colliderShadow: boolean)
	for _, lamp in Probe.streetLamps do
		for _, light in lamp:GetDescendants() do
			if light:IsA("SpotLight") then
				light.Shadows = on
			end
		end
		lamp.Collider.CastShadow = colliderShadow
	end
end

-- How Studio's content provider fetches each id, and what an EditableImage reads back.
function Probe.textures(ids)
	local ContentProvider = game:GetService("ContentProvider")
	local AssetService = game:GetService("AssetService")
	local lines = {}
	ContentProvider:PreloadAsync(ids, function(id, status)
		table.insert(lines, id .. " preload " .. status.Name)
	end)
	for _, id in ids do
		local ok, image = pcall(function()
			return AssetService:CreateEditableImageAsync(Content.fromUri(id))
		end)
		if ok and image then
			local size = image.Size
			local pixels = image:ReadPixelsBuffer(Vector2.zero, size)
			local sum, peak, count = 0, 0, size.X * size.Y
			for i = 0, count - 1 do
				local r = buffer.readu8(pixels, i * 4)
				sum += r
				peak = math.max(peak, r)
			end
			table.insert(lines, string.format("%s editable %dx%d mean red %.1f peak %d", id, size.X, size.Y, sum / count, peak))
			image:Destroy()
		else
			table.insert(lines, id .. " editable failed: " .. tostring(image))
		end
	end
	return table.concat(lines, "\n")
end

-- The game's own glints (Effects/LampGlints as synced in the place), aimed at the probe lamps from
-- the current camera, for one rendered frame.
function Probe.glints(wetness: number, rain: number)
	local client = game:GetService("StarterPlayer").StarterPlayerScripts.Client
	local LampGlints = require(client.Effects.LampGlints)
	if Probe.glintPool == nil then
		Probe.glintPool = LampGlints.new()
		table.insert(created, Probe.glintPool.folder)
	end
	local lamps = {}
	for _, lamp in Probe.streetLamps do
		local pivot = lamp:GetPivot()
		table.insert(lamps, { base = pivot.Position, right = pivot.ZVector, side = 1 })
	end
	LampGlints.assign(Probe.glintPool, lamps)
	LampGlints.render(Probe.glintPool, workspace.CurrentCamera, wetness, rain)
	local beams = {}
	for _, beam in Probe.glintPool.folder:GetDescendants() do
		if beam:IsA("Beam") and beam.Enabled then
			table.insert(beams, string.format("%s w=%.2f t=%.2f", beam.Texture, beam.Width0, beam.Transparency.Keypoints[1].Value))
		end
	end
	return table.concat(beams, "; ")
end

-- One entry of shots.luau: its look, view and state, drawn the old way or the new; returns its
-- name, or nil when the shot has no "before" (the cabin light did not exist).
function Probe.shot(index: number, which: string)
	if Probe.shots == nil then
		local m = Instance.new("ModuleScript")
		m.Source = game:GetService("HttpService"):GetAsync("http://127.0.0.1:8782/shots.luau?v=" .. os.clock())
		Probe.shots = require(m)
	end
	local shot = Probe.shots.shots[index]
	if shot == nil then
		return nil
	end
	if which == "old" and shot[4] == nil then
		return "skip"
	end
	Probe.look(shot[2])
	local view = Probe.shots.views[shot[3]]
	Probe.view(view.eye, view.target, view.fov)
	if which == "old" then
		Probe.oldShow(shot[4])
	else
		Probe.newShow(shot[5])
	end
	return shot[1]
end

function Probe.teardown()
	for index = #saved, 1, -1 do
		local entry = saved[index]
		entry.instance[entry.property] = entry.value
	end
	for _, instance in created do
		instance:Destroy()
	end
	table.clear(saved)
	table.clear(created)
	Probe.grade = nil
	return "restored"
end

return Probe
