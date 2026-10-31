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
local ContentProvider = game:GetService("ContentProvider")
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
local StartupHandOver = require(ReplicatedStorage.Shared.Rules.StartupHandOver)
local Types = require(ReplicatedStorage.Shared.Config.Cars.Types)
local Units = require(ReplicatedStorage.Shared.Units)

local ExhaustFlames = require(script.Parent.Parent.Effects.ExhaustFlames)

local STOP_FADE_SECONDS = 0.15
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
	-- The idle loop's volume at idle: each start-up is levelled against it.
	idleLevel: number,
	startup: Sound?,
	-- The playing start-up's volume at a full share.
	startupVolume: number,
	handOver: StartupHandOver.State?,
	-- os.clock() at the START press.
	pressedAt: number,
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
	parent: Instance,
	region: CarAudio.Region?
): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Looped = true
	if region then
		sound.PlaybackRegionsEnabled = true
		sound.PlaybackRegion = NumberRange.new(region.from, region.to)
		sound.LoopRegion = NumberRange.new(region.from, region.to)
	end
	sound.Volume = 0
	sound.SoundGroup = soundGroup
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = rollOff.from
	sound.RollOffMaxDistance = rollOff.to
	sound.Parent = parent
	sound:Play()
	return sound
end

-- A one-shot cut from an uploaded sound (most from the packed events file); it removes itself
-- once played.
local function oneShot(
	pack: CarAudio.Pack,
	soundId: string,
	region: CarAudio.Region,
	soundGroup: SoundGroup,
	parent: Instance,
	volume: number,
	speed: number
): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
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
		CarAudio.popsSoundId(current.pack),
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

-- The events file's start-up, from where the engine is `sincePress` seconds after the press.
local function playRegion(current: Session, sincePress: number)
	local pack = current.pack
	local settings = pack.startup
	local volume = current.idleLevel * 10 ^ (settings.boostDb / 20)
	local startup = oneShot(
		pack,
		pack.eventsSoundId,
		settings.region,
		current.engineGroup,
		current.enginePoint,
		volume,
		1
	)
	if sincePress > 0 then
		startup.TimePosition = settings.region.from + sincePress
	end
	current.startup = startup
	current.startupVolume = volume
	current.handOver = StartupHandOver.new(settings, nil, current.pressedAt, os.clock())
end

-- The car's own start-up sound. Should it fail to load (it can be taken down), the events file's
-- start-up plays instead, from where the engine is by then; never both.
local function playOwn(current: Session, own: CarAudio.StartupSound)
	local volume = current.idleLevel * own.volume
	local region = { from = own.from, to = own.to }
	local startup = oneShot(current.pack, own.id, region, current.engineGroup, current.enginePoint, volume, 1)
	local handOver = StartupHandOver.new(current.pack.startup, own, current.pressedAt, os.clock())
	current.startup = startup
	current.startupVolume = volume
	current.handOver = handOver
	task.spawn(function()
		ContentProvider:PreloadAsync({ startup }, function(_: string, status: Enum.AssetFetchStatus)
			local failed = status == Enum.AssetFetchStatus.Failure or status == Enum.AssetFetchStatus.TimedOut
			if
				not failed
				or session ~= current
				or current.startup ~= startup
				or handOver.handedOver ~= nil
			then
				return
			end
			startup:Destroy()
			playRegion(current, os.clock() - current.pressedAt)
		end)
	end)
end

-- The engine's share while the start-up plays (Rules/StartupHandOver).
local function startupShare(current: Session, rpm: number, dt: number): number
	local startup, handOver = current.startup, current.handOver
	if startup == nil or handOver == nil then
		return 1
	end
	local share, gain, seek = StartupHandOver.step(handOver, {
		playing = startup.Parent ~= nil and startup.Playing,
		loaded = startup.IsLoaded,
		position = startup.TimePosition,
	}, rpm, os.clock(), dt)
	if seek then
		startup.TimePosition = seek
	end
	if gain then
		startup.Volume = current.startupVolume * gain
	end
	if handOver.done then
		startup:Destroy()
		current.startup = nil
	end
	return share
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
	current.model:SetAttribute(CarAudio.ENGINE_LEVEL_ATTRIBUTE, pack.engineVolume * EngineSound.level(mix))

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
		oneShot(
			pack,
			pack.eventsSoundId,
			gear.region,
			current.eventsGroup,
			current.enginePoint,
			gear.volume,
			speed
		)
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
	for _, layer in pack.engineLayers do
		table.insert(layers, loop(layer.soundId, engineGroup, pack.rollOff, enginePoint, layer.region))
		table.insert(
			mixerLayers,
			{ rpm = layer.rpm, load = layer.load, volume = layer.volume, crossoverRpm = layer.crossoverRpm }
		)
	end
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
		limiter = loop(pack.limiter.soundId, engineGroup, pack.rollOff, exhaustPoint, pack.limiter.region),
		far = loop(pack.far.soundId, engineGroup, pack.farRollOff, exhaustPoint, pack.far.region),
		engineGroup = engineGroup,
		eventsGroup = eventsGroup,
		engineEqualiser = engineEqualiser,
		eventsEqualiser = eventsEqualiser,
		enginePoint = enginePoint,
		exhaustPoint = exhaustPoint,
		idleLevel = CarAudio.idleLevel(pack),
		startup = nil,
		startupVolume = 0,
		handOver = nil,
		pressedAt = os.clock() - sincePress,
		dip = 1,
		limiterShare = 0,
		outside = 1,
		pops = ExhaustPops.new(pack.popTriggers),
	}
	current.far.PlaybackSpeed = pack.far.speed
	session = current
	local own = pack.startup.sound
	if own then
		playOwn(current, own)
	else
		playRegion(current, sincePress)
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
