--!strict
--[[
	Plays the car the local player drives: the engine loops mixed by rpm and throttle, the
	limiter, the start-up, gear changes, the shift cut and the pops after a lift. The readouts
	come from the attributes Driving sets on the car every frame, and only the driver's client
	has them, so other players' cars stay silent for now.

	Every sound hangs on an attachment on the chassis, so it is positional. The camera's
	DriveLabView attribute picks the shaping: the engine loops are cabin recordings, dry in the
	cockpit and equalised toward the exhaust outside, where the far loop joins with distance.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CarAudio = require(ReplicatedStorage.Shared.Config.CarAudio)
local CarAudioEvents = require(ReplicatedStorage.Shared.Rules.CarAudioEvents)
local CarEntry = require(ReplicatedStorage.Shared.Rules.CarEntry)
local CarRig = require(ReplicatedStorage.Shared.Car.CarRig)
local CarState = require(ReplicatedStorage.Shared.Car.CarState)
local EngineSound = require(ReplicatedStorage.Shared.Rules.EngineSound)
local Types = require(ReplicatedStorage.Shared.Config.Cars.Types)
local Units = require(ReplicatedStorage.Shared.Units)

local ExhaustFlames = require(script.Parent.Parent.Effects.ExhaustFlames)

local STOP_FADE_SECONDS = 0.15
-- A start-up whose sound has not loaded by then is skipped rather than left holding the engine.
local STARTUP_LOAD_TIMEOUT = 3
-- A one-shot is removed when it ends, or this long after its region would have ended.
local ONE_SHOT_GRACE = 5

type Session = {
	model: Model,
	chassis: BasePart,
	-- Everything the session made: destroying them stops every sound.
	owned: { Instance },
	engine: EngineSound.State,
	events: CarAudioEvents.State,
	layers: { Sound },
	limiter: Sound,
	far: Sound,
	engineGroup: SoundGroup,
	eventsGroup: SoundGroup,
	engineEqualiser: EqualizerSoundEffect,
	eventsEqualiser: EqualizerSoundEffect,
	enginePoint: Attachment,
	exhaustPoint: Attachment,
	startup: Sound?,
	startedAt: number,
	-- Engine share during the start-up, 0 to 1, once the start-up hands over early.
	handedOver: number?,
	dip: number,
	limiterShare: number,
	outside: number,
	popsUntil: number,
	nextPop: number,
}

local localPlayer = Players.LocalPlayer
local random = Random.new()
local session: Session? = nil
-- The car the local player sits in; its engine sounds only once started (Rules/CarEntry).
local seated: Model? = nil

local function readNumber(model: Model, name: string, default: number): number
	local value = model:GetAttribute(name)
	return if typeof(value) == "number" and value == value then value else default
end

local function readout(model: Model): CarAudioEvents.Readout?
	if typeof(model:GetAttribute("Rpm")) ~= "number" then
		return nil
	end
	return {
		rpm = readNumber(model, "Rpm", 0),
		throttle = readNumber(model, "Throttle", 0),
		gear = readNumber(model, "Gear", 0),
		shifting = model:GetAttribute("Shifting") == true,
		limiter = model:GetAttribute("Limiter") == true,
		tcActive = model:GetAttribute("TcActive") == true,
	}
end

local function drivingMode(model: Model): Types.DrivingMode
	local mode = model:GetAttribute("DrivingMode")
	if mode == "Sport" then
		return "Sport"
	elseif mode == "Corsa" then
		return "Corsa"
	end
	return "Strada"
end

local function forMode(values: CarAudio.ByMode, mode: Types.DrivingMode): number
	return if mode == "Corsa" then values.Corsa elseif mode == "Sport" then values.Sport else values.Strada
end

local function between(range: CarAudio.Region): number
	return range.from + (range.to - range.from) * random:NextNumber()
end

local function point(chassis: BasePart, name: string, position: { forward: number, up: number }): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Position =
		Vector3.new(0, Units.metresToStuds(position.up), -Units.metresToStuds(position.forward))
	attachment.Parent = chassis
	return attachment
end

local function group(name: string): (SoundGroup, EqualizerSoundEffect)
	local soundGroup = Instance.new("SoundGroup")
	soundGroup.Name = name
	local equaliser = Instance.new("EqualizerSoundEffect")
	equaliser.Parent = soundGroup
	soundGroup.Parent = SoundService
	return soundGroup, equaliser
end

local function loop(
	soundId: string,
	soundGroup: SoundGroup,
	rollOff: CarAudio.Region,
	parent: Instance
): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Looped = true
	sound.Volume = 0
	sound.SoundGroup = soundGroup
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = rollOff.from
	sound.RollOffMaxDistance = rollOff.to
	sound.Parent = parent
	sound:Play()
	return sound
end

-- A one-shot cut from the packed events file; it removes itself once played.
local function oneShot(
	region: CarAudio.Region,
	soundGroup: SoundGroup,
	parent: Instance,
	volume: number,
	speed: number
): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = CarAudio.EVENTS_SOUND_ID
	sound.PlaybackRegionsEnabled = true
	sound.PlaybackRegion = NumberRange.new(region.from, region.to)
	sound.Volume = volume
	sound.PlaybackSpeed = speed
	sound.SoundGroup = soundGroup
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = CarAudio.ROLL_OFF.from
	sound.RollOffMaxDistance = CarAudio.ROLL_OFF.to
	sound.Parent = parent
	sound:Play()
	local function remove()
		sound:Destroy()
	end
	sound.Ended:Once(remove)
	task.delay((region.to - region.from) / speed + ONE_SHOT_GRACE, remove)
	return sound
end

local function pop(current: Session)
	local pops = CarAudio.POPS
	local volume = between(pops.volume)
	oneShot(
		pops.regions[random:NextInteger(1, #pops.regions)],
		current.eventsGroup,
		current.exhaustPoint,
		volume,
		between(pops.speed)
	)
	-- The flame goes with the bang: a louder pop throws more of it.
	ExhaustFlames.burst(current.model, (volume - pops.volume.from) / (pops.volume.to - pops.volume.from))
end

local function equalise(
	equaliser: EqualizerSoundEffect,
	inside: CarAudio.Equaliser,
	outside: CarAudio.Equaliser,
	share: number
)
	equaliser.LowGain = inside.low + (outside.low - inside.low) * share
	equaliser.MidGain = inside.mid + (outside.mid - inside.mid) * share
	equaliser.HighGain = inside.high + (outside.high - inside.high) * share
end

-- The engine's share while the start-up plays: none, then an equal-power hand-over as the
-- start-up's own fade-out begins, or a quick one if the driver revs it first or it never loads.
local function startupShare(current: Session, rpm: number, dt: number): number
	local startup = current.startup
	if startup == nil then
		return 1
	end
	local settings = CarAudio.STARTUP
	local waited = os.clock() - current.startedAt
	if
		current.handedOver == nil
		and (rpm > settings.abortRpm or (not startup.IsLoaded and waited > STARTUP_LOAD_TIMEOUT))
	then
		current.handedOver = 0
	end
	local handedOver = current.handedOver
	if handedOver then
		local step = EngineSound.blend(dt, settings.abortHalfLife)
		startup.Volume *= 1 - step
		local share = handedOver + (1 - handedOver) * step
		current.handedOver = share
		if share > 0.99 then
			startup:Destroy()
			current.startup = nil
		end
		return share
	end
	if not startup.IsLoaded then
		return 0
	end
	-- Playing is set by Play() itself, so unlike IsPlaying it is not false while the sound loads.
	if startup.Parent == nil or not startup.Playing then
		current.startup = nil
		return 1
	end
	local length = settings.region.to - settings.region.from
	local elapsed = startup.TimePosition - settings.region.from
	local progress = math.clamp((elapsed - settings.handOver) / (length - settings.handOver), 0, 1)
	return math.sin(progress * math.pi / 2)
end

local function update(current: Session, dt: number)
	local car = readout(current.model)
	if car == nil then
		return
	end
	local mode: Types.DrivingMode = drivingMode(current.model)
	local events = CarAudioEvents.step(current.events, car, dt)
	-- The engine's throttle drops at every fuel cut; while the limiter bounces it counts as open.
	local mix = EngineSound.step(current.engine, car.rpm, if events.limiter then 1 else car.throttle, dt)

	local dip = CarAudio.SHIFT_DIP
	local dipGoal = if car.shifting then dip.gain else 1
	current.dip += (dipGoal - current.dip) * EngineSound.blend(
		dt,
		if dipGoal < current.dip then dip.downHalfLife else dip.upHalfLife
	)
	local limiterGoal = if events.limiter then 1 else 0
	current.limiterShare += (limiterGoal - current.limiterShare) * EngineSound.blend(
		dt,
		CarAudio.LIMITER.halfLife
	)

	local master = CarAudio.ENGINE_VOLUME * current.dip * startupShare(current, car.rpm, dt)
	local onDuck = 1 - (1 - CarAudio.LIMITER.onDuck) * current.limiterShare
	for index, sound in current.layers do
		local layer = CarAudio.ENGINE_LAYERS[index]
		sound.Volume = mix.volumes[index] * master * (if layer.load == "On" then onDuck else 1)
		sound.PlaybackSpeed = mix.speeds[index]
	end
	local loud = EngineSound.loudness(CarAudio.ENGINE_TUNING, math.max(car.rpm, 1))
	current.limiter.Volume = CarAudio.LIMITER.volume * current.limiterShare * master * loud
	current.limiter.PlaybackSpeed = math.max(car.rpm, 1) / CarAudio.LIMITER.rpm

	local camera = Workspace.CurrentCamera
	local outsideGoal = if camera
			and camera:GetAttribute(CarAudio.VIEW_ATTRIBUTE) == CarAudio.COCKPIT_VIEW
		then 0
		else 1
	current.outside += (outsideGoal - current.outside) * EngineSound.blend(dt, CarAudio.VIEW_HALF_LIFE)
	equalise(current.engineEqualiser, CarAudio.COCKPIT.engine, CarAudio.OUTSIDE.engine, current.outside)
	equalise(current.eventsEqualiser, CarAudio.COCKPIT.events, CarAudio.OUTSIDE.events, current.outside)
	local far = CarAudio.FAR
	local distance = if camera then (camera.CFrame.Position - current.chassis.Position).Magnitude else 0
	local farShare = math.clamp((distance - far.fromDistance) / (far.toDistance - far.fromDistance), 0, 1)
	local viewShare = CarAudio.COCKPIT.far + (CarAudio.OUTSIDE.far - CarAudio.COCKPIT.far) * current.outside
	current.far.Volume = far.volume * farShare * viewShare * master * loud

	local pops = CarAudio.POPS
	local now = os.clock()
	if events.gear then
		local gear = CarAudio.GEAR
		local speed = if events.gear == "Up" then gear.upSpeed else gear.downSpeed
		oneShot(gear.region, current.eventsGroup, current.enginePoint, gear.volume, speed)
	end
	if
		events.cut
		and car.rpm >= CarAudio.EVENTS.liftMinRpm
		and random:NextNumber() < forMode(pops.upshiftChance, mode)
	then
		pop(current)
	end
	if events.lift and random:NextNumber() < forMode(pops.chance, mode) then
		current.popsUntil = now + between(pops.trainSeconds)
		current.nextPop = now
	end
	if car.throttle > CarAudio.EVENTS.liftTo or car.rpm < pops.minRpm then
		current.popsUntil = 0
	elseif now < current.popsUntil and now >= current.nextPop then
		pop(current)
		current.nextPop = now + between(pops.gapSeconds)
	end
end

local function stop()
	local current = session
	if current == nil then
		return
	end
	session = nil
	local playing = table.clone(current.layers)
	table.insert(playing, current.limiter)
	table.insert(playing, current.far)
	if current.startup then
		table.insert(playing, current.startup)
	end
	for _, sound in playing do
		TweenService:Create(sound, TweenInfo.new(STOP_FADE_SECONDS), { Volume = 0 }):Play()
	end
	task.delay(STOP_FADE_SECONDS + 0.05, function()
		for _, instance in current.owned do
			instance:Destroy()
		end
	end)
end

local function start(model: Model, sincePress: number)
	local chassis = model:FindFirstChild("Chassis")
	if chassis == nil or not chassis:IsA("BasePart") then
		return
	end
	local engineGroup, engineEqualiser = group("DriveLabCarEngine")
	local eventsGroup, eventsEqualiser = group("DriveLabCarEvents")
	local enginePoint = point(chassis, "DriveLabEngineAudio", CarAudio.ENGINE_POSITION)
	local exhaustPoint = point(chassis, "DriveLabExhaustAudio", CarAudio.EXHAUST_POSITION)
	local layers: { Sound } = table.create(#CarAudio.ENGINE_LAYERS)
	local mixerLayers: { EngineSound.Layer } = table.create(#CarAudio.ENGINE_LAYERS)
	local idle = CarAudio.ENGINE_LAYERS[1]
	for _, layer in CarAudio.ENGINE_LAYERS do
		table.insert(layers, loop(layer.soundId, engineGroup, CarAudio.ROLL_OFF, enginePoint))
		table.insert(
			mixerLayers,
			{ rpm = layer.rpm, load = layer.load, volume = layer.volume, crossoverRpm = layer.crossoverRpm }
		)
		if layer.rpm < idle.rpm then
			idle = layer
		end
	end
	-- Level with the idle loop it hands over to.
	local startupVolume = CarAudio.ENGINE_VOLUME
		* idle.volume
		* EngineSound.loudness(CarAudio.ENGINE_TUNING, idle.rpm)
		* 10 ^ (CarAudio.STARTUP.boostDb / 20)
	local current: Session = {
		model = model,
		chassis = chassis,
		owned = { engineGroup, eventsGroup, enginePoint, exhaustPoint },
		engine = EngineSound.new(mixerLayers, CarAudio.ENGINE_TUNING),
		events = CarAudioEvents.new(CarAudio.EVENTS),
		layers = layers,
		limiter = loop(CarAudio.LIMITER.soundId, engineGroup, CarAudio.ROLL_OFF, exhaustPoint),
		far = loop(CarAudio.FAR.soundId, engineGroup, CarAudio.FAR_ROLL_OFF, exhaustPoint),
		engineGroup = engineGroup,
		eventsGroup = eventsGroup,
		engineEqualiser = engineEqualiser,
		eventsEqualiser = eventsEqualiser,
		enginePoint = enginePoint,
		exhaustPoint = exhaustPoint,
		startup = oneShot(CarAudio.STARTUP.region, engineGroup, enginePoint, startupVolume, 1),
		startedAt = os.clock(),
		handedOver = nil,
		dip = 1,
		limiterShare = 0,
		outside = 1,
		popsUntil = 0,
		nextPop = 0,
	}
	current.far.PlaybackSpeed = CarAudio.FAR.speed
	session = current
	-- Joined late in the start-up, the recording picks up where the engine is.
	local startup = current.startup
	if startup and sincePress > 0 then
		startup.TimePosition = CarAudio.STARTUP.region.from + sincePress
	end
end

-- The engine sounds from the moment START is pressed until it is switched off.
local function follow()
	local model = seated
	if model == nil then
		return
	end
	local startup = CarEntry.startup(CarState.read(model), Workspace:GetServerTimeNow())
	if session == nil and startup.sincePress then
		start(model, startup.sincePress)
	elseif session and startup.stage == "Off" then
		stop()
	end
end

local function onSeat(humanoid: Humanoid)
	stop()
	seated = nil
	local seat = humanoid.SeatPart
	local model = seat and seat.Parent
	if seat and seat:IsA("Seat") and model and model:IsA("Model") and model:HasTag(CarRig.TAG) then
		seated = model
	end
end

local function onCharacter(character: Model)
	stop()
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	if character.Parent == nil then
		return
	end
	humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
		onSeat(humanoid)
	end)
end

local Controller = {}

function Controller.start()
	RunService.Heartbeat:Connect(function(dt: number)
		follow()
		if session then
			update(session, dt)
		end
	end)
	if localPlayer.Character then
		task.spawn(onCharacter, localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(onCharacter)
end

return Controller
