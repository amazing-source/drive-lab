--!strict
--[[
	The driven car's gear lever, drawn from its driver's shift readouts (LeverColumn, LeverRow and
	KnobDown, Controllers/Driving): turned about its pivot to its place in the H, its knob pushed
	down into reverse's lockout (Rules/ShiftHand, from the car's model binding). Local to the
	driver's client: other clients see it parked in the gate a drive starts in, as the server rigs it
	(Car/CarRig). Writes nothing but the lever's weld C0.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Binding = require(ReplicatedStorage.Shared.Config.Cars.Binding)
local CarRig = require(ReplicatedStorage.Shared.Car.CarRig)
local Catalog = require(ReplicatedStorage.Shared.Config.Cars.Catalog)
local ShiftHand = require(ReplicatedStorage.Shared.Rules.ShiftHand)
local ShiftSync = require(ReplicatedStorage.Shared.Rules.ShiftSync)
local Types = require(ReplicatedStorage.Shared.Config.Cars.Types)

type Drive = {
	model: Model,
	binding: Binding.CarModel,
	lever: ShiftHand.Lever,
	gates: { [number]: Types.Gate },
	joint: CarRig.Hinged?,
	-- The column, row and knob last written to the weld.
	written: { number }?,
	-- Seconds until the lever is looked for again, while its part has not streamed in.
	retry: number,
}

local RETRY_SECONDS = 1

local localPlayer = Players.LocalPlayer
local drive: Drive? = nil

local function seatedModel(): Model?
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	local model = seat and seat.Parent
	return if model and model:IsA("Model") and model:HasTag(CarRig.TAG) then model else nil
end

local function park(current: Drive)
	local joint = current.joint
	if joint and joint.weld.Parent then
		local column, row, knob = ShiftSync.parked(current.gates)
		joint.weld.C0 = CarRig.leverC0(joint.rest, current.lever, column, row, knob)
	end
end

-- Follows the seat: a car with a bound gear lever and an H-pattern manual, nothing otherwise.
local function follow(): Drive?
	local model = seatedModel()
	local current = drive
	if current and current.model == model then
		return current
	end
	if current then
		park(current)
	end
	drive = nil
	local entry = model and Catalog.of(model)
	local shifter = entry and entry.model.shifter
	local gearbox = entry and entry.physics.gearbox
	local manual = if gearbox and gearbox.kind == "manual" then gearbox.manual else nil
	if model == nil or entry == nil or shifter == nil or manual == nil then
		return nil
	end
	local fresh: Drive = {
		model = model,
		binding = entry.model,
		lever = ShiftHand.leverFromBinding(shifter, manual.gates, entry.model.seat),
		gates = manual.gates,
		joint = nil,
		written = nil,
		retry = 0,
	}
	drive = fresh
	return fresh
end

local function number(model: Model, name: string, fallback: number): number
	local value = model:GetAttribute(name)
	return if typeof(value) == "number" then value else fallback
end

local function update(dt: number)
	local current = follow()
	if current == nil then
		return
	end
	local model = current.model
	if current.joint == nil then
		current.retry -= dt
		if current.retry <= 0 then
			current.retry = RETRY_SECONDS
			local rig = CarRig.find(model, current.binding)
			current.joint = rig and rig.shifter
		end
	end
	local joint = current.joint
	if joint == nil then
		return
	end
	local parkedColumn, parkedRow = ShiftSync.parked(current.gates)
	local column = number(model, "LeverColumn", parkedColumn)
	local row = number(model, "LeverRow", parkedRow)
	local knob = number(model, "KnobDown", 0)
	local written = current.written
	if written and written[1] == column and written[2] == row and written[3] == knob then
		return
	end
	joint.weld.C0 = CarRig.leverC0(joint.rest, current.lever, column, row, knob)
	current.written = { column, row, knob }
end

local Controller = {}

function Controller.start()
	RunService.Heartbeat:Connect(update)
end

return Controller
