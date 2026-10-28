--!strict
--[[
	Plays the weather on this client: rain that builds and fades with Workspace's RainIntensity,
	from a light patter to a downpour; in the cockpit the outside muffled and the rain drumming on
	the roof; distant thunder in heavy rain; and, while the local player drives, the tyres' spray
	on a wet road by speed and Wetness. The mix is Rules/WeatherAudio's; this module plays it.

	Every sound is a region of one uploaded file. The rain, the roof and the thunder play flat,
	not positional. The spray is positional, on a point under Terrain kept on the driven car, so
	after the player gets out it fades where the car was instead of being cut. The sounds have
	their own groups; nothing here touches the engine's sound or the weather's visuals.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local CarRig = require(ReplicatedStorage.Shared.Car.CarRig)
local Config = require(ReplicatedStorage.Shared.Config.WeatherAudio)
local Rules = require(ReplicatedStorage.Shared.Rules.WeatherAudio)
local Units = require(ReplicatedStorage.Shared.Units)

-- A thunder is removed when it ends, or this long after its region would have ended.
local ONE_SHOT_GRACE = 5

type Loops = { rainLight: Sound, rainHeavy: Sound, roofLight: Sound, roofHeavy: Sound, spray: Sound }

type Audio = {
	state: Rules.State,
	input: Rules.Input,
	outside: SoundGroup,
	roof: SoundGroup,
	equaliser: EqualizerSoundEffect,
	loops: Loops,
	sprayPoint: Attachment,
}

type Car = { model: Model, chassis: BasePart }

local localPlayer = Players.LocalPlayer
local random = Random.new()
local car: Car? = nil

local SPRAY_OFFSET = Vector3.new(
	0,
	Units.metresToStuds(Config.SPRAY_POSITION.up),
	-Units.metresToStuds(Config.SPRAY_POSITION.forward)
)

local function readNumber(instance: Instance, name: string): number
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

local function group(name: string, parent: Instance): SoundGroup
	local soundGroup = Instance.new("SoundGroup")
	soundGroup.Name = name
	soundGroup.Parent = parent
	return soundGroup
end

local function loop(name: string, region: Config.Region, soundGroup: SoundGroup, parent: Instance): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = Config.SOUND_ID
	sound.Looped = true
	sound.PlaybackRegionsEnabled = true
	-- Starts in the guard before the loop, which is the loop's own end, and loops inside it.
	sound.PlaybackRegion = NumberRange.new(region.from - Config.GUARD, region.to + Config.GUARD)
	sound.LoopRegion = NumberRange.new(region.from, region.to)
	sound.Volume = 0
	sound.SoundGroup = soundGroup
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = Config.ROLL_OFF.from
	sound.RollOffMaxDistance = Config.ROLL_OFF.to
	sound.Parent = parent
	return sound
end

-- Pauses a loop while it is silent, at its own volume or its group's, and resumes it where it
-- was once it is not.
local function play(sound: Sound, volume: number, groupVolume: number)
	sound.Volume = volume
	local audible = volume * groupVolume > Config.SILENT_VOLUME
	if sound.Playing ~= audible then
		sound.Playing = audible
	end
end

local function thunder(audio: Audio, roll: Rules.Thunder)
	local region = Config.THUNDERS[roll.take]
	local shaping = Config.THUNDER_EQUALISER
	local sound = Instance.new("Sound")
	sound.Name = "Thunder"
	sound.SoundId = Config.SOUND_ID
	sound.PlaybackRegionsEnabled = true
	sound.PlaybackRegion = NumberRange.new(region.from, region.to)
	sound.Volume = roll.volume
	sound.PlaybackSpeed = roll.speed
	sound.SoundGroup = audio.outside
	local distance = Instance.new("EqualizerSoundEffect")
	distance.LowGain = shaping.low
	distance.MidGain = shaping.mid
	distance.HighGain = shaping.high
	distance.Parent = sound
	sound.Parent = audio.outside
	sound:Play()
	local function remove()
		sound:Destroy()
	end
	sound.Ended:Once(remove)
	task.delay((region.to - region.from) / roll.speed + ONE_SHOT_GRACE, remove)
end

local function update(audio: Audio, dt: number)
	local input = audio.input
	local camera = Workspace.CurrentCamera
	local current = car
	local driving = current ~= nil and current.chassis.Parent ~= nil
	input.rainIntensity = readNumber(Workspace, Config.RAIN_ATTRIBUTE)
	input.wetness = readNumber(Workspace, Config.WETNESS_ATTRIBUTE)
	input.speedKmh = if current and driving then readNumber(current.model, Config.SPEED_ATTRIBUTE) else 0
	input.cockpit = camera ~= nil and camera:GetAttribute(Config.VIEW_ATTRIBUTE) == Config.COCKPIT_VIEW
	input.driving = driving
	if current and driving then
		audio.sprayPoint.WorldPosition = current.chassis.CFrame:PointToWorldSpace(SPRAY_OFFSET)
	end

	local mix = Rules.step(audio.state, input, dt)
	local loops = audio.loops
	play(loops.rainLight, mix.rainLight, mix.outside)
	play(loops.rainHeavy, mix.rainHeavy, mix.outside)
	play(loops.roofLight, mix.roofLight, mix.roof)
	play(loops.roofHeavy, mix.roofHeavy, mix.roof)
	play(loops.spray, mix.spray, mix.outside)
	loops.spray.PlaybackSpeed = mix.spraySpeed
	audio.outside.Volume = mix.outside
	audio.roof.Volume = mix.roof
	audio.equaliser.MidGain = mix.midGain
	audio.equaliser.HighGain = mix.highGain
	if mix.thunder then
		thunder(audio, mix.thunder)
	end
end

local function onSeat(humanoid: Humanoid)
	local seat = humanoid.SeatPart
	local model = seat and seat.Parent
	local chassis = model and model:FindFirstChild("Chassis")
	if
		seat
		and seat:IsA("Seat")
		and model
		and model:IsA("Model")
		and model:HasTag(CarRig.TAG)
		and chassis
		and chassis:IsA("BasePart")
	then
		car = { model = model, chassis = chassis }
	else
		car = nil
	end
end

local function onCharacter(character: Model)
	car = nil
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	if character.Parent == nil then
		return
	end
	humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
		onSeat(humanoid)
	end)
end

local function build(): Audio
	local weather = group("DriveLabWeather", SoundService)
	local outside = group("Outside", weather)
	local roof = group("Roof", weather)
	local equaliser = Instance.new("EqualizerSoundEffect")
	equaliser.Parent = outside
	local sprayPoint = Instance.new("Attachment")
	sprayPoint.Name = "DriveLabSprayAudio"
	sprayPoint.Parent = Workspace.Terrain
	local regions = Config.LOOPS
	return {
		state = Rules.new(Config.TUNING, function(): number
			return random:NextNumber()
		end),
		input = { rainIntensity = 0, wetness = 0, speedKmh = 0, cockpit = false, driving = false },
		outside = outside,
		roof = roof,
		equaliser = equaliser,
		loops = {
			rainLight = loop("RainLight", regions.rainLight, outside, outside),
			rainHeavy = loop("RainHeavy", regions.rainHeavy, outside, outside),
			roofLight = loop("RoofLight", regions.roofLight, roof, roof),
			roofHeavy = loop("RoofHeavy", regions.roofHeavy, roof, roof),
			spray = loop("Spray", regions.spray, outside, sprayPoint),
		},
		sprayPoint = sprayPoint,
	}
end

local Controller = {}

function Controller.start()
	local audio = build()
	RunService.Heartbeat:Connect(function(dt: number)
		update(audio, dt)
	end)
	if localPlayer.Character then
		task.spawn(onCharacter, localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(onCharacter)
end

return Controller
