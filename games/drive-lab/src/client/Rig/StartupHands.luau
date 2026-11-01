--!strict
--[[
	The driver's hands off the wheel: resting on the thighs while the engine is off, then the
	start-up's keyed reach (Rules/StartupArms) to the car's controls, and on to the wheel. Each
	side has the grip hand Controllers/DriverArms already draws plus the posed meshes, Rest, Point
	and Pinch (a key held between thumb and index), and a sleeve cuff for them, kept in the place
	at ReplicatedStorage.DriveLabAssets.Hands; one shows at a time, dressed as Rig/Gloves says. A
	place without the Pinch mesh draws the Point hand for it. The same set draws the car's gesture
	meshes on the wheel (Config/DriverGestures), each with the grip's cuff or the posed hands'; a
	gesture mesh the place lacks is drawn as the grip (a thumb or finger moved from it) or the
	Point hand.
	Everything is placed from a wrist frame (z up the forearm, y out of the back of the hand), the
	frame the arm reaches.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Contract = require(ReplicatedStorage.Shared.Config.Cars.Contract)
local DriverArms = require(ReplicatedStorage.Shared.Config.DriverArms)
local DriverGestures = require(ReplicatedStorage.Shared.Config.DriverGestures)
local DriverShift = require(ReplicatedStorage.Shared.Config.DriverShift)
local DriverStartup = require(ReplicatedStorage.Shared.Config.DriverStartup)
local Gloves = require(script.Parent.Gloves)
local HandShapes = require(ReplicatedStorage.Shared.Rules.HandShapes)
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
	-- The shift hand's Knob mesh, on a car with a gear lever whose shift data places it.
	knob: BasePart?,
	-- The car's gesture meshes for this side, by name, each with its frame in its wrist frame.
	posed: { [string]: { part: BasePart, offset: CFrame, cuff: "Grip" | "Wrist" } },
	-- What the place has of all these, for Rules/HandShapes; fixed once built.
	have: HandShapes.Have,
	shown: string,
	-- Fixed per side, worked out once: the grip's wrist frame in the wheel's frame, and each
	-- mesh's frame from its wrist frame.
	gripWrist: CFrame,
	gripOffset: CFrame,
	gripCuffOffset: CFrame,
	restOffset: CFrame,
	pointOffset: CFrame,
	pinchOffset: CFrame,
	knobOffset: CFrame,
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

-- A mesh frame from a gesture's { x, y, z, qw, qx, qy, qz } in metres.
local function meshFrame(key: { number }): CFrame
	local k = STUDS_PER_METRE
	return CFrame.new(key[1] * k, key[2] * k, key[3] * k, key[5], key[6], key[7], key[4])
end

-- The gesture meshes of one side the place has (their names end in _R or _L).
local function posedMeshes(
	gestures: DriverGestures.Gestures?,
	letter: string,
	color: Color3,
	folder: Instance
): { [string]: { part: BasePart, offset: CFrame, cuff: "Grip" | "Wrist" } }
	local found = {}
	if gestures == nil then
		return found
	end
	for name, mesh in gestures.MESHES do
		local template = if string.sub(name, -2) == "_" .. letter then asset(name) else nil
		if template then
			found[name] = {
				part = hidden(Gloves.hand(template, color), folder),
				offset = meshFrame(mesh.frame),
				cuff = mesh.cuff,
			}
		end
	end
	return found
end

local function have(hands: Hands): HandShapes.Have
	local shapes = hands.shapes
	local gestures: { [string]: HandShapes.Cuff } = {}
	for name, mesh in hands.posed do
		gestures[name] = mesh.cuff
	end
	local pinch: BasePart? = if shapes then shapes[PINCH] else nil
	return {
		startupShapes = shapes ~= nil,
		pinch = pinch ~= nil,
		knob = hands.knob ~= nil,
		gestures = gestures,
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
	local knob = asset(`{DriverShift.KNOB_MESH}_{letter}`)
	local paths = driver.startupPaths
	local shift = driver.shift
	local knobMesh = if shift then shift.mesh else nil
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
		posed = posedMeshes(driver.gestures, letter, color, folder),
		have = { startupShapes = false, pinch = false, gestures = {} },
		shown = "Grip",
		gripWrist = gripWrist,
		gripOffset = fromWrist * CFrame.new(sign * centre.x, centre.y, centre.z),
		gripCuffOffset = fromWrist * CFrame.new(sign * cuffCentre.x, cuffCentre.y, cuffCentre.z),
		restOffset = offset(paths.MESHES.Rest),
		pointOffset = offset(paths.MESHES.Point),
		pinchOffset = offset(paths.MESHES.Pinch or paths.MESHES.Point),
		knobOffset = offset(knobMesh or paths.MESHES.Rest),
		cuffOffset = offset(paths.CUFF),
	}
	if rest and point and cuff then
		local shapes: { [DriverStartup.Shape]: BasePart } = {}
		shapes[REST] = hidden(Gloves.hand(rest, color), folder)
		shapes[POINT] = hidden(Gloves.hand(point, color), folder)
		if pinch and paths.MESHES.Pinch then
			shapes[PINCH] = hidden(Gloves.hand(pinch, color), folder)
		end
		if knob and knobMesh then
			hands.knob = hidden(Gloves.hand(knob, color), folder)
		end
		hands.shapes = shapes
		hands.cuff = hidden(Gloves.cuff(cuff), folder)
	end
	hands.have = have(hands)
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
	if hands.knob then
		hands.knob:Destroy()
	end
	for _, mesh in hands.posed do
		mesh.part:Destroy()
	end
end

local function show(hands: Hands, shown: HandShapes.Shown)
	if hands.shown == shown.shape then
		return
	end
	hands.shown = shown.shape
	hands.grip.Transparency = if shown.grip then 0 else 1
	hands.gripCuff.Transparency = if shown.gripCuff then 0 else 1
	local shapes, cuff = hands.shapes, hands.cuff
	if shapes then
		for name, part in shapes do
			part.Transparency = if name == shown.mesh then 0 else 1
		end
	end
	if cuff then
		cuff.Transparency = if shown.wristCuff then 0 else 1
	end
	local knob = hands.knob
	if knob then
		knob.Transparency = if shown.mesh == "Knob" then 0 else 1
	end
	for name, mesh in hands.posed do
		mesh.part.Transparency = if name == shown.mesh then 0 else 1
	end
end

-- Shows `shape` at the wrist frame `wrist` and returns the hand and cuff to draw with their frames.
function StartupHands.draw(
	hands: Hands,
	wrist: CFrame,
	shape: string
): (CFrame, BasePart, CFrame, BasePart, CFrame)
	local shown = HandShapes.shown(shape, hands.have)
	show(hands, shown)
	local hand, handFrame = hands.grip, wrist * hands.gripOffset
	local gesture = hands.posed[shown.shape]
	local shapes = hands.shapes
	local knob = hands.knob
	if gesture then
		hand, handFrame = gesture.part, wrist * gesture.offset
	elseif shown.mesh == "Knob" and knob then
		hand, handFrame = knob, wrist * hands.knobOffset
	elseif shown.mesh and shapes then
		local offset = if shown.shape == REST
			then hands.restOffset
			elseif shown.shape == PINCH then hands.pinchOffset
			else hands.pointOffset
		hand, handFrame = shapes[shown.shape :: DriverStartup.Shape], wrist * offset
	end
	local cuff = hands.cuff
	if shown.wristCuff and cuff then
		return wrist, hand, handFrame, cuff, wrist * hands.cuffOffset
	end
	return wrist, hand, handFrame, hands.gripCuff, wrist * hands.gripCuffOffset
end

-- The side's grip on the wheel `wheel` (turned as the arms follow it) in the seat frame `seat`.
function StartupHands.gripPose(hands: Hands, wheel: CFrame, seat: CFrame): StartupArms.Pose
	return toPose(seat:ToObjectSpace(wheel * hands.gripWrist))
end

-- Shows `shape` at the wrist `pose` (seat frame `seat`), as StartupHands.draw.
function StartupHands.drawPose(
	hands: Hands,
	seat: CFrame,
	pose: StartupArms.Pose,
	shape: string
): (CFrame, BasePart, CFrame, BasePart, CFrame)
	return StartupHands.draw(hands, seat * toCFrame(pose), shape)
end

-- The wrist frame for one side, and the hand and cuff to draw with their frames. `wheel` is the
-- steering wheel's frame turned as the arms follow it; `sinceKey` is nil with the engine off.
function StartupHands.place(
	hands: Hands,
	wheel: CFrame,
	seat: CFrame,
	sinceKey: number?,
	settle: { from: StartupArms.Pose, share: number }?
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
		if settle then
			pose = StartupArms.settle(settle.from, pose, settle.share)
		end
		wrist = seat * toCFrame(pose)
		shape = hand.shape
	end
	return StartupHands.draw(hands, wrist, shape)
end

return StartupHands
