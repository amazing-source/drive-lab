--!strict
--[[
	Effects of the car the local player drives: smoke from its sliding tyres and the air debris
	it drives through. Reads what Driving publishes on the car, the car's motion and Workspace's
	Wetness; writes nothing but its own particles. Leaving the car stops new particles and lets
	the ones in the air finish.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CarRig = require(ReplicatedStorage.Shared.Car.CarRig)
local RulesTyreSmoke = require(ReplicatedStorage.Shared.Rules.TyreSmoke)

local AirDebris = require(script.Parent.Parent.Effects.AirDebris)
local TyreSmoke = require(script.Parent.Parent.Effects.TyreSmoke)

type Ride = {
	model: Model,
	chassis: BasePart,
	smoke: TyreSmoke.TyreSmoke?,
	-- The car's bounding box from its pivot, measured once.
	offset: CFrame,
	-- Rewritten each frame for the debris.
	motion: AirDebris.Motion,
}

type State = {
	debris: AirDebris.AirDebris,
	ride: Ride?,
	-- Kept after leaving a car, so its smoke fades rather than vanishing.
	lastSmoke: TyreSmoke.TyreSmoke?,
	readings: { RulesTyreSmoke.Wheel },
}

local localPlayer = Players.LocalPlayer
local state: State? = nil

local function seatedCar(): Model?
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	local model = seat and seat.Parent
	if model and model:IsA("Model") and model:HasTag(CarRig.TAG) then
		return model
	end
	return nil
end

local function board(current: State, model: Model): Ride?
	local chassis = model:FindFirstChild("Chassis")
	if chassis == nil or not chassis:IsA("BasePart") then
		return nil
	end
	if current.lastSmoke and current.lastSmoke.model ~= model then
		TyreSmoke.destroy(current.lastSmoke)
		current.lastSmoke = nil
	end
	local smoke = current.lastSmoke or TyreSmoke.new(model)
	current.lastSmoke = smoke
	local box, size = model:GetBoundingBox()
	return {
		model = model,
		chassis = chassis,
		smoke = smoke,
		offset = model:GetPivot():ToObjectSpace(box),
		motion = { model = model, box = box, size = size, velocity = Vector3.zero, turnRate = 0 },
	}
end

local function wetness(): number
	local value = Workspace:GetAttribute("Wetness")
	return if typeof(value) == "number" and value == value then math.clamp(value, 0, 1) else 0
end

local function update(dt: number)
	local current = state
	if current == nil then
		return
	end
	local model = seatedCar()
	local ride = current.ride
	if ride and (ride.model ~= model or ride.model.Parent == nil) then
		if ride.smoke then
			TyreSmoke.idle(ride.smoke)
		end
		current.ride, ride = nil, nil
	end
	if ride == nil and model then
		ride = board(current, model)
		current.ride = ride
	end
	if ride == nil then
		AirDebris.update(current.debris, nil, 0)
		return
	end
	debug.profilebegin("DrivingEffects")
	local wet = wetness()
	if ride.smoke then
		TyreSmoke.read(ride.model, current.readings)
		TyreSmoke.update(ride.smoke, current.readings, wet, dt)
	end
	local motion = ride.motion
	local box = ride.model:GetPivot() * ride.offset
	motion.box = box
	motion.velocity = ride.chassis.AssemblyLinearVelocity
	-- Positive turning right, which is a negative spin about up (as VehicleRunner reads it).
	motion.turnRate = -ride.chassis.AssemblyAngularVelocity:Dot(box.UpVector)
	AirDebris.update(current.debris, motion, wet)
	debug.profileend()
end

local Controller = {}

function Controller.start()
	if state then
		return
	end
	state = {
		debris = AirDebris.new(),
		ride = nil,
		lastSmoke = nil,
		readings = {},
	}
	-- After the driving camera (Camera + 2) and the weather (+3), which publishes Wetness.
	RunService:BindToRenderStep("DriveLabDrivingEffects", Enum.RenderPriority.Camera.Value + 4, update)
end

return Controller
