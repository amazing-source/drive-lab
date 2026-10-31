--!strict
--[[
	Plays the tyres' squeal and skid while the local player drives: one pair of loops per axle,
	from the slip and slide Driving publishes for each tyre, under a ceiling set by what the engine
	plays (Controllers/CarAudio publishes it). The mix is Rules/TyreAudio's; this module plays it,
	flat through one AudioDeviceOutput as the road's sound is. Both loops are regions of the pack
	Config/TyreAudio picks.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local CarRig = require(ReplicatedStorage.Shared.Car.CarRig)
local Config = require(ReplicatedStorage.Shared.Config.TyreAudio)
local Rules = require(ReplicatedStorage.Shared.Rules.TyreAudio)

type Loop = { player: AudioPlayer, equaliser: AudioEqualizer }
type AxleLoops = { squeal: Loop, skid: Loop }

type Audio = {
	state: Rules.State,
	input: Rules.Input,
	front: AxleLoops,
	rear: AxleLoops,
}

local localPlayer = Players.LocalPlayer
local car: Model? = nil

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

local function loop(name: string, region: Config.Region, parent: Instance, output: Instance): Loop
	local pack = Config.PACKS[Config.PACK]
	local audio = Instance.new("AudioPlayer")
	audio.Name = name
	audio.Asset = pack.soundId
	audio.Looping = true
	-- Starts in the guard before the loop, which is the loop's own end, and loops inside it.
	audio.PlaybackRegion = NumberRange.new(region.from - Config.GUARD, region.to + Config.GUARD)
	audio.LoopRegion = NumberRange.new(region.from, region.to)
	audio.Volume = 0
	audio.Parent = parent
	local effect = Instance.new("AudioEqualizer")
	effect.Name = `{name}Shaping`
	effect.MidRange = NumberRange.new(Config.MID_BAND.from, Config.MID_BAND.to)
	effect.Parent = parent
	wire(audio, effect)
	wire(effect, output)
	return { player = audio, equaliser = effect }
end

-- Stops a loop while it is silent and resumes it once it is not.
local function play(target: Loop, volume: number, speed: number, shaping: Rules.Shaping)
	local audio = target.player
	audio.Volume = volume
	audio.PlaybackSpeed = speed
	target.equaliser.LowGain = shaping.low
	target.equaliser.MidGain = shaping.mid
	target.equaliser.HighGain = shaping.high
	local audible = volume > Config.SILENT_VOLUME
	if audio.IsPlaying ~= audible then
		if audible then
			audio:Play()
		else
			audio:Stop()
		end
	end
end

local function readAxle(model: Model, into: Rules.Axle, first: number)
	for index = 1, 2 do
		local wheel = first + index - 1
		into.slips[index] = readNumber(model, Config.SLIP_ATTRIBUTES[wheel])
		into.slides[index] = readNumber(model, Config.SLIDE_ATTRIBUTES[wheel])
	end
end

local function update(audio: Audio, dt: number)
	local input = audio.input
	local camera = Workspace.CurrentCamera
	local current = car
	local driving = current ~= nil and current.Parent ~= nil
	input.driving = driving
	if current and driving then
		readAxle(current, input.front, 1)
		readAxle(current, input.rear, 3)
		input.engineLevel = readNumber(current, Config.ENGINE_LEVEL_ATTRIBUTE)
	end
	input.wetness = readNumber(Workspace, "Wetness")
	input.cockpit = camera ~= nil and camera:GetAttribute(Config.VIEW_ATTRIBUTE) == Config.COCKPIT_VIEW

	local mix = Rules.step(audio.state, input, dt)
	play(audio.front.squeal, mix.front.squeal, mix.front.squealSpeed, mix.squealEq)
	play(audio.front.skid, mix.front.skid, mix.front.skidSpeed, mix.skidEq)
	play(audio.rear.squeal, mix.rear.squeal, mix.rear.squealSpeed, mix.squealEq)
	play(audio.rear.skid, mix.rear.skid, mix.rear.skidSpeed, mix.skidEq)
end

local function onSeat(humanoid: Humanoid)
	local seat = humanoid.SeatPart
	local model = seat and seat.Parent
	if seat and seat:IsA("Seat") and model and model:IsA("Model") and model:HasTag(CarRig.TAG) then
		car = model
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
	folder.Name = "DriveLabTyres"
	local output = Instance.new("AudioDeviceOutput")
	output.Parent = folder
	local loops = Config.PACKS[Config.PACK].loops
	local audio: Audio = {
		state = Rules.new(Config.TUNING),
		input = {
			front = { slips = { 0, 0 }, slides = { 0, 0 } },
			rear = { slips = { 0, 0 }, slides = { 0, 0 } },
			wetness = 0,
			engineLevel = 0,
			cockpit = false,
			driving = false,
		},
		front = {
			squeal = loop("FrontSqueal", loops.squeal, folder, output),
			skid = loop("FrontSkid", loops.skid, folder, output),
		},
		rear = {
			squeal = loop("RearSqueal", loops.squeal, folder, output),
			skid = loop("RearSkid", loops.skid, folder, output),
		},
	}
	folder.Parent = SoundService
	return audio
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
