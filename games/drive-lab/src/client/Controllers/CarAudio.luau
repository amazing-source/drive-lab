--!strict
--[[
	Plays the car the local player drives: the engine loops mixed by rpm and throttle, the
	limiter, the start-up, gear changes, the shift cut and the exhaust's pops, with their flames
	(Rules/ExhaustPops decides when it pops, Rules/ExhaustFlames which pops throw flame). The readouts come from the attributes Driving sets
	on the car every frame, and only the driver's client has them, so other players' cars stay
	silent for now.

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

local Binding = require(ReplicatedStorage.Shared.Config.Cars.Binding)
local CarAudio = require(ReplicatedStorage.Shared.Config.CarAudio)
local CarAudioEvents = require(ReplicatedStorage.Shared.Rules.CarAudioEvents)
local CarEntry = require(ReplicatedStorage.Shared.Rules.CarEntry)
local CarRig = require(ReplicatedStorage.Shared.Car.CarRig)
local CarState = require(ReplicatedStorage.Shared.Car.CarState)
local Catalog = require(ReplicatedStorage.Shared.Config.Cars.Catalog)
local DriveModes = require(ReplicatedStorage.Shared.Rules.DriveModes)
local EngineSound = require(ReplicatedStorage.Shared.Rules.EngineSound)
local ExhaustFlamesRules = require(ReplicatedStorage.Shared.Rules.ExhaustFlames)
local ExhaustPops = require(ReplicatedStorage.Shared.Rules.ExhaustPops)
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
	pack: CarAudio.Pack,
	-- The car's drive modes, in order (Config/Cars).
	modes: { Types.DrivingMode },
	-- Where its pops throw flames (the binding's outlets), and which of them do.
	binding: Binding.CarModel,
	flames: ExhaustFlamesRules.CarFlames?,
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
	pops: ExhaustPops.State,
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

local function draw(): number
	return random:NextNumber()
end

local function between(range: CarAudio.Region): number
	return range.from + (range.to - range.from) * draw()
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
	pack: CarAudio.Pack,
	region: CarAudio.Region,
	soundGroup: SoundGroup,
	parent: Instance,
	volume: number,
	speed: number
): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = pack.eventsSoundId
	sound.PlaybackRegionsEnabled = true
	sound.PlaybackRegion = NumberRange.new(region.from, region.to)
	sound.Volume = volume
	sound.PlaybackSpeed = speed
	sound.SoundGroup = soundGroup
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = pack.rollOff.from
	sound.RollOffMaxDistance = pack.rollOff.to
	sound.Parent = parent
	sound:Play()
	local function remove()
		sound:Destroy()
	end
	sound.Ended:Once(remove)
	task.delay((region.to - region.from) / speed + ONE_SHOT_GRACE, remove)
	return sound
end

local function pop(current: Session, mode: Types.DrivingMode)
	local pops = current.pack.pops
	local volume = between(pops.volume)
	oneShot(
		current.pack,
		pops.regions[random:NextInteger(1, #pops.regions)],
		current.eventsGroup,
		current.exhaustPoint,
		volume,
		between(pops.speed)
	)
	-- The flame goes with the bang: a louder pop throws more of it.
	local strength = (volume - pops.volume.from) / (pops.volume.to - pops.volume.from)
	local share = ExhaustFlamesRules.share(current.flames, mode, current.pops.kind or "Lift", strength, draw)
	if share then
		ExhaustFlames.burst(current.model, current.binding, share, current.flames)
	end
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
	local settings = current.pack.startup
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
	local pack = current.pack
	local car = readout(current.model)
	if car == nil then
		return
	end
	local mode = DriveModes.current(current.modes, current.model:GetAttribute("DrivingMode"))
	local events = CarAudioEvents.step(current.events, car, dt)
	-- The engine's throttle drops at every fuel cut; while the limiter bounces it counts as open.
	local mix = EngineSound.step(current.engine, car.rpm, if events.limiter then 1 else car.throttle, dt)

	local dip = pack.shiftDip
	local dipGoal = if car.shifting then dip.gain else 1
	current.dip += (dipGoal - current.dip) * EngineSound.blend(
		dt,
		if dipGoal < current.dip then dip.downHalfLife else dip.upHalfLife
	)
	local limiterGoal = if events.limiter then 1 else 0
	current.limiterShare += (limiterGoal - current.limiterShare) * EngineSound.blend(
		dt,
		pack.limiter.halfLife
	)

	local master = pack.engineVolume * current.dip * startupShare(current, car.rpm, dt)
	local onDuck = 1 - (1 - pack.limiter.onDuck) * current.limiterShare
	for index, sound in current.layers do
		local layer = pack.engineLayers[index]
		sound.Volume = mix.volumes[index] * master * (if layer.load == "On" then onDuck else 1)
		sound.PlaybackSpeed = mix.speeds[index]
	end
	local loud = EngineSound.loudness(pack.engineTuning, math.max(car.rpm, 1))
	current.limiter.Volume = pack.limiter.volume * current.limiterShare * master * loud
	current.limiter.PlaybackSpeed = math.max(car.rpm, 1) / pack.limiter.rpm

	local camera = Workspace.CurrentCamera
	local outsideGoal = if camera
			and camera:GetAttribute(CarAudio.VIEW_ATTRIBUTE) == CarAudio.COCKPIT_VIEW
		then 0
		else 1
	current.outside += (outsideGoal - current.outside) * EngineSound.blend(dt, CarAudio.VIEW_HALF_LIFE)
	equalise(current.engineEqualiser, pack.cockpit.engine, pack.outside.engine, current.outside)
	equalise(current.eventsEqualiser, pack.cockpit.events, pack.outside.events, current.outside)
	local far = pack.far
	local distance = if camera then (camera.CFrame.Position - current.chassis.Position).Magnitude else 0
	local farShare = math.clamp((distance - far.fromDistance) / (far.toDistance - far.fromDistance), 0, 1)
	local viewShare = pack.cockpit.far + (pack.outside.far - pack.cockpit.far) * current.outside
	current.far.Volume = far.volume * farShare * viewShare * master * loud

	if events.gear then
		local gear = pack.gear
		local speed = if events.gear == "Up" then gear.upSpeed else gear.downSpeed
		oneShot(pack, gear.region, current.eventsGroup, current.enginePoint, gear.volume, speed)
	end
	if ExhaustPops.step(current.pops, events, car, mode, os.clock(), draw) then
		pop(current, mode)
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

local function start(model: Model, entry: Catalog.Entry, sincePress: number)
	local chassis = model:FindFirstChild("Chassis")
	if chassis == nil or not chassis:IsA("BasePart") then
		return
	end
	local pack = entry.audio
	local engineGroup, engineEqualiser = group("DriveLabCarEngine")
	local eventsGroup, eventsEqualiser = group("DriveLabCarEvents")
	local enginePoint = point(chassis, "DriveLabEngineAudio", pack.enginePosition)
	local exhaustPoint = point(chassis, "DriveLabExhaustAudio", pack.exhaustPosition)
	local layers: { Sound } = table.create(#pack.engineLayers)
	local mixerLayers: { EngineSound.Layer } = table.create(#pack.engineLayers)
	local idle = pack.engineLayers[1]
	for _, layer in pack.engineLayers do
		table.insert(layers, loop(layer.soundId, engineGroup, pack.rollOff, enginePoint))
		table.insert(
			mixerLayers,
			{ rpm = layer.rpm, load = layer.load, volume = layer.volume, crossoverRpm = layer.crossoverRpm }
		)
		if layer.rpm < idle.rpm then
			idle = layer
		end
	end
	-- Level with the idle loop it hands over to.
	local startupVolume = pack.engineVolume
		* idle.volume
		* EngineSound.loudness(pack.engineTuning, idle.rpm)
		* 10 ^ (pack.startup.boostDb / 20)
	local current: Session = {
		model = model,
		pack = pack,
		modes = entry.physics.modeOrder,
		binding = entry.model,
		flames = entry.flames,
		chassis = chassis,
		owned = { engineGroup, eventsGroup, enginePoint, exhaustPoint },
		engine = EngineSound.new(mixerLayers, pack.engineTuning),
		events = CarAudioEvents.new(pack.events),
		layers = layers,
		limiter = loop(pack.limiter.soundId, engineGroup, pack.rollOff, exhaustPoint),
		far = loop(pack.far.soundId, engineGroup, pack.farRollOff, exhaustPoint),
		engineGroup = engineGroup,
		eventsGroup = eventsGroup,
		engineEqualiser = engineEqualiser,
		eventsEqualiser = eventsEqualiser,
		enginePoint = enginePoint,
		exhaustPoint = exhaustPoint,
		startup = oneShot(pack, pack.startup.region, engineGroup, enginePoint, startupVolume, 1),
		startedAt = os.clock(),
		handedOver = nil,
		dip = 1,
		limiterShare = 0,
		outside = 1,
		pops = ExhaustPops.new(pack.popTriggers),
	}
	current.far.PlaybackSpeed = pack.far.speed
	session = current
	-- Joined late in the start-up, the recording picks up where the engine is.
	local startup = current.startup
	if startup and sincePress > 0 then
		startup.TimePosition = pack.startup.region.from + sincePress
	end
end

-- The engine sounds from the moment START is pressed until it is switched off.
local function follow()
	local model = seated
	local entry = model and Catalog.of(model)
	if model == nil or entry == nil then
		return
	end
	local startup = CarEntry.startup(entry, CarState.read(model), Workspace:GetServerTimeNow())
	if session == nil and startup.sincePress then
		start(model, entry, startup.sincePress)
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
