--!strict
--[[
	The cockpit controls' sounds (Config/CarAudio.ControlSounds, Rules/ControlSounds) of every car
	whose pack has them, played at its driver's seat through their own SoundGroup: a click the
	instant the driver's hand works a control (Rig/ControlPresses); the start-up's key, guard,
	switch and START as its server-timed timeline passes them, so a late joiner never hears an old
	start; the pit radio opening, hissing while held and closing; the wiper motor and the washer
	pump. The switches are local to the driver's client, so only the driver hears the radio, the
	wiper and the washer. Levelled against the car's idle loop; writes nothing but its own sounds.
]]
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local CarAudio = require(ReplicatedStorage.Shared.Config.CarAudio)
local CarRig = require(ReplicatedStorage.Shared.Car.CarRig)
local CarState = require(ReplicatedStorage.Shared.Car.CarState)
local Catalog = require(ReplicatedStorage.Shared.Config.Cars.Catalog)
local ControlPresses = require(script.Parent.Parent.Rig.ControlPresses)
local Rules = require(ReplicatedStorage.Shared.Rules.ControlSounds)

type Car = {
	entry: Catalog.Entry,
	sounds: CarAudio.ControlSounds,
	seat: BasePart,
	idleLevel: number,
	watch: Rules.Watch,
	talking: boolean,
	-- The loops, made the first time each plays.
	loops: { [string]: Sound? },
}

-- Seconds between looks for cars not set up yet (their seat not streamed in).
local SCAN_SECONDS = 1

local cars: { [Model]: Car } = {}
local group: SoundGroup? = nil
local sinceScan = math.huge

local function newSound(car: Car, sound: CarAudio.ControlSound, looped: boolean): Sound
	local instance = Instance.new("Sound")
	instance.Name = "DriveLabControlSound"
	instance.SoundId = sound.soundId
	instance.Volume = Rules.volume(car.idleLevel, sound)
	instance.Looped = looped
	local region = sound.region
	if region then
		instance.PlaybackRegionsEnabled = true
		instance.PlaybackRegion = NumberRange.new(region.from, region.to)
		instance.LoopRegion = NumberRange.new(region.from, region.to)
	end
	local rollOff = CarAudio.CONTROLS_ROLL_OFF
	instance.RollOffMode = Enum.RollOffMode.InverseTapered
	instance.RollOffMinDistance = rollOff.from
	instance.RollOffMaxDistance = rollOff.to
	instance.SoundGroup = group
	instance.Parent = car.seat
	return instance
end

local function playOnce(car: Car, sound: CarAudio.ControlSound?)
	if sound == nil then
		return
	end
	local instance = newSound(car, sound, false)
	instance.Ended:Once(function()
		instance:Destroy()
	end)
	task.delay(CarAudio.CONTROLS_ONE_SHOT_SECONDS, function()
		if instance.Parent then
			instance:Destroy()
		end
	end)
	instance:Play()
end

-- Plays the loop `name` at `rate` (its playback speed), or stops it when `rate` is nil.
local function loop(car: Car, name: string, sound: CarAudio.ControlSound?, rate: number?)
	local existing = car.loops[name]
	if sound == nil then
		return
	end
	local instance: Sound
	if existing then
		instance = existing
	elseif rate == nil then
		return
	else
		instance = newSound(car, sound, true)
		car.loops[name] = instance
	end
	if rate == nil then
		if instance.IsPlaying then
			instance:Stop()
		end
		return
	end
	instance.PlaybackSpeed = rate
	if not instance.IsPlaying then
		instance:Play()
	end
end

local function track(model: Instance)
	if not model:IsA("Model") or cars[model] then
		return
	end
	local entry = Catalog.of(model)
	local sounds = entry and entry.audio.controls
	local rig = entry and sounds and CarRig.find(model, entry.model)
	if entry == nil or sounds == nil or rig == nil then
		return
	end
	cars[model] = {
		entry = entry,
		sounds = sounds,
		seat = rig.seat,
		idleLevel = CarAudio.idleLevel(entry.audio),
		watch = Rules.newWatch(),
		talking = false,
		loops = {},
	}
end

local function number(model: Model, name: string): number
	local value = model:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

local function updateCar(model: Model, car: Car, now: number)
	local sounds = car.sounds
	local state = CarState.read(model)
	local running = state.engine ~= "Off"
	for _, name in Rules.watchStartup(car.watch, car.entry.startup, running, state.engineAt, now) do
		playOnce(car, sounds.press[name])
	end
	local radio = sounds.radio
	local talking = model:GetAttribute("RadioTalking") == true
	local edge = Rules.radioEdge(car.talking, talking)
	car.talking = talking
	if radio and edge then
		playOnce(car, if edge == "Press" then radio.press else radio.release)
	end
	loop(car, "Radio", radio and radio.hiss, if talking then 1 else nil)
	local motor = sounds.wiperMotor
	local rate = motor
		and Rules.wiperRate(motor.rates, number(model, "WiperSpeed"), number(model, "WiperSweep"))
	loop(car, "WiperMotor", motor, rate)
	loop(car, "WasherPump", sounds.washerPump, if model:GetAttribute("Washing") == true then 1 else nil)
end

local function update(dt: number)
	sinceScan += dt
	if sinceScan >= SCAN_SECONDS then
		sinceScan = 0
		for _, model in CollectionService:GetTagged(CarRig.TAG) do
			track(model)
		end
	end
	local now = Workspace:GetServerTimeNow()
	for model, car in cars do
		if model.Parent == nil or car.seat.Parent == nil then
			for _, instance in car.loops do
				if instance then
					instance:Destroy()
				end
			end
			cars[model] = nil
		else
			updateCar(model, car, now)
		end
	end
end

local Controller = {}

function Controller.start()
	local soundGroup = Instance.new("SoundGroup")
	soundGroup.Name = CarAudio.CONTROLS_GROUP
	soundGroup.Parent = SoundService
	group = soundGroup
	ControlPresses.connect(function(model: Model, name: string)
		local car = cars[model]
		if car then
			playOnce(car, car.sounds.press[name])
		end
	end)
	RunService.Heartbeat:Connect(update)
end

return Controller
