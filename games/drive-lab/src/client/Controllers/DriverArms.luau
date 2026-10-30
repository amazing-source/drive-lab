--!strict
--[[
	The driver's arms. Once a character is seated in a car's driver seat (Rules/CarEntry's phase;
	getting in and out, the body animation moves the blocky arms), its blocky arms are hidden
	and custom ones drawn instead: the hands on the thighs while the engine is off, reaching
	for the START flap and onto the wheel after the start key (Rig/StartupHands), then on the
	steering wheel's rim at a quarter to three, turning with the wheel up to FOLLOW_LIMIT either
	way (past that the wheel slides through them), and an upper arm and a forearm reaching each
	wrist from the shoulder, the elbow bending down and out (Rules/ArmIK).

	The hands are meshes posed around the SVJ's rim (tools/blender/hand_grip.py), gloved or in
	the avatar's skin colour (Rig/Gloves). The sleeves are modelled tubes
	(tools/blender/driver_sleeves.py) stretched to each bone, the forearm turned so its cuff lies
	flat with the hand, and a ball of the same cloth fills the elbow; in the cockpit view the
	local driver sees only the gloves (Rules/ArmPieces). All are kept in the place at
	ReplicatedStorage.DriveLabAssets. Every client draws every driver's arms: they are cosmetic,
	built locally and never replicated. A car's steering readout exists only on its driver's
	client, so other drivers' hands rest at the straight-ahead grip, as their wheels do here.
	Drawn after physics each frame from the parts' current positions, so the arms never trail a
	car at speed.
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Log = require(ReplicatedStorage.Kit.Log)

local ArmIK = require(ReplicatedStorage.Shared.Rules.ArmIK)
local ArmPieces = require(ReplicatedStorage.Shared.Rules.ArmPieces)
local CarEntry = require(ReplicatedStorage.Shared.Rules.CarEntry)
local CarRig = require(ReplicatedStorage.Shared.Car.CarRig)
local CarState = require(ReplicatedStorage.Shared.Car.CarState)
local Catalog = require(ReplicatedStorage.Shared.Config.Cars.Catalog)
local DriverArms = require(ReplicatedStorage.Shared.Config.DriverArms)
local Gloves = require(script.Parent.Parent.Rig.Gloves)
local StartupHands = require(script.Parent.Parent.Rig.StartupHands)
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
	hands: StartupHands.Hands,
}

type Driver = {
	entry: Catalog.Entry,
	character: Model,
	torso: BasePart,
	model: Model,
	chassis: BasePart,
	seat: BasePart,
	rest: CFrame,
	maxTurn: number,
	scale: number,
	sides: { Side },
	-- Whether the upper arms, elbows and forearms are drawn (Rules/ArmPieces).
	sleevesShown: boolean,
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
		StartupHands.release(side.hands)
		if side.arm.Parent then
			side.arm.Transparency = side.armTransparency
		end
	end
end

local function build(model: Model, character: Model): Driver?
	local torso = character:FindFirstChild("Torso")
	local chassis = model:FindFirstChild("Chassis")
	local seat = model:FindFirstChild("DriverSeat")
	local wheel = chassis and chassis:FindFirstChild("SteeringWheel")
	local entry = Catalog.of(model)
	if
		torso == nil
		or not torso:IsA("BasePart")
		or chassis == nil
		or not chassis:IsA("BasePart")
		or seat == nil
		or not seat:IsA("BasePart")
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
		local hand = Gloves.hand(limb.hand, arm.Color)
		hand.Parent = folder
		local cuff = Gloves.cuff(limb.cuff)
		cuff.Parent = folder
		table.insert(sides, {
			sign = limb.sign,
			joint = joint,
			arm = arm,
			armTransparency = arm.Transparency,
			upper = upper,
			lower = lower,
			elbow = elbowBall(scale),
			hand = hand,
			cuff = cuff,
			hands = StartupHands.build(
				entry.driver.startupPaths,
				limb.sign,
				hand,
				cuff,
				arm.Color,
				folder :: Folder
			),
		})
		arm.Transparency = 1
	end
	return {
		entry = entry,
		character = character,
		torso = torso,
		model = model,
		chassis = chassis,
		seat = seat,
		rest = rest,
		maxTurn = Steering.maxWheelAngle(entry.physics.steering),
		scale = scale,
		sides = sides,
		sleevesShown = true,
	}
end

local function showSleeves(driver: Driver, shown: boolean)
	if driver.sleevesShown == shown then
		return
	end
	driver.sleevesShown = shown
	local transparency = if shown then 0 else 1
	for _, side in driver.sides do
		side.upper.Transparency = transparency
		side.lower.Transparency = transparency
		side.elbow.Transparency = transparency
	end
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

local function pose(driver: Driver, state: CarEntry.State, now: number)
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
	local bias, overhang = DriverArms.ELBOW_BIAS, DriverArms.CUFF_OVERHANG
	-- The hands rest while the engine is off and reach through the start-up after the key.
	local sinceKey = if state.engine == "On" then now - state.engineAt else nil
	for _, side in driver.sides do
		local sign = side.sign
		local inset = Vector3.new(sign * DriverArms.SHOULDER_INSET * scale, 0, 0)
		local shoulder = torso:PointToWorldSpace(side.joint.C0.Position - inset)
		local wrist, hand, handFrame, cuff, cuffFrame =
			StartupHands.place(side.hands, wheel, driver.seat.CFrame, sinceKey)
		local wristAt = wrist.Position
		-- Toward where the elbow would be with the forearm straight down the hand's axis.
		local along = wrist.ZVector
		local bendToward = (wristAt + along * lower - shoulder).Unit
			+ torso:VectorToWorldSpace(Vector3.new(sign * bias.out, -bias.down, bias.back))
		local upperFrame, lowerFrame = reach(shoulder, wristAt, bendToward, wrist.YVector, upper, lower)
		table.insert(parts, side.upper)
		table.insert(frames, upperFrame * CFrame.new(0, 0, -upper / 2))
		-- The forearm runs past the wrist by the cuff's overhang, over the hand's cut end.
		table.insert(parts, side.lower)
		table.insert(frames, lowerFrame * CFrame.new(0, 0, -(lower + overhang) / 2))
		table.insert(parts, side.elbow)
		table.insert(frames, CFrame.new(lowerFrame.Position))
		table.insert(parts, hand)
		table.insert(frames, handFrame)
		table.insert(parts, cuff)
		table.insert(frames, cuffFrame)
	end
end

-- Only once seated: getting in and out, the body animation moves the blocky arms.
local function seated(model: Model, now: number): boolean
	local entry = Catalog.of(model)
	return entry ~= nil and CarEntry.phase(entry, CarState.read(model), now) == "Seated"
end

local function update()
	local now = Workspace:GetServerTimeNow()
	for _, model in CollectionService:GetTagged(CarRig.TAG) do
		if model:IsA("Model") and drivers[model] == nil then
			local character = seatedCharacter(model)
			if character and seated(model, now) then
				local driver = build(model, character)
				if driver then
					drivers[model] = driver
				end
			end
		end
	end
	table.clear(parts)
	table.clear(frames)
	local camera = Workspace.CurrentCamera
	local view = camera and camera:GetAttribute("DriveLabView")
	local own = Players.LocalPlayer and Players.LocalPlayer.Character
	for model, driver in drivers do
		local state = CarState.read(model)
		if
			model.Parent == nil
			or seatedCharacter(model) ~= driver.character
			or driver.torso.Parent == nil
			or CarEntry.phase(driver.entry, state, now) ~= "Seated"
		then
			release(driver)
			drivers[model] = nil
		else
			showSleeves(
				driver,
				ArmPieces.sleevesShown(view, driver.character == own, DriverArms.COCKPIT_GLOVES_ONLY)
			)
			pose(driver, state, now)
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
