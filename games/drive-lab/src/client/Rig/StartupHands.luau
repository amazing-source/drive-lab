--!strict
--[[
	The driver's hands off the wheel: resting on the thighs while the engine is off, then the
	start-up's keyed reach (Rules/StartupArms) to the car's controls, and on to the wheel. Each
	side has the grip hand Controllers/DriverArms already draws plus the posed meshes, Rest, Point
	and Pinch (a key held between thumb and index), and a sleeve cuff for them, kept in the place
	at ReplicatedStorage.DriveLabAssets.Hands; one shows at a time, dressed as Rig/Gloves says. A
	place without the Pinch mesh draws the Point hand for it.
	Everything is placed from a wrist frame (z up the forearm, y out of the back of the hand), the
	frame the arm reaches.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Contract = require(ReplicatedStorage.Shared.Config.Cars.Contract)
local DriverArms = require(ReplicatedStorage.Shared.Config.DriverArms)
local DriverStartup = require(ReplicatedStorage.Shared.Config.DriverStartup)
local Gloves = require(script.Parent.Gloves)
local StartupArms = require(ReplicatedStorage.Shared.Rules.StartupArms)
local Units = require(ReplicatedStorage.Shared.Units)

export type Hands = {
	sign: number,
	track: DriverStartup.Track,
	grip: BasePart,
	gripCuff: BasePart,
	-- nil when the place lacks the posed meshes: the grip hand then stands in for them.
	shapes: { [DriverStartup.Shape]: BasePart }?,
	cuff: BasePart?,
	shown: DriverStartup.Shape,
	-- Fixed per side, worked out once: the grip's wrist frame in the wheel's frame, and each
	-- mesh's frame from its wrist frame.
	gripWrist: CFrame,
	gripOffset: CFrame,
	gripCuffOffset: CFrame,
	restOffset: CFrame,
	pointOffset: CFrame,
	pinchOffset: CFrame,
	cuffOffset: CFrame,
}

local STUDS_PER_METRE = 1 / Units.METRES_PER_STUD
local REST: DriverStartup.Shape, POINT: DriverStartup.Shape, PINCH: DriverStartup.Shape =
	"Rest", "Point", "Pinch"

local StartupHands = {}

local function asset(name: string): BasePart?
	local assets = ReplicatedStorage:FindFirstChild("DriveLabAssets")
	local holder = assets and assets:FindFirstChild("Hands")
	local found = holder and holder:FindFirstChild(name)
	return if found and found:IsA("BasePart") then found else nil
end

local function hidden(part: BasePart, folder: Instance): BasePart
	part.Transparency = 1
	part.Parent = folder
	return part
end

-- The grip hand's wrist frame in the steering wheel's frame (the car's grip, the left hand
-- mirrored).
function StartupHands.gripWrist(grip: DriverArms.Grip, sign: number): CFrame
	local wrist, forearm, back = grip.wrist, grip.forearm, grip.back
	local z = Vector3.new(sign * forearm.x, forearm.y, forearm.z).Unit
	local up = Vector3.new(sign * back.x, back.y, back.z)
	local y = (up - z * up:Dot(z)).Unit
	return CFrame.fromMatrix(Vector3.new(sign * wrist.x, wrist.y, wrist.z), y:Cross(z), y, z)
end

-- Poses are metres in the seat frame; the world is in studs.
local function toCFrame(pose: StartupArms.Pose): CFrame
	local p, q = pose.position, pose.rotation
	local k = STUDS_PER_METRE
	return CFrame.new(p.x * k, p.y * k, p.z * k, q.x, q.y, q.z, q.w)
end

local function toPose(frame: CFrame): StartupArms.Pose
	local axis, angle = frame:ToAxisAngle()
	local sine = math.sin(angle / 2)
	local p = frame.Position / STUDS_PER_METRE
	return {
		position = { x = p.X, y = p.Y, z = p.Z },
		rotation = { w = math.cos(angle / 2), x = axis.X * sine, y = axis.Y * sine, z = axis.Z * sine },
	}
end

function StartupHands.build(
	driver: Contract.Driver,
	sign: number,
	grip: BasePart,
	gripCuff: BasePart,
	color: Color3,
	folder: Instance
): Hands
	local letter = if sign > 0 then "R" else "L"
	local rest, point, cuff =
		asset("HandRest_" .. letter), asset("HandPoint_" .. letter), asset("WristCuff_" .. letter)
	local pinch = asset("HandPinch_" .. letter)
	local paths = driver.startupPaths
	local gripWrist = StartupHands.gripWrist(driver.grip, sign)
	local fromWrist = gripWrist:Inverse()
	local centre, cuffCentre = driver.grip.centre, driver.grip.cuff
	local function offset(centreOf: DriverStartup.Point): CFrame
		return CFrame.new(Vector3.new(sign * centreOf.x, centreOf.y, centreOf.z) * STUDS_PER_METRE)
	end
	local hands: Hands = {
		sign = sign,
		track = if sign > 0 then paths.RIGHT else paths.LEFT,
		grip = grip,
		gripCuff = gripCuff,
		shapes = nil,
		cuff = nil,
		shown = "Grip",
		gripWrist = gripWrist,
		gripOffset = fromWrist * CFrame.new(sign * centre.x, centre.y, centre.z),
		gripCuffOffset = fromWrist * CFrame.new(sign * cuffCentre.x, cuffCentre.y, cuffCentre.z),
		restOffset = offset(paths.MESHES.Rest),
		pointOffset = offset(paths.MESHES.Point),
		pinchOffset = offset(paths.MESHES.Pinch or paths.MESHES.Point),
		cuffOffset = offset(paths.CUFF),
	}
	if rest and point and cuff then
		local shapes: { [DriverStartup.Shape]: BasePart } = {}
		shapes[REST] = hidden(Gloves.hand(rest, color), folder)
		shapes[POINT] = hidden(Gloves.hand(point, color), folder)
		if pinch and paths.MESHES.Pinch then
			shapes[PINCH] = hidden(Gloves.hand(pinch, color), folder)
		end
		hands.shapes = shapes
		hands.cuff = hidden(Gloves.cuff(cuff), folder)
	end
	return hands
end

function StartupHands.release(hands: Hands)
	if hands.shapes then
		for _, part in hands.shapes do
			part:Destroy()
		end
	end
	if hands.cuff then
		hands.cuff:Destroy()
	end
end

-- The shape a hand is drawn with: the Point hand stands in for a Pinch the place lacks.
local function drawn(hands: Hands, shape: DriverStartup.Shape): DriverStartup.Shape
	if shape ~= PINCH then
		return shape
	end
	local shapes = hands.shapes
	local mesh: BasePart? = if shapes then shapes[PINCH] else nil
	return if mesh then shape else POINT
end

local function show(hands: Hands, shape: DriverStartup.Shape)
	if hands.shown == shape then
		return
	end
	hands.shown = shape
	local shapes, cuff = hands.shapes, hands.cuff
	local posed = shapes ~= nil and shape ~= "Grip"
	hands.grip.Transparency = if posed then 1 else 0
	hands.gripCuff.Transparency = if posed then 1 else 0
	if shapes and cuff then
		for name, part in shapes do
			part.Transparency = if name == shape then 0 else 1
		end
		cuff.Transparency = if posed then 0 else 1
	end
end

-- The wrist frame for one side, and the hand and cuff to draw with their frames. `wheel` is the
-- steering wheel's frame turned as the arms follow it; `sinceKey` is nil with the engine off.
function StartupHands.place(
	hands: Hands,
	wheel: CFrame,
	seat: CFrame,
	sinceKey: number?
): (CFrame, BasePart, CFrame, BasePart, CFrame)
	local gripFrame = wheel * hands.gripWrist
	local hand = StartupArms.hand(hands.track, sinceKey)
	local wrist = gripFrame
	local shape: DriverStartup.Shape = "Grip"
	if hand then
		local pose = hand.pose
		if hand.toGrip > 0 then
			local live = toPose(seat:ToObjectSpace(gripFrame))
			pose = StartupArms.retarget(pose, StartupArms.finalPose(hands.track), live, hand.toGrip)
		end
		wrist = seat * toCFrame(pose)
		shape = hand.shape
	end
	shape = drawn(hands, shape)
	show(hands, shape)
	local shapes, cuff = hands.shapes, hands.cuff
	if shape == "Grip" or shapes == nil or cuff == nil then
		return wrist, hands.grip, wrist * hands.gripOffset, hands.gripCuff, wrist * hands.gripCuffOffset
	end
	local offset = if shape == "Rest"
		then hands.restOffset
		elseif shape == "Pinch" then hands.pinchOffset
		else hands.pointOffset
	return wrist, shapes[shape], wrist * offset, cuff, wrist * hands.cuffOffset
end

return StartupHands
