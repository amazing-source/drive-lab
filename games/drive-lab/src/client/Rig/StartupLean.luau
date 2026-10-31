--!strict
--[[
	The start-up's torso lean on a seated driver (Rules/StartupLean, from the car's startup paths'
	LEAN): the turn Controllers/BodyLean composes into its root joint layer, so one writer keeps that
	joint, and the cockpit eye with the lean taken back out, so the view does not dip
	(Controllers/CarCamera). Nothing on a car without a lean or outside its keys.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CarRig = require(ReplicatedStorage.Shared.Car.CarRig)
local CarState = require(ReplicatedStorage.Shared.Car.CarState)
local Catalog = require(ReplicatedStorage.Shared.Config.Cars.Catalog)
local Rules = require(ReplicatedStorage.Shared.Rules.StartupLean)
local Units = require(ReplicatedStorage.Shared.Units)

local StartupLean = {}

-- The seat the humanoid sits in and its lean now, in the seat's space (studs), or nil.
local function active(humanoid: Humanoid): (BasePart?, CFrame)
	local seat = humanoid.SeatPart
	local model = seat and seat.Parent
	if seat == nil or model == nil or not model:IsA("Model") or not model:HasTag(CarRig.TAG) then
		return nil, CFrame.identity
	end
	local entry = Catalog.of(model)
	local lean = entry and entry.driver.startupPaths.LEAN
	if lean == nil then
		return nil, CFrame.identity
	end
	local state = CarState.read(model)
	local sinceKey = if state.engine == "On" then Workspace:GetServerTimeNow() - state.engineAt else nil
	local degrees = Rules.degrees(lean, sinceKey)
	if degrees == 0 then
		return nil, CFrame.identity
	end
	local turn, offset = Rules.turn(lean.pivot, degrees)
	local studs = Units.metresToStuds(1)
	return seat,
		CFrame.new(offset.x * studs, offset.y * studs, offset.z * studs) * CFrame.new(
			0,
			0,
			0,
			turn.x,
			turn.y,
			turn.z,
			turn.w
		)
end

-- The lean as a turn in the root part's axes about the joint's pivot (`jointPivot`, in the root
-- part's space), as Rig/JointLayer takes it; nil when there is none.
function StartupLean.rootTurn(humanoid: Humanoid, root: BasePart, jointPivot: Vector3): CFrame?
	local seat, lean = active(humanoid)
	if seat == nil then
		return nil
	end
	local seatInRoot = root.CFrame:ToObjectSpace(seat.CFrame)
	local inRoot = seatInRoot * lean * seatInRoot:Inverse()
	return CFrame.new(-jointPivot) * inRoot * CFrame.new(jointPivot)
end

-- `point` (world) with the humanoid's start-up lean undone.
function StartupLean.unlean(humanoid: Humanoid, point: Vector3): Vector3
	local seat, lean = active(humanoid)
	if seat == nil then
		return point
	end
	return seat.CFrame:PointToWorldSpace(
		lean:Inverse():PointToWorldSpace(seat.CFrame:PointToObjectSpace(point))
	)
end

return StartupLean
