--!strict
--[[
	Weather and atmosphere on this client: the player's weather key, the preset blend, the road's wetness, the lighting,
	the wet road, the rain, the water on the car, and the rain on the camera (lens drops, a
	contact blur, a light far depth of field) and, in the cockpit, on the windscreen. The only writer of Workspace's RainIntensity and Wetness
	attributes, which the car's grip reads on the driver's client; set here they are local, so a
	reader on the server would see nothing. Reads the camera's DriveLabView and the car's
	SpeedKmh, and never writes the camera or the car.
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CarRig = require(ReplicatedStorage.Shared.Car.CarRig)
local Config = require(ReplicatedStorage.Shared.Config.Atmosphere)
local Controls = require(ReplicatedStorage.Shared.Config.Controls)
local Trove = require(ReplicatedStorage.Packages.Trove)
local WeatherCycle = require(ReplicatedStorage.Shared.Rules.WeatherCycle)

local CarWater = require(script.CarWater)
local DeveloperPanel = require(script.DeveloperPanel)
local Lens = require(script.Lens)
local Optics = require(script.Optics)
local PresetBlend = require(script.PresetBlend)
local Rain = require(script.Rain)
local RainDensity = require(script.RainDensity)
local Weather = require(script.Weather)
local WeatherLabel = require(script.WeatherLabel)
local WetSurfaces = require(script.WetSurfaces)
local Wetness = require(script.Wetness)
local Windshield = require(script.Windshield)

type Car = { model: Model, offset: CFrame, size: Vector3 }

type State = {
	trove: typeof(Trove.new()),
	cameraTrove: typeof(Trove.new()),
	weather: PresetBlend.Weather<Config.Look>,
	target: Config.PresetName,
	applied: boolean,
	override: number?,
	lighting: Weather.Weather,
	surfaces: WetSurfaces.WetSurfaces,
	rain: Rain.Rain,
	water: CarWater.CarWater,
	windshield: Windshield.Windshield,
	optics: Optics.Optics,
	lens: Lens.Lens?,
	weatherLabel: WeatherLabel.WeatherLabel?,
	cars: { [Model]: Car },
	-- The nearest car to the camera this frame, and its speed (km/h, never negative).
	nearest: Car?,
	speedKmh: number,
	camera: Camera?,
	lastPosition: Vector3?,
	-- One frame record and one car box, rewritten each frame rather than rebuilt.
	frame: Rain.Frame,
	carBox: Rain.CarBox,
	published: { RainIntensity: number, Wetness: number },
	panel: DeveloperPanel.Panel?,
	sincePanel: number,
}

local VIEWS: { [string]: Rain.View } =
	{ OnFoot = "OnFoot", Chase = "Chase", Hood = "Hood", Cockpit = "Cockpit" }

local localPlayer = Players.LocalPlayer
local state: State? = nil

local function presetOf(name: Config.PresetName): Config.Preset
	for _, preset in Config.PRESETS do
		if preset.name == name then
			return preset
		end
	end
	error(`unknown preset {name}`)
end

local function presetLook(name: Config.PresetName): Config.Look
	return presetOf(name).look
end

local function savedTier(): Config.Tier
	local settings = UserSettings():GetService("UserGameSettings")
	return RainDensity.tier(settings.SavedQualityLevel.Value, Config.QUALITY_LEVELS, Config.DEFAULT_TIER)
end

local function measure(model: Model): Car
	local box, size = model:GetBoundingBox()
	return { model = model, offset = model:GetPivot():ToObjectSpace(box), size = size }
end

-- What rain lands on but that shelters nothing below it: the cars and the local character.
local function refreshBodies(current: State)
	local bodies: { Instance } = {}
	for model in current.cars do
		table.insert(bodies, model)
	end
	if localPlayer.Character then
		table.insert(bodies, localPlayer.Character)
	end
	current.frame.bodies = bodies
end

local function readView(camera: Camera): Rain.View
	local view = camera:GetAttribute("DriveLabView")
	return if typeof(view) == "string" and VIEWS[view] then VIEWS[view] else "OnFoot"
end

local function bindCamera(current: State, camera: Camera?)
	current.cameraTrove:Clean()
	current.camera = camera
	current.lastPosition = nil
	current.frame.velocity = Vector3.zero
	if camera == nil then
		return
	end
	current.frame.view = readView(camera)
	current.cameraTrove:Connect(camera:GetAttributeChangedSignal("DriveLabView"), function()
		current.frame.view = readView(camera)
		-- The car's box is measured again on entering a car view, in case parts streamed in.
		for model in current.cars do
			current.cars[model] = measure(model)
		end
	end)
end

local function nearestCar(current: State, position: Vector3): Car?
	local best: Car?, distance = nil, math.huge
	for _, car in current.cars do
		local away = (car.model:GetPivot().Position - position).Magnitude
		if away < distance then
			best, distance = car, away
		end
	end
	return best
end

local function publish(current: State, name: "RainIntensity" | "Wetness", value: number)
	if
		math.abs(value - current.published[name]) >= Config.PUBLISH_STEP
		or (value == 0) ~= (current.published[name] == 0)
	then
		Workspace:SetAttribute(name, value)
		current.published[name] = value
	end
end

local function trackMotion(current: State, position: Vector3, dt: number)
	local frame = current.frame
	local last = current.lastPosition
	current.lastPosition = position
	if last == nil or dt <= 0 or (position - last).Magnitude > Config.RAIN.teleportDistance then
		frame.velocity = Vector3.zero
		return
	end
	local share = 1 - 0.5 ^ (dt / Config.RAIN.velocityHalfLife)
	frame.velocity += ((position - last) / dt - frame.velocity) * share
end

local function trackCar(current: State, car: Car?)
	local frame = current.frame
	current.nearest = car
	if car == nil then
		frame.car, current.speedKmh = nil, 0
		return
	end
	local box = current.carBox
	box.frame, box.size = car.model:GetPivot() * car.offset, car.size
	frame.car = box
	local kmh = car.model:GetAttribute("SpeedKmh")
	local valid = typeof(kmh) == "number" and kmh == kmh and math.abs(kmh) < math.huge
	current.speedKmh = if valid then math.abs(kmh :: number) else 0
end

-- The rain on the camera and on the car, after the rain itself has sampled the sky.
local function wetCameraAndCar(
	current: State,
	dt: number,
	intensity: number,
	wetness: number,
	position: Vector3
)
	local frame, rain = current.frame, current.rain
	local landed = 0
	if current.lens then
		landed = Lens.update(
			current.lens,
			dt,
			intensity,
			rain.exposure,
			frame.view,
			current.speedKmh,
			rain.budget.lensDrops
		)
	end
	local car = frame.car
	local distance = if car then (car.frame.Position - position).Magnitude else nil
	Optics.update(
		current.optics,
		dt,
		frame.view,
		intensity,
		landed,
		distance,
		if car then car.size.Z else 0,
		current.speedKmh
	)
	local nearest = current.nearest
	CarWater.update(
		current.water,
		nearest and nearest.model,
		intensity,
		rain.exposure,
		wetness,
		current.speedKmh
	)
	Windshield.update(
		current.windshield,
		dt,
		frame.view == "Cockpit",
		nearest and nearest.model,
		intensity,
		rain.exposure,
		current.speedKmh,
		rain.budget.lensDrops
	)
end

local function showPanel(current: State, look: Config.Look, wetness: number, dt: number)
	local panel = current.panel
	current.sincePanel += dt
	if panel == nil or current.sincePanel < Config.PANEL_REFRESH then
		return
	end
	current.sincePanel = 0
	DeveloperPanel.show(panel, {
		target = current.target,
		progress = PresetBlend.progress(current.weather.blend),
		rainIntensity = look.rainIntensity,
		wetness = current.override or wetness,
		simulated = wetness,
		override = current.override,
		tier = current.rain.tier,
	})
end

local function update(dt: number)
	local current = state
	if current == nil then
		return
	end
	debug.profilebegin("Atmosphere.Update")
	local weather = current.weather
	local blend = PresetBlend.advance(weather.blend, dt)
	local look = PresetBlend.current(blend, Config.CYCLIC)
	if blend ~= weather.blend or not current.applied then
		Weather.apply(current.lighting, look)
		Rain.setLook(current.rain, look)
		current.applied = true
	end
	weather.blend = blend
	weather.wetness = Wetness.step(weather.wetness, look.rainIntensity, dt, Config.WETNESS)
	local wetness = current.override or weather.wetness
	WetSurfaces.apply(current.surfaces, wetness)
	publish(current, "RainIntensity", look.rainIntensity)
	publish(current, "Wetness", wetness)

	local camera = current.camera
	if camera then
		local position = camera.CFrame.Position
		trackMotion(current, position, dt)
		trackCar(current, nearestCar(current, position))
		current.frame.camera = position
		current.frame.intensity = look.rainIntensity
		current.frame.wetness = wetness
		Rain.update(current.rain, dt, current.frame)
		wetCameraAndCar(current, dt, look.rainIntensity, wetness, position)
	end
	showPanel(current, look, weather.wetness, dt)
	debug.profileend()
end

local Atmosphere = {}

-- Heads for a preset over `seconds` (clamped to the configured window), from what is on screen.
function Atmosphere.choose(name: Config.PresetName, seconds: number?)
	local current = state
	if current == nil then
		return
	end
	local duration =
		math.clamp(seconds or Config.TRANSITION_SECONDS, Config.TRANSITION_MIN, Config.TRANSITION_MAX)
	current.weather = PresetBlend.choose(current.weather, presetLook(name), duration, Config.CYCLIC)
	current.target = name
	current.applied = false
end

-- A wetness shown and published instead of the simulated one, for captures; Studio only.
function Atmosphere.setOverride(wetness: number?)
	local current = state
	if current == nil or not RunService:IsStudio() then
		return
	end
	current.override = if wetness then math.clamp(wetness, 0, 1) else nil
end

local function cycleOverride()
	local current = state
	if current == nil then
		return
	end
	local steps = Config.OVERRIDE_STEPS
	local index = if current.override then table.find(steps, current.override) else 0
	Atmosphere.setOverride(steps[(index or 0) + 1])
end

local function mountLens(current: State)
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	if state ~= current then
		return
	end
	current.lens = Lens.new(playerGui)
end

-- The player's weather key: the next preset of the cycle, and its name on screen.
local function stepWeather(current: State)
	local key = Config.WEATHER_KEY
	local name: Config.PresetName = key.cycle[WeatherCycle.nextIndex(key.cycle, current.target)]
	Atmosphere.choose(name, key.seconds)
	local label = current.weatherLabel
	if label then
		WeatherLabel.show(label, presetOf(name).label, key.labelSeconds)
	end
end

local function mountWeatherLabel(current: State)
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	if state ~= current then
		return
	end
	current.weatherLabel = WeatherLabel.new(playerGui)
end

local function mountPanel(current: State)
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	if state ~= current then
		return
	end
	current.panel =
		DeveloperPanel.new(playerGui, { choose = Atmosphere.choose, cycleOverride = cycleOverride })
end

function Atmosphere.start()
	if state then
		return
	end
	local trove = Trove.new()
	local current: State = {
		trove = trove,
		cameraTrove = trove:Extend(),
		weather = PresetBlend.weather(presetLook(Config.START_PRESET), Config.START_WETNESS),
		target = Config.START_PRESET,
		applied = false,
		override = nil,
		lighting = Weather.new(),
		surfaces = WetSurfaces.new(),
		rain = Rain.new(savedTier()),
		water = CarWater.new(),
		windshield = Windshield.new(),
		optics = Optics.new(),
		lens = nil,
		weatherLabel = nil,
		cars = {},
		nearest = nil,
		speedKmh = 0,
		camera = nil,
		lastPosition = nil,
		frame = {
			camera = Vector3.zero,
			velocity = Vector3.zero,
			view = "OnFoot",
			car = nil,
			intensity = 0,
			wetness = 0,
			bodies = {},
		},
		carBox = { frame = CFrame.identity, size = Vector3.zero },
		published = { RainIntensity = -1, Wetness = -1 },
		panel = nil,
		sincePanel = math.huge,
	}
	state = current

	local function track(instance: Instance)
		if instance:IsA("Model") then
			current.cars[instance] = measure(instance)
			refreshBodies(current)
		end
	end
	for _, instance in CollectionService:GetTagged(CarRig.TAG) do
		track(instance)
	end
	trove:Connect(CollectionService:GetInstanceAddedSignal(CarRig.TAG), track)
	trove:Connect(CollectionService:GetInstanceRemovedSignal(CarRig.TAG), function(instance: Instance)
		if instance:IsA("Model") then
			current.cars[instance] = nil
			refreshBodies(current)
		end
	end)
	trove:Connect(localPlayer.CharacterAdded, function()
		refreshBodies(current)
	end)
	refreshBodies(current)

	bindCamera(current, Workspace.CurrentCamera)
	trove:Connect(Workspace:GetPropertyChangedSignal("CurrentCamera"), function()
		bindCamera(current, Workspace.CurrentCamera)
	end)
	trove:Connect(
		UserSettings():GetService("UserGameSettings"):GetPropertyChangedSignal("SavedQualityLevel"),
		function()
			local tier: Config.Tier = savedTier()
			if tier ~= current.rain.tier then
				Rain.setTier(current.rain, tier)
			end
		end
	)
	trove:Add(task.spawn(WetSurfaces.prepare, current.surfaces))
	trove:Add(task.spawn(mountLens, current))
	trove:Add(task.spawn(mountWeatherLabel, current))
	trove:Connect(UserInputService.InputBegan, function(input: InputObject, processed: boolean)
		if processed or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if table.find(Controls.WEATHER, input.KeyCode) then
			stepWeather(current)
		end
	end)
	if RunService:IsStudio() and Config.DEV_PANEL then
		trove:Add(task.spawn(mountPanel, current))
	end
	-- After the driving camera (Camera + 2), so the rain follows this frame's view.
	trove:BindToRenderStep("DriveLabAtmosphere", Enum.RenderPriority.Camera.Value + 3, update)
end

-- Puts back everything this client changed: Lighting, terrain colours, the material override,
-- the depth of field, the attributes it published; removes the rain, the car's water, the lens
-- drops and the panel.
function Atmosphere.stop()
	local current = state
	if current == nil then
		return
	end
	state = nil
	current.trove:Destroy()
	if current.panel then
		DeveloperPanel.destroy(current.panel)
	end
	if current.lens then
		Lens.destroy(current.lens)
	end
	if current.weatherLabel then
		WeatherLabel.destroy(current.weatherLabel)
	end
	Optics.destroy(current.optics)
	CarWater.destroy(current.water)
	Windshield.destroy(current.windshield)
	Rain.destroy(current.rain)
	WetSurfaces.destroy(current.surfaces)
	Weather.destroy(current.lighting)
	Workspace:SetAttribute("RainIntensity", nil)
	Workspace:SetAttribute("Wetness", nil)
end

return Atmosphere
