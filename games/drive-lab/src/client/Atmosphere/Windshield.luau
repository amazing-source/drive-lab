--!strict
--[[
	Water on the windscreen of the car the camera is in, in the cockpit view only (the lens drops
	cover the other views). Drops live in the pane's plane (Rules/WindshieldDrops) and are drawn
	by a SurfaceGui on a thin part of this module's own, just inside the glass and moved with the
	car every frame: the depth test keeps the dashboard, the wheel and the arms in front of
	them, and they stay on the glass however the head turns. The car's model is only read.

	No wipers are modelled. Windshield.wipe takes the blades' swept region as a test over pane
	coordinates (metres, x right from the pane's left edge, y down from its top) and fades the
	drops in it: the hook for whoever adds wipers to the car.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Catalog = require(ReplicatedStorage.Shared.Config.Cars.Catalog)
local Config = require(ReplicatedStorage.Shared.Config.Atmosphere)
local RainDensity = require(script.Parent.RainDensity)
local Units = require(ReplicatedStorage.Shared.Units)
local WindshieldDrops = require(ReplicatedStorage.Shared.Rules.WindshieldDrops)

type Slot = { label: ImageLabel, drop: WindshieldDrops.Drop?, trail: boolean, wiped: boolean }
-- The pane of one car, and where its part sits from the car's mass box.
type Mount = { model: Model, chassis: BasePart, pane: WindshieldDrops.Pane, offset: CFrame }

export type Windshield = {
	folder: Folder,
	part: Part,
	gui: SurfaceGui,
	slots: { Slot },
	carry: number,
	mount: Mount?,
	random: Random,
}

local SHIELD = Config.WINDSHIELD

local function largestPool(): number
	local count = 0
	for _, budget in Config.BUDGETS do
		count = math.max(count, budget.lensDrops)
	end
	return count
end

-- A binding corner, metres from the centre of mass in the car frame, as a point in the mass
-- box's own frame (X right, Y up, Z back), still in metres; the body sits bodyRaise higher.
local function carPoint(
	corner: { forward: number, right: number, up: number },
	raise: number
): WindshieldDrops.Vector
	return { x = corner.right, y = corner.up + raise, z = -corner.forward }
end

local function vector(value: WindshieldDrops.Vector): Vector3
	return Vector3.new(value.x, value.y, value.z)
end

local function mountFor(model: Model): Mount?
	local name = model:GetAttribute("Car")
	local entry = if typeof(name) == "string" then Catalog[name] else nil
	local chassis = model.PrimaryPart
	if entry == nil or chassis == nil then
		return nil
	end
	local binding = entry.model
	local corners = {}
	for index, corner in binding.windshield do
		corners[index] = carPoint(corner, binding.bodyRaise)
	end
	local pane = WindshieldDrops.pane(corners, { x = 0, y = 0, z = 1 })
	local right, up = vector(pane.right), -vector(pane.down)
	local centre = vector(pane.centre) + vector(pane.normal) * SHIELD.inset
	local offset = CFrame.fromMatrix(centre * Units.metresToStuds(1), right, up)
	return { model = model, chassis = chassis, pane = pane, offset = offset }
end

local function place(shield: Windshield, mount: Mount)
	local pane = mount.pane
	shield.part.Size = Vector3.new(Units.metresToStuds(pane.width), Units.metresToStuds(pane.height), 0.02)
	-- The face toward the driver: +Z of the part points to the back of the car or to the front.
	shield.gui.Face = if mount.offset.LookVector.Z > 0 then Enum.NormalId.Front else Enum.NormalId.Back
end

local function hide(shield: Windshield)
	shield.gui.Enabled = false
	for _, slot in shield.slots do
		slot.drop = nil
		slot.label.Visible = false
	end
end

-- A new drop in a free slot, somewhere its whole sprite (the square canvas, not only what shows
-- of it) lies inside the windscreen; none if four tries find no such place.
local function land(shield: Windshield, slot: Slot, pane: WindshieldDrops.Pane)
	local random = shield.random
	local trail = random:NextNumber() < SHIELD.drops.sliding
	local sprite = if trail then SHIELD.trail else SHIELD.bead
	local size = random:NextNumber(sprite.width[1], sprite.width[2]) / sprite.across
	local reach = size / 2
	for _ = 1, 4 do
		local x, y = random:NextNumber(0, pane.width), random:NextNumber(0, pane.height)
		if WindshieldDrops.inside(pane.polygon, x, y, reach) then
			local tuning = SHIELD.drops
			slot.drop = {
				x = x,
				y = y,
				radius = reach,
				slides = trail,
				cling = random:NextNumber(tuning.cling[1], tuning.cling[2]),
				speed = 0,
				age = 0,
				life = random:NextNumber(tuning.life[1], tuning.life[2]),
			}
			slot.trail, slot.wiped = trail, false
			local label = slot.label
			label.Image = sprite.image
			label.Size = UDim2.fromScale(size / pane.width, size / pane.height)
			label.Rotation = 0
			label.Visible = true
			return
		end
	end
end

local function draw(slot: Slot, pane: WindshieldDrops.Pane)
	local drop = slot.drop
	if drop == nil then
		return
	end
	local label = slot.label
	local opacity = WindshieldDrops.opacity(drop, SHIELD.drops) * (if slot.wiped then 0.2 else 1)
	label.ImageTransparency = 1 - SHIELD.opacity * opacity
	-- A sliding drop's bead leads: below its trail going down, above it when the air drives
	-- it up the glass.
	local upward = slot.trail and drop.speed < 0
	label.Rotation = if upward then 180 else 0
	local bead = if slot.trail then SHIELD.trail.bead else SHIELD.bead.bead
	label.AnchorPoint = Vector2.new(0.5, if upward then 1 - bead else bead)
	label.Position = UDim2.fromScale(drop.x / pane.width, drop.y / pane.height)
end

local Windshield = {}

function Windshield.new(): Windshield
	local folder = Instance.new("Folder")
	folder.Name = "DriveLabWindshield"
	local part = Instance.new("Part")
	part.Name = "Drops"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.one
	part.Parent = folder
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Drops"
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = SHIELD.pixelsPerStud
	gui.LightInfluence = SHIELD.lightInfluence
	gui.AlwaysOnTop = false
	gui.ClipsDescendants = true
	gui.Enabled = false
	gui.Adornee = part
	gui.Parent = part
	local slots: { Slot } = {}
	for index = 1, largestPool() do
		local label = Instance.new("ImageLabel")
		label.Name = `Drop{index}`
		label.BackgroundTransparency = 1
		label.ImageTransparency = 1
		label.Visible = false
		label.Parent = gui
		table.insert(slots, { label = label, drop = nil, trail = false, wiped = false })
	end
	folder.Parent = Workspace
	return {
		folder = folder,
		part = part,
		gui = gui,
		slots = slots,
		carry = 0,
		mount = nil,
		random = Random.new(),
	}
end

-- One frame: in the cockpit view of `model`, drops land, cling, slide and fade; anywhere else
-- the glass is cleared. `cap` is the most drops at once (the tier's lens budget).
function Windshield.update(
	shield: Windshield,
	dt: number,
	cockpit: boolean,
	model: Model?,
	intensity: number,
	exposure: number,
	speedKmh: number,
	cap: number
)
	if not cockpit or model == nil or model.Parent == nil then
		if shield.gui.Enabled then
			hide(shield)
		end
		shield.mount = nil
		return
	end
	if shield.mount == nil or (shield.mount :: Mount).model ~= model then
		local fresh = mountFor(model)
		shield.mount = fresh
		if fresh == nil then
			hide(shield)
			return
		end
		place(shield, fresh)
	end
	local mount = shield.mount :: Mount
	shield.part.CFrame = mount.chassis.CFrame * mount.offset
	shield.gui.Enabled = true
	local pane, tuning = mount.pane, SHIELD.drops
	local due
	due, shield.carry = RainDensity.accumulate(
		shield.carry,
		WindshieldDrops.landing(intensity, exposure, speedKmh, tuning),
		dt,
		2
	)
	local pull = WindshieldDrops.pull(speedKmh, tuning)
	for index, slot in shield.slots do
		local drop = slot.drop
		if drop and not WindshieldDrops.step(drop, dt, pull, pane.height, tuning) then
			slot.drop = nil
			slot.label.Visible = false
		elseif drop == nil and due > 0 and index <= cap then
			due -= 1
			land(shield, slot, pane)
		end
		draw(slot, pane)
	end
end

-- Fades the drops whose centre `swept` covers, for a wiper's pass.
function Windshield.wipe(shield: Windshield, swept: (x: number, y: number) -> boolean)
	for _, slot in shield.slots do
		local drop = slot.drop
		if drop and swept(drop.x, drop.y) then
			slot.wiped = true
			drop.life = math.min(drop.life, drop.age + SHIELD.wipeSeconds)
		end
	end
end

function Windshield.destroy(shield: Windshield)
	shield.folder:Destroy()
end

return Windshield
