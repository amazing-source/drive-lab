--!strict
--[[
	The driver's legs. Once a character is seated in a car's driver seat (Rules/CarEntry's phase),
	its blocky legs are hidden and real-length ones drawn: the trousers' seat filling the room
	between the R6 torso and the cushion, trouser sleeves from each hip to the knee and on to
	the ankle, a cloth ball in the knee, and shoes on the pedals (Rules/DriverLegs):
	the right foot on the throttle, over on the brake while it is pressed, holding the brake
	through the start-up; the left on the footrest. The pedals turn with them, where the rig has
	hinged them (Car/CarRig).

	Every client draws every driver's legs; they are cosmetic, built locally and never
	replicated. Throttle and Brake readouts exist only on a car's driver's client, so on other
	drivers' cars the right foot rests on the throttle, pressing only through the start-up,
	which every client derives from the car's replicated state. Drawn after physics each frame,
	in one BulkMoveTo, like the arms.
]]
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Log = require(ReplicatedStorage.Kit.Log)

local CarEntry = require(ReplicatedStorage.Shared.Rules.CarEntry)
local CarRig = require(ReplicatedStorage.Shared.Car.CarRig)
local CarState = require(ReplicatedStorage.Shared.Car.CarState)
local Catalog = require(ReplicatedStorage.Shared.Config.Cars.Catalog)
local DriverLegs = require(ReplicatedStorage.Shared.Config.DriverLegs)
local Legs = require(ReplicatedStorage.Shared.Rules.DriverLegs)
local Units = require(ReplicatedStorage.Shared.Units)

type Side = {
	-- +1 for the right leg, -1 for the left.
	sign: number,
	leg: BasePart,
	legTransparency: number,
	thigh: BasePart,
	shin: BasePart,
	knee: BasePart,
	shoe: BasePart,
}

type Pedal = { weld: Weld, rest: CFrame, angle: number }

type Driver = {
	entry: Catalog.Entry,
	character: Model,
	torso: BasePart,
	model: Model,
	seat: BasePart,
	scale: number,
	sides: { Side },
	-- The trousers' seat under the torso.
	pelvis: BasePart,
	-- 0 with the right foot on the throttle, 1 on the brake.
	over: number,
	throttle: Pedal?,
	brake: Pedal?,
}

local LIMBS: { { sign: number, leg: string, shoe: string } } = {
	{ sign = 1, leg = "Right Leg", shoe = "Shoe_R" },
	{ sign = -1, leg = "Left Leg", shoe = "Shoe_L" },
}
local STUDS_PER_METRE = 1 / Units.METRES_PER_STUD

local log = Log.scope("DriverLegs")
local folder: Folder? = nil
local warned = false
local drivers: { [Model]: Driver } = {}
local parts: { BasePart } = {}
local frames: { CFrame } = {}
local trouser =
	Color3.fromRGB(DriverLegs.TROUSER_RGB[1], DriverLegs.TROUSER_RGB[2], DriverLegs.TROUSER_RGB[3])

local function template(name: string): BasePart?
	local assets = ReplicatedStorage:FindFirstChild("DriveLabAssets")
	local holder = assets and assets:FindFirstChild("Legs")
	local found = holder and holder:FindFirstChild(name)
	if found and found:IsA("BasePart") then
		return found
	end
	if not warned then
		warned = true
		log.warn(`ReplicatedStorage.DriveLabAssets.Legs.{name} is missing; the legs stay blocky`)
	end
	return nil
end

local function cloth(from: BasePart, length: number?): BasePart
	local part = from:Clone()
	part.Color = trouser
	if length then
		part.Size = Vector3.new(part.Size.X, part.Size.Y, length)
	end
	part.Parent = folder
	return part
end

local function kneeBall(): BasePart
	local part = Instance.new("Part")
	part.Name = "Knee"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * DriverLegs.KNEE_SIZE * STUDS_PER_METRE
	part.Color = trouser
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

-- A pedal the rig hung on a hinge; nil on a car whose pedals are still part of its cabin mesh.
local function hinged(model: Model, name: string): Pedal?
	local chassis = model:FindFirstChild("Chassis")
	local weld = chassis and chassis:FindFirstChild(name)
	local rest = weld and weld:GetAttribute("RestC0")
	if weld == nil or not weld:IsA("Weld") or typeof(rest) ~= "CFrame" then
		return nil
	end
	return { weld = weld, rest = rest, angle = 0 }
end

local function turn(pedal: Pedal?, angle: number)
	if pedal == nil or math.abs(pedal.angle - angle) < 1e-4 then
		return
	end
	pedal.angle = angle
	pedal.weld.C0 = pedal.rest * CFrame.Angles(angle, 0, 0)
end

local function release(driver: Driver)
	for _, side in driver.sides do
		side.thigh:Destroy()
		side.shin:Destroy()
		side.knee:Destroy()
		side.shoe:Destroy()
		if side.leg.Parent then
			side.leg.Transparency = side.legTransparency
		end
	end
	driver.pelvis:Destroy()
	turn(driver.throttle, 0)
	turn(driver.brake, 0)
end

local function build(model: Model, entry: Catalog.Entry, character: Model): Driver?
	local torso = character:FindFirstChild("Torso")
	local seat = model:FindFirstChild("DriverSeat")
	if torso == nil or not torso:IsA("BasePart") or seat == nil or not seat:IsA("BasePart") then
		return nil
	end
	-- Everything found before anything is made or hidden, so a missing piece leaves no trace.
	local thigh, shin, pelvis = template("Thigh"), template("Shin"), template("Pelvis")
	if thigh == nil or shin == nil or pelvis == nil then
		return nil
	end
	local found: { { sign: number, leg: BasePart, shoe: BasePart } } = {}
	for _, limb in LIMBS do
		local leg = character:FindFirstChild(limb.leg)
		local shoe = template(limb.shoe)
		if leg == nil or not leg:IsA("BasePart") or shoe == nil then
			return nil
		end
		table.insert(found, { sign = limb.sign, leg = leg, shoe = shoe })
	end
	local sides = {}
	for _, limb in found do
		local shoe = limb.shoe:Clone()
		shoe.Parent = folder
		table.insert(sides, {
			sign = limb.sign,
			leg = limb.leg,
			legTransparency = limb.leg.Transparency,
			-- Each sleeve keeps its modelled cross-section and stretches to its bone.
			thigh = cloth(thigh, DriverLegs.THIGH * STUDS_PER_METRE),
			shin = cloth(shin, (DriverLegs.SHIN + DriverLegs.HEM_OVERHANG) * STUDS_PER_METRE),
			knee = kneeBall(),
			shoe = shoe,
		})
		limb.leg.Transparency = 1
	end
	return {
		entry = entry,
		character = character,
		torso = torso,
		model = model,
		seat = seat,
		scale = character:GetScale(),
		sides = sides,
		pelvis = cloth(pelvis),
		over = 0,
		throttle = hinged(model, DriverLegs.THROTTLE.part),
		brake = hinged(model, DriverLegs.BRAKE.part),
	}
end

local function readout(model: Model, name: string): number
	local value = model:GetAttribute(name)
	return if typeof(value) == "number" and value == value then value else 0
end

local function world(seat: CFrame, point: Legs.Vector): Vector3
	return seat:PointToWorldSpace(Vector3.new(point.x, point.y, point.z) * STUDS_PER_METRE)
end

local function draw(side: Side, seat: CFrame, leg: Legs.Leg)
	local hip, knee, ankle = world(seat, leg.hip), world(seat, leg.knee), world(seat, leg.ankle)
	local up = seat.UpVector
	table.insert(parts, side.thigh)
	table.insert(frames, CFrame.lookAt(hip, knee, up) * CFrame.new(0, 0, -side.thigh.Size.Z / 2))
	-- The shin's sleeve runs past the ankle by the hem's overhang, over the shoe's collar.
	table.insert(parts, side.shin)
	table.insert(frames, CFrame.lookAt(knee, ankle, up) * CFrame.new(0, 0, -side.shin.Size.Z / 2))
	table.insert(parts, side.knee)
	table.insert(frames, CFrame.new(knee))
	local forward = seat:VectorToWorldSpace(Vector3.new(leg.forward.x, leg.forward.y, leg.forward.z))
	local instep = seat:VectorToWorldSpace(Vector3.new(leg.up.x, leg.up.y, leg.up.z))
	local shoe = DriverLegs.SHOE_CENTRE
	table.insert(parts, side.shoe)
	table.insert(
		frames,
		CFrame.fromMatrix(ankle, instep:Cross(-forward), instep, -forward)
			* CFrame.new(Vector3.new(side.sign * shoe.x, shoe.y, shoe.z) * STUDS_PER_METRE)
	)
end

local function pose(driver: Driver, state: CarEntry.State, now: number, dt: number)
	local model = driver.model
	local throttle, brake = readout(model, "Throttle"), readout(model, "Brake")
	local held = CarEntry.startupBrake(driver.entry, state, now)
	if held then
		throttle, brake = 0, math.max(brake, held)
	end
	driver.over = Legs.approach(driver.over, Legs.wantsBrake(brake), dt)
	local throttleAngle, brakeAngle = Legs.pedalAngles(driver.over, throttle, brake)
	turn(driver.throttle, throttleAngle)
	turn(driver.brake, brakeAngle)
	local seat = driver.seat.CFrame
	local hip, centre = DriverLegs.HIP, DriverLegs.PELVIS_CENTRE
	table.insert(parts, driver.pelvis)
	table.insert(
		frames,
		driver.torso.CFrame * CFrame.new(Vector3.new(centre.x, centre.y, centre.z) * driver.scale)
	)
	for _, side in driver.sides do
		local at = seat:PointToObjectSpace(
			driver.torso.CFrame:PointToWorldSpace(Vector3.new(side.sign * hip.x, hip.y, hip.z) * driver.scale)
		) / STUDS_PER_METRE
		local hipPoint = { x = at.X, y = at.Y, z = at.Z }
		local leg = if side.sign > 0
			then Legs.right(hipPoint, driver.over, throttleAngle, brakeAngle)
			else Legs.left(hipPoint)
		draw(side, seat, leg)
	end
end

local function update(dt: number)
	local now = Workspace:GetServerTimeNow()
	for _, model in CollectionService:GetTagged(CarRig.TAG) do
		if model:IsA("Model") and drivers[model] == nil then
			local character = seatedCharacter(model)
			local entry = Catalog.of(model)
			if character and entry and CarEntry.phase(entry, CarState.read(model), now) == "Seated" then
				local driver = build(model, entry, character)
				if driver then
					drivers[model] = driver
				end
			end
		end
	end
	table.clear(parts)
	table.clear(frames)
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
			pose(driver, state, now, dt)
		end
	end
	if #parts > 0 then
		Workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

local Controller = {}

function Controller.start()
	local holder = Instance.new("Folder")
	holder.Name = "DriverLegs"
	holder.Parent = Workspace
	folder = holder
	-- With the arms, after the cameras.
	RunService:BindToRenderStep("DriverLegs", Enum.RenderPriority.Camera.Value + 3, update)
end

return Controller
