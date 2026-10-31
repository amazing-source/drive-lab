--!strict
--[[
	The driver's arms. Once a character is seated in a car's driver seat (Rules/CarEntry's phase;
	getting in and out, the body animation moves the blocky arms), its blocky arms are hidden
	and custom ones drawn instead: the hands on the thighs while the engine is off, reaching
	for the START flap and onto the wheel after the start key (Rig/StartupHands), then on the
	steering wheel's rim at a quarter to three, turning with the wheel up to FOLLOW_LIMIT either
	way (past that the wheel slides through them), and an upper arm and a forearm reaching each
	wrist from the shoulder, the elbow bending down and out (Rules/ArmIK). In a car with hand
	gestures, the local driver's hand works the wheel's buttons and the panel's switches as the
	player presses them (Rig/WheelGestures).

	The hands are meshes posed around each car's rim (tools/blender/hand_grip.py), gloved or in
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
local Contract = require(ReplicatedStorage.Shared.Config.Cars.Contract)
local DriverArms = require(ReplicatedStorage.Shared.Config.DriverArms)
local Gloves = require(script.Parent.Parent.Rig.Gloves)
local StartupArms = require(ReplicatedStorage.Shared.Rules.StartupArms)
local StartupHands = require(script.Parent.Parent.Rig.StartupHands)
local WheelGestures = require(script.Parent.Parent.Rig.WheelGestures)
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
	-- The drawn arms' bone lengths in studs at this character's scale (Contract.armLengths).
	upperLength: number,
	lowerLength: number,
	sides: { Side },
	-- Whether the upper arms, elbows and forearms are drawn (Rules/ArmPieces).
	sleevesShown: boolean,
	-- The local driver's gestures in a car that has them, and by side whether that hand is on
	-- the wheel to make them.
	gestures: WheelGestures.State?,
	onWheel: { [number]: boolean },
}

local LIMBS: { { sign: number, joint: string, arm: string } } = {
	{ sign = 1, joint = "Right Shoulder", arm = "Right Arm" },
	{ sign = -1, joint = "Left Shoulder", arm = "Left Arm" },
}

local SLEEVE = Color3.fromRGB(DriverArms.SLEEVE_RGB[1], DriverArms.SLEEVE_RGB[2], DriverArms.SLEEVE_RGB[3])

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

-- A car's hand mesh from the folder its grip names, or the shared Hands folder's in a place that
-- lacks that car's own set.
local function handTemplate(meshes: string, name: string): BasePart?
	local assets = ReplicatedStorage:FindFirstChild("DriveLabAssets")
	local own = assets and assets:FindFirstChild(meshes)
	local found = own and own:FindFirstChild(name)
	if found and found:IsA("BasePart") then
		return found
	end
	return template("Hands", name)
end

local function sleeve(from: BasePart): BasePart
	local part = from:Clone()
	part.Color = SLEEVE
	part.Parent = folder
	return part
end

local function elbowBall(scale: number): BasePart
	local part = Instance.new("Part")
	part.Name = "Elbow"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * DriverArms.ELBOW_SIZE * scale
	part.Color = SLEEVE
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
	if driver.gestures then
		WheelGestures.release(driver.gestures)
	end
end

local function build(model: Model, character: Model): Driver?
	local torso = character:FindFirstChild("Torso")
	local chassis = model:FindFirstChild("Chassis")
	local seat = model:FindFirstChild("DriverSeat")
	local entry = Catalog.of(model)
	local wheel = chassis and entry and chassis:FindFirstChild(entry.model.steeringWheel)
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
		local meshes = entry.driver.grip.meshes
		local hand, cuff = handTemplate(meshes, "Hand_" .. letter), handTemplate(meshes, "Cuff_" .. letter)
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
	local upperLength, lowerLength = Contract.armLengths(entry)
	local sides = {}
	for _, limb in found do
		local joint, arm = limb.joint, limb.arm
		-- Each sleeve keeps its modelled cross-section and stretches to its bone's length.
		local upper = sleeve(upperSleeve)
		upper.Size = Vector3.new(upper.Size.X, upper.Size.Y, upperLength * scale)
		local lower = sleeve(lowerSleeve)
		lower.Size = Vector3.new(lower.Size.X, lower.Size.Y, lowerLength * scale + DriverArms.CUFF_OVERHANG)
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
			hands = StartupHands.build(entry.driver, limb.sign, hand, cuff, arm.Color, folder :: Folder),
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
		upperLength = upperLength * scale,
		lowerLength = lowerLength * scale,
		sides = sides,
		sleevesShown = true,
		gestures = if Players.LocalPlayer and character == Players.LocalPlayer.Character
			then WheelGestures.new(entry, model, chassis)
			else nil,
		onWheel = {},
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

-- How far the drawn arms are into the hand-over (CarEntry.handOverShare), nil when not drawn.
local function handOverShare(entry: Catalog.Entry, state: CarEntry.State, now: number): number?
	local handOver = entry.driver.handOver
	return CarEntry.handOverShare(entry, state, now, if handOver then handOver.seconds else nil)
end

local function pose(driver: Driver, state: CarEntry.State, now: number, share: number, dt: number)
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
	local upper, lower = driver.upperLength, driver.lowerLength
	local bias, overhang = DriverArms.ELBOW_BIAS, DriverArms.CUFF_OVERHANG
	-- The hands rest while the engine is off and reach through the start-up after the key.
	local sinceKey = if state.engine == "On" then now - state.engineAt else nil
	local handOver = driver.entry.driver.handOver
	local gestures = driver.gestures
	local onWheel = driver.onWheel
	if gestures then
		for _, side in driver.sides do
			onWheel[side.sign] = StartupArms.onWheel(side.hands.track, sinceKey, share)
		end
		WheelGestures.step(gestures, onWheel, now, dt)
		WheelGestures.turnControls(gestures)
	end
	for _, side in driver.sides do
		local sign = side.sign
		local inset = Vector3.new(sign * DriverArms.SHOULDER_INSET * scale, 0, 0)
		local shoulder = torso:PointToWorldSpace(side.joint.C0.Position - inset)
		local settle = if handOver and share < 1
			then { from = if sign > 0 then handOver.right else handOver.left, share = share }
			else nil
		local gestureWrist, shape = nil, "Grip"
		if gestures and onWheel[sign] then
			gestureWrist, shape =
				WheelGestures.wrist(gestures, sign, wheel, driver.seat.CFrame, side.hands.gripWrist)
		end
		local wrist, hand, handFrame, cuff, cuffFrame
		if gestureWrist then
			wrist, hand, handFrame, cuff, cuffFrame = StartupHands.draw(side.hands, gestureWrist, shape)
		else
			wrist, hand, handFrame, cuff, cuffFrame =
				StartupHands.place(side.hands, wheel, driver.seat.CFrame, sinceKey, settle)
		end
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

-- Only once seated (and, for a car with a hand-over, through its first moments of getting out):
-- getting in and out, the body animation moves the blocky arms.
local function seated(model: Model, now: number): boolean
	local entry = Catalog.of(model)
	return entry ~= nil and handOverShare(entry, CarState.read(model), now) ~= nil
end

local function update(dt: number)
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
		local share = handOverShare(driver.entry, state, now)
		if
			model.Parent == nil
			or seatedCharacter(model) ~= driver.character
			or driver.torso.Parent == nil
			or share == nil
		then
			release(driver)
			drivers[model] = nil
		else
			showSleeves(
				driver,
				ArmPieces.sleevesShown(view, driver.character == own, DriverArms.COCKPIT_GLOVES_ONLY)
			)
			pose(driver, state, now, share, dt)
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
