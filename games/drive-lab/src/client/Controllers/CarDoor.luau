--!strict
--[[
	The driver's door and the START flap of every car on this client, turned from the car's
	replicated entry state and the server's clock (Rules/CarEntry), so every client shows the
	same door at the same moment, late joiners too. The door's latch and shut sound from its outer
	panel. Writes nothing but the two hinge welds' C0 and the sounds it plays.
]]
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CarEntry = require(ReplicatedStorage.Shared.Config.CarEntry)
local CarRig = require(ReplicatedStorage.Shared.Car.CarRig)
local CarState = require(ReplicatedStorage.Shared.Car.CarState)
local Catalog = require(ReplicatedStorage.Shared.Config.Cars.Catalog)
local Config = require(ReplicatedStorage.Shared.Config.CarDoor)
local Entry = require(ReplicatedStorage.Shared.Rules.CarEntry)
local Hinge = require(ReplicatedStorage.Shared.Rules.Hinge)

type Car = {
	rig: CarRig.Rig,
	openAngle: number,
	panel: BasePart?,
	doorAngle: number,
	flapAngle: number,
	-- The door's openness Config.LEAD seconds ahead at the last frame; nil before the first.
	ahead: number?,
}

-- Seconds between looks for cars whose door has not streamed in yet.
local SCAN_SECONDS = 1
-- Seconds a one-shot outlives its region before it is removed anyway.
local SOUND_GRACE = 0.5

local cars: { [Model]: Car } = {}
local sinceScan = math.huge

local function track(model: Instance)
	if not model:IsA("Model") or cars[model] then
		return
	end
	local name = model:GetAttribute("Car")
	local entry = if typeof(name) == "string" then Catalog[name] else nil
	local binding = entry and entry.model
	if binding == nil or (binding.door == nil and binding.flap == nil) then
		return
	end
	local rig = CarRig.find(model, binding)
	-- A car whose door or flap has not streamed in yet is picked up on a later scan.
	if rig == nil or (binding.door and rig.door == nil) or (binding.flap and rig.flap == nil) then
		return
	end
	local panel = if binding.door then model:FindFirstChild(binding.door.parts[1], true) else nil
	cars[model] = {
		rig = rig,
		openAngle = if binding.door then binding.door.openAngle else 0,
		panel = if panel and panel:IsA("BasePart") then panel else nil,
		doorAngle = 0,
		flapAngle = 0,
		ahead = nil,
	}
end

local function play(panel: BasePart, region: Config.Region)
	local sound = Instance.new("Sound")
	sound.Name = "DoorSound"
	sound.SoundId = Config.SOUND_ID
	sound.PlaybackRegionsEnabled = true
	sound.PlaybackRegion = NumberRange.new(region.from, region.to)
	sound.Volume = Config.VOLUME
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = Config.ROLL_OFF.from
	sound.RollOffMaxDistance = Config.ROLL_OFF.to
	sound.Parent = panel
	sound:Play()
	local function remove()
		sound:Destroy()
	end
	sound.Ended:Once(remove)
	task.delay(region.to - region.from + SOUND_GRACE, remove)
end

local function poseDoor(car: Car, door: Weld, state: Entry.State, now: number)
	local angle = Hinge.angle(Entry.doorOpenness(state, now), car.openAngle)
	if angle ~= car.doorAngle then
		door.C0 = car.rig.doorRest * CFrame.Angles(angle, 0, 0)
		car.doorAngle = angle
	end
	local ahead = Entry.doorOpenness(state, now + Config.LEAD)
	local sound = if car.ahead ~= nil then Hinge.sound(car.ahead, ahead) else nil
	car.ahead = ahead
	if sound and car.panel and Config.SOUND_ID ~= "" then
		play(car.panel, if sound == "Latch" then Config.LATCH else Config.SHUT)
	end
end

local function poseFlap(car: Car, flap: Weld, state: Entry.State, now: number)
	local angle = Hinge.angle(Entry.flapOpenness(state, now), CarEntry.STARTUP.flapAngle)
	if angle ~= car.flapAngle then
		flap.C0 = car.rig.flapRest * CFrame.Angles(angle, 0, 0)
		car.flapAngle = angle
	end
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
		if model.Parent == nil or car.rig.chassis.Parent == nil then
			cars[model] = nil
			continue
		end
		local state = CarState.read(model)
		local door, flap = car.rig.door, car.rig.flap
		if door then
			poseDoor(car, door, state, now)
		end
		if flap then
			poseFlap(car, flap, state, now)
		end
	end
end

local Controller = {}

function Controller.start()
	CollectionService:GetInstanceAddedSignal(CarRig.TAG):Connect(track)
	-- Before the frame is drawn, so the door and the hand that holds it move in the same frame.
	RunService.PreRender:Connect(update)
end

return Controller
