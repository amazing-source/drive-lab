--!strict
--[[
	The chase camera's placement, after Assetto Corsa's first chase camera: hung off the rear axle
	in the car's own frame, so it turns with the car and rides the body's pitch, and aimed with the
	world's up, so it never rolls. Two things are smoothed and nothing else: the shift with the
	car's g (Config CHASE.lean) and, when switched on, the spring on the yaw (CHASE.yawSpring) and
	the turn toward a drifting car's path (CHASE.driftBlend).
	Not a controller: CarCamera steps and places it.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CarCamera = require(ReplicatedStorage.Shared.Config.CarCamera)
local Catalog = require(ReplicatedStorage.Shared.Config.Cars.Catalog)
local Rules = require(ReplicatedStorage.Shared.Rules.CarCamera)
local Units = require(ReplicatedStorage.Shared.Units)

-- `axle` is the rear axle from the centre of mass (metres, forward and up) of `model`, and
-- `framing` its chase distance and height.
export type State = {
	model: Model?,
	axle: { forward: number, up: number },
	framing: CarCamera.ChaseFraming,
	lean: Rules.Lean,
	yaw: Rules.Spring?,
	driftYaw: number,
}

local ChaseView = {}

local function studs(metres: number): number
	return Units.metresToStuds(metres)
end

local function number(model: Model, name: string): number
	local value = model:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

local function headingYaw(frame: CFrame): number
	local look = frame.LookVector
	return math.atan2(-look.X, -look.Z)
end

function ChaseView.new(): State
	return {
		model = nil,
		axle = { forward = 0, up = 0 },
		framing = Rules.chaseFraming(nil),
		lean = { right = 0, back = 0 },
		yaw = nil,
		driftYaw = 0,
	}
end

-- Once a frame in every view, so the chase is current whenever it is switched to. `velocity` is
-- the chassis's, in studs per second.
function ChaseView.step(state: State, model: Model, chassis: CFrame, velocity: Vector3, dt: number)
	if state.model ~= model then
		local entry = Catalog.of(model)
		if entry == nil then
			return
		end
		local forward, up = Rules.rearAxle(entry.physics)
		state.model, state.axle = model, { forward = forward, up = up }
		state.framing = Rules.chaseFraming(entry.camera)
	end
	local target =
		Rules.leanTarget(number(model, "LongitudinalG"), number(model, "LateralG"), number(model, "SpeedKmh"))
	Rules.stepLean(state.lean, target, dt)
	local spring = CarCamera.CHASE.yawSpring
	if not spring.enabled then
		state.yaw = nil
	elseif state.yaw == nil then
		state.yaw = Rules.newSpring(headingYaw(chassis))
	else
		Rules.stepYaw(state.yaw, headingYaw(chassis), dt, spring.hz)
	end
	local blend = CarCamera.CHASE.driftBlend
	if blend.enabled then
		local path = math.atan2(-velocity.X, -velocity.Z)
		local speed = Units.studsToMetres(Vector3.new(velocity.X, 0, velocity.Z).Magnitude)
		local turn = Rules.driftYawTarget(number(model, "Drift"), headingYaw(chassis), path, speed, blend)
		state.driftYaw = Rules.stepDriftYaw(state.driftYaw, turn, dt, blend.halfLife)
	else
		state.driftYaw = 0
	end
end

-- Looking around (lookYaw, lookPitch) orbits the eye round the car's centre of mass, so the car
-- stays in view.
function ChaseView.place(state: State, chassis: CFrame, lookYaw: number, lookPitch: number): CFrame
	local chase = CarCamera.CHASE
	local yaw = (if state.yaw then state.yaw.angle else headingYaw(chassis)) + state.driftYaw
	local pitch = math.asin(math.clamp(chassis.LookVector.Y, -1, 1))
	local anchor = chassis:PointToWorldSpace(Vector3.new(0, studs(state.axle.up), -studs(state.axle.forward)))
	local toCentre = -studs(state.axle.forward)
	local orbit = CFrame.new(anchor)
		* CFrame.Angles(0, yaw, 0)
		* CFrame.Angles(pitch, 0, 0)
		* CFrame.new(0, 0, -toCentre)
		* CFrame.Angles(0, lookYaw, 0)
		* CFrame.Angles(-lookPitch, 0, 0)
		* CFrame.new(0, 0, toCentre)
	local lean = state.lean
	local framing = state.framing
	local eye = orbit
		* Vector3.new(studs(lean.right), studs(framing.height), studs(framing.distance + lean.back))
	local focus = orbit * Vector3.new(0, 0, -studs(chase.lookAhead))
	return CFrame.lookAt(eye, focus) * CFrame.Angles(chase.pitch, 0, 0)
end

return ChaseView
