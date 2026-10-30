--!strict
--[[
	The live binnacle display of the car the local player drives, on a car whose display is one
	(its entry's binnacle; Controllers/Cluster draws a dial face): the shift lights, the page the
	display switch has stepped to (DisplayPage, Controllers/CarSwitches) and its readouts, on the
	screen the rig mounts in the binnacle and on the strip's lenses. Dark until START is pressed.
	Built once per drive, then updated from the car's readouts a few dozen times a second.
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CarEntry = require(ReplicatedStorage.Shared.Rules.CarEntry)
local CarRig = require(ReplicatedStorage.Shared.Car.CarRig)
local CarState = require(ReplicatedStorage.Shared.Car.CarState)
local Catalog = require(ReplicatedStorage.Shared.Config.Cars.Catalog)
local Cluster = require(ReplicatedStorage.Shared.Config.Cluster)
local DriveModes = require(ReplicatedStorage.Shared.Rules.DriveModes)
local DriverAssists = require(ReplicatedStorage.Shared.Rules.DriverAssists)

local BinnacleView = require(script.Parent.Parent.Ui.BinnacleView)

type Drive = { model: Model, entry: Catalog.Entry, view: BinnacleView.View }

local localPlayer = Players.LocalPlayer
local drive: Drive? = nil
local elapsed = 0

local function number(model: Model, name: string): number
	local value = model:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
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

local function refresh(current: Drive)
	local model, entry = current.model, current.entry
	local mode = DriveModes.current(entry.physics.modeOrder, model:GetAttribute("DrivingMode"))
	local state, now = CarState.read(model), Workspace:GetServerTimeNow()
	local page = model:GetAttribute("DisplayPage")
	BinnacleView.update(current.view, {
		on = CarEntry.startup(entry, state, now).sincePress ~= nil,
		readout = {
			rpm = CarEntry.shownRpm(entry, state, now, number(model, "Rpm")),
			gear = number(model, "Gear"),
			speedKmh = number(model, "SpeedKmh"),
			tcOn = DriverAssists.assists(model:GetAttribute("EscOff") == true, mode, entry.assists).tc,
			mode = entry.modeLabels[mode],
		},
		page = if typeof(page) == "number" then page else 1,
		lamps = { pitLimiter = model:GetAttribute("PitLimiter") == true, fault = false },
		now = os.clock(),
	})
end

local function update(dt: number)
	local model = drivenModel()
	local current = drive
	if current and current.model ~= model then
		BinnacleView.destroy(current.view)
		drive, current = nil, nil
	end
	if model == nil then
		return
	end
	if current == nil then
		local screen = model:FindFirstChild("ClusterScreen")
		local entry = Catalog.of(model)
		local spec = entry and entry.binnacle
		if screen == nil or not screen:IsA("BasePart") or entry == nil or spec == nil then
			return
		end
		current = { model = model, entry = entry, view = BinnacleView.build(screen, model, spec) }
		drive = current
	end
	elapsed += dt
	if elapsed < Cluster.UPDATE_INTERVAL then
		return
	end
	elapsed = 0
	refresh(current :: Drive)
end

local Controller = {}

function Controller.start()
	RunService.Heartbeat:Connect(update)
end

return Controller
