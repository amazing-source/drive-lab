--!strict
--[[
	The driver's arms. While a character sits in a car's driver seat, its blocky arms are hidden
	and custom ones drawn instead: the hands on the steering wheel's rim at a quarter to three,
	turning with the wheel up to FOLLOW_LIMIT either way (past that the wheel slides through
	them), and an upper arm and a forearm reaching each wrist from the shoulder, the elbow
	bending down and out (Rules/ArmIK).

	The hands are meshes posed around the SVJ's rim (tools/blender/hand_grip.py), tinted with
	the avatar's arm colour; the sleeves are modelled tubes (tools/blender/driver_sleeves.py)
	stretched to each bone, the forearm turned so its cuff lies flat with the hand, and a ball of
	the same cloth fills the elbow. All are kept in the place at ReplicatedStorage.DriveLabAssets. Every client draws every driver's arms: they are cosmetic, built
	locally and never replicated. A car's steering readout exists only on its driver's client, so other drivers'
	hands rest at the straight-ahead grip, as their wheels do here. Drawn after physics each
	frame from the parts' current positions, so the arms never trail a car at speed.
]]
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Log = require(ReplicatedStorage.Kit.Log)

local ArmIK = require(ReplicatedStorage.Shared.Rules.ArmIK)
local CarRig = require(ReplicatedStorage.Shared.Car.CarRig)
local Catalog = require(ReplicatedStorage.Shared.Config.Cars.Catalog)
local DriverArms = require(ReplicatedStorage.Shared.Config.DriverArms)
local Steering = require(ReplicatedStorage.Shared.Vehicle.Steering)

type Side = {
	-- +1 for the right arm, -1 for the left.
	sign: number,
	joint: Motor6D,
	arm: BasePart,
	armTransparency: number,
	upper: BasePart,
	lower: BasePart,
	elbow: BasePart,
	hand: BasePart,
	cuff: BasePart,
}

type Driver = {
	character: Model,
	torso: BasePart,
	model: Model,
	chassis: BasePart,
	rest: CFrame,
	maxTurn: number,
	scale: number,
	sides: { Side },
}

local LIMBS: { { sign: number, joint: string, arm: string } } = {
	{ sign = 1, joint = "Right Shoulder", arm = "Right Arm" },
	{ sign = -1, joint = "Left Shoulder", arm = "Left Arm" },
}

local log = Log.scope("DriverArms")
local folder: Folder? = nil
local warned = false
local drivers: { [Model]: Driver } = {}
local parts: { BasePart } = {}
local frames: { CFrame } = {}

local function template(group: string, name: string): BasePart?
	local assets = ReplicatedStorage:FindFirstChild("DriveLabAssets")
	local holder = assets and assets:FindFirstChild(group)
	local found = holder and holder:FindFirstChild(name)
	if found and found:IsA("BasePart") then
		return found
	end
	if not warned then
		warned = true
		log.warn(`ReplicatedStorage.DriveLabAssets.{group}.{name} is missing; the arms stay blocky`)
	end
	return nil
end

local function sleeve(from: BasePart): BasePart
	local part = from:Clone()
	part.Color = DriverArms.SLEEVE_COLOR
	part.Parent = folder
	return part
end

local function elbowBall(scale: number): BasePart
	local part = Instance.new("Part")
	part.Name = "Elbow"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * DriverArms.ELBOW_SIZE * scale
	part.Color = DriverArms.SLEEVE_COLOR
	part.Material = Enum.Material.Fabric
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Parent = folder
	return part
end

local function seatedCharacter(model: Model): Model?
	local seat = model:FindFirstChild("DriverSeat")
	local occupant = if seat and seat:IsA("Seat") then seat.Occupant else nil
	local character = occupant and occupant.Parent
	return if character and character:IsA("Model") then character else nil
end

local function release(driver: Driver)
	for _, side in driver.sides do
		side.upper:Destroy()
		side.lower:Destroy()
		side.elbow:Destroy()
		side.hand:Destroy()
		side.cuff:Destroy()
		if side.arm.Parent then
			side.arm.Transparency = side.armTransparency
		end
	end
end

local function build(model: Model, character: Model): Driver?
	local torso = character:FindFirstChild("Torso")
	local chassis = model:FindFirstChild("Chassis")
	local wheel = chassis and chassis:FindFirstChild("SteeringWheel")
	local name = model:GetAttribute("Car")
	local entry = if typeof(name) == "string" then Catalog[name] else nil
	if
		torso == nil
		or not torso:IsA("BasePart")
		or chassis == nil
		or not chassis:IsA("BasePart")
		or wheel == nil
		or not wheel:IsA("Weld")
		or wheel.Part1 == nil
		or entry == nil
	then
		return nil
	end
	local rest = wheel:GetAttribute("RestC0")
	if typeof(rest) ~= "CFrame" then
		return nil
	end
	-- Both arms found before anything is made or hidden, so a missing one leaves no trace.
	local upperSleeve, lowerSleeve = template("Sleeves", "UpperArm"), template("Sleeves", "Forearm")
	if upperSleeve == nil or lowerSleeve == nil then
		return nil
	end
	local found: { { sign: number, joint: Motor6D, arm: BasePart, hand: BasePart, cuff: BasePart } } = {}
	for _, limb in LIMBS do
		local joint = torso:FindFirstChild(limb.joint)
		local arm = character:FindFirstChild(limb.arm)
		local letter = if limb.sign > 0 then "R" else "L"
		local hand, cuff = template("Hands", "Hand_" .. letter), template("Hands", "Cuff_" .. letter)
		if
			joint == nil
			or not joint:IsA("Motor6D")
			or arm == nil
			or not arm:IsA("BasePart")
			or hand == nil
			or cuff == nil
		then
			return nil
		end
		table.insert(found, { sign = limb.sign, joint = joint, arm = arm, hand = hand, cuff = cuff })
	end
	local scale = character:GetScale()
	local sides = {}
	for _, limb in found do
		local joint, arm = limb.joint, limb.arm
		-- Each sleeve keeps its modelled cross-section and stretches to its bone's length.
		local upper = sleeve(upperSleeve)
		upper.Size = Vector3.new(upper.Size.X, upper.Size.Y, DriverArms.UPPER_LENGTH * scale)
		local lower = sleeve(lowerSleeve)
		lower.Size = Vector3.new(
			lower.Size.X,
			lower.Size.Y,
			DriverArms.LOWER_LENGTH * scale + DriverArms.CUFF_OVERHANG
		)
		-- The skin's detail map is near white; the avatar's arm colour tints it.
		local hand = limb.hand:Clone()
		local skin = hand:FindFirstChildOfClass("SurfaceAppearance")
		if skin then
			skin.Color = arm.Color
		else
			hand.Color = arm.Color
		end
		hand.Parent = folder
		table.insert(sides, {
			sign = limb.sign,
			joint = joint,
			arm = arm,
			armTransparency = arm.Transparency,
			upper = upper,
			lower = lower,
			elbow = elbowBall(scale),
			hand = hand,
			cuff = sleeve(limb.cuff),
		})
		arm.Transparency = 1
	end
	return {
		character = character,
		torso = torso,
		model = model,
		chassis = chassis,
		rest = rest,
		maxTurn = Steering.maxWheelAngle(entry.physics.steering),
		scale = scale,
		sides = sides,
	}
end

-- Shoulder to wrist with the elbow between, as the two bones' frames: each looks down its bone
-- from the joint nearer the body. The upper arm's up axis is the normal of the arm's plane; the
-- forearm's is the back of the hand, so the cuff's flat sides lie with the wrist's.
local function reach(
	shoulder: Vector3,
	wrist: Vector3,
	pole: Vector3,
	handBack: Vector3,
	upper: number,
	lower: number
): (CFrame, CFrame)
	local toWrist = wrist - shoulder
	local solved = ArmIK.solve(upper, lower, toWrist.Magnitude)
	local along = toWrist.Unit
	local outward = (pole - along * pole:Dot(along)).Unit
	local elbow = shoulder
		+ along * (upper * math.cos(solved.bend))
		+ outward * (upper * math.sin(solved.bend))
	local reached = shoulder + along * solved.reach
	local normal = along:Cross(outward)
	return CFrame.lookAt(shoulder, elbow, normal), CFrame.lookAt(elbow, reached, handBack)
end

local function pose(driver: Driver)
	local steer = driver.model:GetAttribute("Steer")
	local turn = math.clamp(
		(if typeof(steer) == "number" then steer else 0) * driver.maxTurn,
		-DriverArms.FOLLOW_LIMIT,
		DriverArms.FOLLOW_LIMIT
	)
	-- The same turn the runner gives the wheel: negative about the column's +Z, toward the driver.
	local wheel = driver.chassis.CFrame * driver.rest * CFrame.Angles(0, 0, -turn)
	local torso = driver.torso.CFrame
	local scale = driver.scale
	local upper, lower = DriverArms.UPPER_LENGTH * scale, DriverArms.LOWER_LENGTH * scale
	local centre, cuff, wrist = DriverArms.HAND_CENTRE, DriverArms.CUFF_CENTRE, DriverArms.HAND_WRIST
	local forearm, back, bias = DriverArms.HAND_FOREARM, DriverArms.HAND_BACK, DriverArms.ELBOW_BIAS
	local overhang = DriverArms.CUFF_OVERHANG
	for _, side in driver.sides do
		local sign = side.sign
		local inset = Vector3.new(sign * DriverArms.SHOULDER_INSET * scale, 0, 0)
		local shoulder = torso:PointToWorldSpace(side.joint.C0.Position - inset)
		local wristAt = wheel:PointToWorldSpace(Vector3.new(sign * wrist.x, wrist.y, wrist.z))
		-- Toward where the elbow would be with the forearm straight down the hand's axis.
		local along = wheel:VectorToWorldSpace(Vector3.new(sign * forearm.x, forearm.y, forearm.z))
		local bendToward = (wristAt + along * lower - shoulder).Unit
			+ torso:VectorToWorldSpace(Vector3.new(sign * bias.out, -bias.down, bias.back))
		local handBack = wheel:VectorToWorldSpace(Vector3.new(sign * back.x, back.y, back.z))
		local upperFrame, lowerFrame = reach(shoulder, wristAt, bendToward, handBack, upper, lower)
		table.insert(parts, side.upper)
		table.insert(frames, upperFrame * CFrame.new(0, 0, -upper / 2))
		-- The forearm runs past the wrist by the cuff's overhang, over the hand's cut end.
		table.insert(parts, side.lower)
		table.insert(frames, lowerFrame * CFrame.new(0, 0, -(lower + overhang) / 2))
		table.insert(parts, side.elbow)
		table.insert(frames, CFrame.new(lowerFrame.Position))
		table.insert(parts, side.hand)
		table.insert(frames, wheel * CFrame.new(sign * centre.x, centre.y, centre.z))
		table.insert(parts, side.cuff)
		table.insert(frames, wheel * CFrame.new(sign * cuff.x, cuff.y, cuff.z))
	end
end

local function update()
	for _, model in CollectionService:GetTagged(CarRig.TAG) do
		if model:IsA("Model") and drivers[model] == nil then
			local character = seatedCharacter(model)
			local driver = character and build(model, character)
			if driver then
				drivers[model] = driver
			end
		end
	end
	table.clear(parts)
	table.clear(frames)
	for model, driver in drivers do
		if
			model.Parent == nil
			or seatedCharacter(model) ~= driver.character
			or driver.torso.Parent == nil
		then
			release(driver)
			drivers[model] = nil
		else
			pose(driver)
		end
	end
	if #parts > 0 then
		Workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

local Controller = {}

function Controller.start()
	local holder = Instance.new("Folder")
	holder.Name = "DriverArms"
	holder.Parent = Workspace
	folder = holder
	-- After the cameras; the parts' positions are this frame's whichever runs first.
	RunService:BindToRenderStep("DriverArms", Enum.RenderPriority.Camera.Value + 3, update)
end

return Controller
