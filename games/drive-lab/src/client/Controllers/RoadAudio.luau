--!strict
--[[
	Plays the sound of speed while the local player drives: the wind, through a low-pass that
	opens as the car goes faster, and the tyres' roar, shaped by the surface under the car. In
	the cockpit both are muffled, the roar less than the wind. The mix is Rules/RoadAudio's; this
	module plays it.

	Built on the audio API rather than Sound objects, because only its AudioFilter has a cutoff
	that can move: each loop is an AudioPlayer wired through its effects to one
	AudioDeviceOutput, so they play flat, as the weather's rain does. Both loops are regions of
	one uploaded file. Nothing here touches the engine's sound.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local CarRig = require(ReplicatedStorage.Shared.Car.CarRig)
local Config = require(ReplicatedStorage.Shared.Config.RoadAudio)
local Rules = require(ReplicatedStorage.Shared.Rules.RoadAudio)
local Units = require(ReplicatedStorage.Shared.Units)

type Loop = { player: AudioPlayer, equaliser: AudioEqualizer }

type Audio = {
	state: Rules.State,
	input: Rules.Input,
	wind: Loop,
	road: Loop,
	cutoff: AudioFilter,
	surfaceIn: number,
}

type Car = { model: Model, chassis: BasePart, ray: RaycastParams }

local localPlayer = Players.LocalPlayer
local car: Car? = nil

local function readNumber(instance: Instance, name: string): number
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

local function wire(source: Instance, target: Instance)
	local link = Instance.new("Wire")
	link.SourceInstance = source
	link.TargetInstance = target
	link.Parent = target
end

local function player(name: string, region: Config.Region, parent: Instance): AudioPlayer
	local audio = Instance.new("AudioPlayer")
	audio.Name = name
	audio.Asset = Config.SOUND_ID
	audio.Looping = true
	-- Starts in the guard before the loop, which is the loop's own end, and loops inside it.
	audio.PlaybackRegion = NumberRange.new(region.from - Config.GUARD, region.to + Config.GUARD)
	audio.LoopRegion = NumberRange.new(region.from, region.to)
	audio.Volume = 0
	audio.Parent = parent
	return audio
end

local function equaliser(name: string, parent: Instance): AudioEqualizer
	local effect = Instance.new("AudioEqualizer")
	effect.Name = name
	effect.MidRange = NumberRange.new(Config.MID_BAND.from, Config.MID_BAND.to)
	effect.Parent = parent
	return effect
end

-- Stops a loop while it is silent and resumes it where it was once it is not.
local function play(loop: Loop, volume: number, speed: number, shaping: Rules.Shaping)
	local audio = loop.player
	audio.Volume = volume
	audio.PlaybackSpeed = speed
	loop.equaliser.LowGain = shaping.low
	loop.equaliser.MidGain = shaping.mid
	loop.equaliser.HighGain = shaping.high
	local audible = volume > Config.SILENT_VOLUME
	if audio.IsPlaying ~= audible then
		if audible then
			audio:Play()
		else
			audio:Stop()
		end
	end
end

-- The material under the chassis, or nil over nothing (in the air, off the map).
local function surfaceUnder(current: Car): string?
	local origin = current.chassis.Position
	local hit =
		Workspace:Raycast(origin, Vector3.new(0, -Units.metresToStuds(Config.SURFACE_REACH), 0), current.ray)
	return if hit then hit.Material.Name else nil
end

local function update(audio: Audio, dt: number)
	local input = audio.input
	local camera = Workspace.CurrentCamera
	local current = car
	local driving = current ~= nil and current.chassis.Parent ~= nil
	input.speedKmh = if current and driving then readNumber(current.model, Config.SPEED_ATTRIBUTE) else 0
	input.cockpit = camera ~= nil and camera:GetAttribute(Config.VIEW_ATTRIBUTE) == Config.COCKPIT_VIEW
	input.driving = driving
	audio.surfaceIn -= dt
	if current and driving and audio.surfaceIn <= 0 then
		audio.surfaceIn = Config.SURFACE_INTERVAL
		input.surface = surfaceUnder(current)
	end

	local mix = Rules.step(audio.state, input, dt)
	audio.cutoff.Frequency = mix.windCutoff
	play(audio.wind, mix.wind, mix.windSpeed, mix.windEq)
	play(audio.road, mix.road, mix.roadSpeed, mix.roadEq)
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
		local ray = RaycastParams.new()
		ray.FilterType = Enum.RaycastFilterType.Exclude
		ray.FilterDescendantsInstances = { model, humanoid.Parent :: Instance }
		ray.IgnoreWater = true
		car = { model = model, chassis = chassis, ray = ray }
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
	local folder = Instance.new("Folder")
	folder.Name = "DriveLabRoad"
	local output = Instance.new("AudioDeviceOutput")
	output.Parent = folder

	local windPlayer = player("Wind", Config.LOOPS.wind, folder)
	local cutoff = Instance.new("AudioFilter")
	cutoff.Name = "WindCutoff"
	cutoff.FilterType = Enum.AudioFilterType.Lowpass12dB
	cutoff.Q = Config.CUTOFF_Q
	cutoff.Frequency = Config.TUNING.cutoffHz.from
	cutoff.Parent = folder
	local windShaping = equaliser("WindShaping", folder)
	wire(windPlayer, cutoff)
	wire(cutoff, windShaping)
	wire(windShaping, output)

	local roadPlayer = player("Road", Config.LOOPS.road, folder)
	local roadShaping = equaliser("RoadShaping", folder)
	wire(roadPlayer, roadShaping)
	wire(roadShaping, output)
	folder.Parent = SoundService

	return {
		state = Rules.new(Config.TUNING),
		input = { speedKmh = 0, cockpit = false, driving = false, surface = nil },
		wind = { player = windPlayer, equaliser = windShaping },
		road = { player = roadPlayer, equaliser = roadShaping },
		cutoff = cutoff,
		surfaceIn = 0,
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
