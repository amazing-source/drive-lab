--!strict
--[[
	The analog cluster of the car the local player drives, on a car whose display is one (its
	entry's gauges; Controllers/Cluster and Binnacle draw the other kinds). Every frame each needle
	follows its reading on the rig's hinge weld, and the faces and needles glow while the cluster
	is lit (from the key reaching ON); the readout and the message centre are redrawn a few dozen
	times a second. The fuel and the temperatures are simulated per car on this client
	(Rules/EngineGauges), kept for the session and cooling while nobody drives the car.
]]
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Binding = require(ReplicatedStorage.Shared.Config.Cars.Binding)
local CarEntry = require(ReplicatedStorage.Shared.Rules.CarEntry)
local CarEntryConfig = require(ReplicatedStorage.Shared.Config.CarEntry)
local CarLightsConfig = require(ReplicatedStorage.Shared.Config.CarLights)
local CarLightsRules = require(ReplicatedStorage.Shared.Rules.CarLights)
local CarRig = require(ReplicatedStorage.Shared.Car.CarRig)
local CarState = require(ReplicatedStorage.Shared.Car.CarState)
local Catalog = require(ReplicatedStorage.Shared.Config.Cars.Catalog)
local Engine = require(ReplicatedStorage.Shared.Vehicle.Engine)
local EngineGauges = require(ReplicatedStorage.Shared.Rules.EngineGauges)
local Gauges = require(ReplicatedStorage.Shared.Config.Gauges)
local MessageCentre = require(ReplicatedStorage.Shared.Rules.MessageCentre)
local Rules = require(ReplicatedStorage.Shared.Rules.Gauges)
local SevenSegment = require(ReplicatedStorage.Shared.Rules.SevenSegment)

local GaugeScreens = require(script.Parent.Parent.Ui.GaugeScreens)

type Drive = {
	model: Model,
	entry: Catalog.Entry,
	cluster: Gauges.Cluster,
	engine: Engine.Engine,
	needles: { Rules.Needle },
	-- Each dial's weld and its bound needle, once its part has streamed in.
	welds: { [number]: CarRig.Hinged },
	bound: { [number]: Binding.Hinge },
	-- Each backlit part's SurfaceAppearance found so far, with its glow.
	glows: { [SurfaceAppearance]: CarLightsConfig.Glow },
	complete: boolean,
	sinceScan: number,
	readout: GaugeScreens.Readout?,
	message: GaugeScreens.Message?,
	movedOff: boolean,
	sinceText: number,
}

-- A car's simulated engine on this client, and when it was last simulated (os.clock).
type Simulated = { state: EngineGauges.State, at: number }

local localPlayer = Players.LocalPlayer
local drive: Drive? = nil
local simulated: { [Model]: Simulated } = setmetatable({}, { __mode = "k" }) :: any

local function colour(value: { r: number, g: number, b: number }): Color3
	return Color3.fromRGB(value.r, value.g, value.b)
end

local function number(model: Model, name: string): number
	local value = model:GetAttribute(name)
	return if typeof(value) == "number" and value == value then value else 0
end

local function drivenModel(): Model?
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	local model = seat and seat.Parent
	if model and model:IsA("Model") and CollectionService:HasTag(model, CarRig.TAG) then
		return model
	end
	return nil
end

-- Finds the needles' welds, the backlit parts and the screens that have streamed in since the last
-- look; `complete` once nothing is missing.
local function scan(current: Drive)
	local model, cluster = current.model, current.cluster
	local rig = CarRig.find(model, current.entry.model)
	local bound = current.entry.model.needles or {}
	local complete = rig ~= nil
	for index, dial in cluster.dials do
		local hinged = rig and rig.needles[dial.needle]
		if hinged and current.welds[index] == nil then
			current.welds[index] = hinged
			current.bound[index] = bound[dial.needle]
		end
		complete = complete and current.welds[index] ~= nil
	end
	for _, light in cluster.backlight do
		for _, name in light.parts do
			local part = model:FindFirstChild(name, true)
			local look = part and part:FindFirstChildOfClass("SurfaceAppearance")
			if look and current.glows[look] == nil then
				look.EmissiveTint = colour(light.glow.tint)
				look.EmissiveStrength = 0
				current.glows[look] = light.glow
			end
			complete = complete and look ~= nil
		end
	end
	local readout, message = cluster.readout, cluster.message
	if readout and current.readout == nil then
		local part = model:FindFirstChild(CarRig.displayName(readout.display))
		current.readout = if part and part:IsA("BasePart") then GaugeScreens.readout(part, readout) else nil
	end
	if message and current.message == nil then
		local part = model:FindFirstChild(CarRig.displayName(message.display))
		current.message = if part and part:IsA("BasePart") then GaugeScreens.message(part, message) else nil
	end
	complete = complete
		and (readout == nil or current.readout ~= nil)
		and (message == nil or current.message ~= nil)
	current.complete = complete
	current.sinceScan = 0
end

local function build(model: Model, entry: Catalog.Entry, cluster: Gauges.Cluster): Drive
	local needles = table.create(#cluster.dials)
	for index in cluster.dials do
		needles[index] = Rules.newNeedle()
	end
	local current: Drive = {
		model = model,
		entry = entry,
		cluster = cluster,
		engine = Engine.prepare(entry.physics.engine),
		needles = needles,
		welds = {},
		bound = {},
		glows = {},
		complete = false,
		sinceScan = 0,
		readout = nil,
		message = nil,
		movedOff = false,
		sinceText = math.huge,
	}
	scan(current)
	return current
end

-- Leaves the needles at rest and the cluster dark for the next driver's client to take over.
local function release(current: Drive)
	for _, hinged in current.welds do
		hinged.weld.C0 = hinged.rest
	end
	for look in current.glows do
		look.EmissiveStrength = 0
	end
	if current.readout then
		current.readout.gui:Destroy()
	end
	if current.message then
		current.message.gui:Destroy()
	end
end

-- This car's simulated engine, cooled for the time nobody simulated it: the time since it was
-- last simulated, less the `covered` seconds this frame's step simulates.
local function engineOf(model: Model, cluster: Gauges.Cluster, covered: number): EngineGauges.State
	local now = os.clock()
	local record = simulated[model]
	if record == nil then
		local odometer = if cluster.message then cluster.message.odometerMiles else 0
		record = { state = EngineGauges.new(cluster.engine, odometer), at = now }
		simulated[model] = record
	end
	EngineGauges.coolOff(record.state, cluster.engine, now - record.at - covered)
	record.at = now
	return record.state
end

local function reading(
	dial: Gauges.Dial,
	speedKmh: number,
	rpm: number,
	state: EngineGauges.State,
	engine: Gauges.Engine
): number
	local kind = dial.reading
	if kind == "speed" then
		return speedKmh
	elseif kind == "rpm" then
		return rpm
	elseif kind == "fuel" then
		return EngineGauges.fuelShare(state, engine)
	elseif kind == "coolant" then
		return state.coolant
	end
	return EngineGauges.oilPressure(engine, rpm, state.oil)
end

local function showText(current: Drive, lit: boolean, state: EngineGauges.State, startKey: string)
	local cluster = current.cluster
	local readout, message = current.readout, current.message
	if readout and cluster.readout then
		local spec = cluster.readout
		local text = SevenSegment.number(number(current.model, "LongitudinalG"), spec.digits, spec.decimals)
		GaugeScreens.showReadout(readout, if lit then text else nil)
	end
	if message and cluster.message then
		local lines =
			MessageCentre.lines(cluster.message, startKey, current.movedOff, state.trip, state.odometer)
		GaugeScreens.showMessage(message, if lit then lines else nil)
	end
end

local function refresh(current: Drive, dt: number)
	local model, entry, cluster = current.model, current.entry, current.cluster
	local carState, now = CarState.read(model), Workspace:GetServerTimeNow()
	local sinceLit = Rules.sinceLit(entry.startup, cluster.lightsWith, carState, now)
	local lit = sinceLit ~= nil
	local running = CarEntry.startup(entry, carState, now).stage == "Running"
	local rpm = CarEntry.shownRpm(entry, carState, now, number(model, "Rpm"))
	local speedKmh = number(model, "SpeedKmh")
	local speed = rpm * Engine.RAD_PER_RPM
	local power = if running
		then math.clamp(number(model, "Throttle"), 0, 1) * Engine.fullTorque(current.engine, speed) * speed
		else 0
	local state = engineOf(model, cluster, dt)
	EngineGauges.step(state, cluster.engine, { running = running, power = power, speedKmh = speedKmh }, dt)
	if carState.engine == "Off" then
		current.movedOff = false
	elseif lit then
		current.movedOff = cluster.message ~= nil
			and MessageCentre.movedOff(cluster.message, current.movedOff, speedKmh)
	end

	local sweep = if sinceLit then Rules.sweepShare(cluster.sweep, sinceLit) else nil
	for index, dial in cluster.dials do
		local needle = current.needles[index]
		local target = if lit
			then sweep or Rules.share(dial, reading(dial, speedKmh, rpm, state, cluster.engine))
			else 0
		if not lit then
			needle.met = false
		end
		Rules.follow(needle, dial, target, dt)
		local hinged = current.welds[index]
		if hinged then
			hinged.weld.C0 = hinged.rest * CFrame.Angles(Rules.turn(current.bound[index], needle.share), 0, 0)
		end
	end

	local daylight = CarLightsRules.daylight(
		Lighting.Brightness,
		CarLightsConfig.NIGHT_BRIGHTNESS,
		CarLightsConfig.DAY_BRIGHTNESS
	)
	local level = if lit then 1 else 0
	for look, glow in current.glows do
		local strength = CarLightsRules.strength(level, glow.night, glow.day, daylight)
		if math.abs(look.EmissiveStrength - strength) > 1e-3 then
			look.EmissiveStrength = strength
		end
	end

	current.sinceText += dt
	if current.sinceText >= Gauges.TEXT_INTERVAL then
		current.sinceText = 0
		local startKey = CarEntry.parseKey(entry, model:GetAttribute(CarEntryConfig.ATTRIBUTES.START_KEY))
		showText(current, lit, state, startKey)
	end
end

local function update(dt: number)
	local model = drivenModel()
	local current = drive
	if current and current.model ~= model then
		release(current)
		drive, current = nil, nil
	end
	if model == nil then
		return
	end
	if current == nil then
		local entry = Catalog.of(model)
		local cluster = entry and entry.gauges
		if entry == nil or cluster == nil then
			return
		end
		current = build(model, entry, cluster)
		drive = current
		-- TRIP A counts this drive.
		engineOf(model, cluster, 0).trip = 0
	end
	local active = current :: Drive
	active.sinceScan += dt
	if not active.complete and active.sinceScan >= Gauges.RESCAN_INTERVAL then
		scan(active)
	end
	refresh(active, dt)
end

local Controller = {}

function Controller.start()
	RunService.Heartbeat:Connect(update)
end

return Controller
