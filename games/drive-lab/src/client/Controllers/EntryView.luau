--!strict
--[[
	The camera while the local player gets in or out; CarCamera asks it each frame. In the third
	person views it keeps the framing the camera had when the sequence began and follows the
	body with it, easing into the car's own view as the entry ends and out of it as the exit
	begins. In the cockpit view it rides the animated head. Seated, it hands back the car's view.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CarState = require(ReplicatedStorage.Shared.Car.CarState)
local Rules = require(ReplicatedStorage.Shared.Rules.CarEntry)

-- Seconds over which the view eases between following the body and the car's view.
local BLEND_SECONDS = 1.2
-- Studs the third person camera keeps from the head, whatever framing it started with.
local MIN_DISTANCE, MAX_DISTANCE = 5, 16
-- The eye in the head's own axes: a little up and forward of its centre.
local EYE = CFrame.new(0, 0.1, -0.35)

type Sequence = { startedAt: number, offset: Vector3 }

local localPlayer = Players.LocalPlayer
local sequence: Sequence? = nil

local EntryView = {}

local function smooth(share: number): number
	local x = math.clamp(share, 0, 1)
	return x * x * (3 - 2 * x)
end

local function head(): BasePart?
	local character = localPlayer.Character
	local part = character and character:FindFirstChild("Head")
	return if part and part:IsA("BasePart") then part else nil
end

local function startOffset(entering: boolean, from: Vector3, normal: CFrame, focus: Vector3): Vector3
	local offset = (if entering then from else normal.Position) - focus
	local distance = math.clamp(offset.Magnitude, MIN_DISTANCE, MAX_DISTANCE)
	return if offset.Magnitude > 1e-3 then offset.Unit * distance else Vector3.new(0, 0, distance)
end

-- `normal` is where the car's view would put the camera; `current` is where it is now.
function EntryView.place(view: string, model: Model, normal: CFrame, current: CFrame): CFrame
	local state = CarState.read(model)
	local at = Workspace:GetServerTimeNow()
	local phase = Rules.phase(state, at)
	local headPart = head()
	if (phase ~= "Entering" and phase ~= "Exiting") or headPart == nil then
		sequence = nil
		return normal
	end
	local entering = phase == "Entering"
	local previous = sequence
	local active: Sequence = if previous and previous.startedAt == state.entryAt
		then previous
		else {
			startedAt = state.entryAt,
			offset = startOffset(entering, current.Position, normal, headPart.Position),
		}
	sequence = active
	local follow = if view == "Cockpit"
		then headPart.CFrame * EYE
		else CFrame.lookAt(headPart.Position + active.offset, headPart.Position)
	local elapsed = at - state.entryAt
	local length = Rules.length(Rules.steps(state.entry, state.entryDoorOpen))
	local weight = if entering
		then smooth((elapsed - (length - BLEND_SECONDS)) / BLEND_SECONDS)
		else 1 - smooth(elapsed / BLEND_SECONDS)
	return follow:Lerp(normal, weight)
end

return EntryView
