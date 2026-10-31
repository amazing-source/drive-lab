--!strict
--[[
	Water on the windscreen of the car the camera is in, in the cockpit view only (the lens drops
	cover the other views). Drops live in the pane's plane (Rules/WindshieldDrops) and are drawn
	by a SurfaceGui on a thin part of this module's own, just inside the glass and moved with the
	car every frame: the depth test keeps the dashboard, the wheel and the arms in front of
	them, and they stay on the glass however the head turns. The car's model is only read.

	A car with a wiper (its binding's `wiper`) clears the drops its blade passes over as the car's
	WiperSweep moves (Rules/WiperSweep), and while its washer runs (Washing) its jets throw fluid
	on the glass in their own pool of drops (Config/Washer), which the wipes then clear.
	Windshield.wipe takes any swept region as a test over pane coordinates (metres, x right from
	the pane's left edge, y down from its top) and fades the drops in it.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Catalog = require(ReplicatedStorage.Shared.Config.Cars.Catalog)
local Config = require(ReplicatedStorage.Shared.Config.Atmosphere)
local Hinge = require(ReplicatedStorage.Shared.Rules.Hinge)
local RainDensity = require(script.Parent.RainDensity)
local Units = require(ReplicatedStorage.Shared.Units)
local Washer = require(ReplicatedStorage.Shared.Config.Washer)
local WindshieldDrops = require(ReplicatedStorage.Shared.Rules.WindshieldDrops)
local WiperSweep = require(ReplicatedStorage.Shared.Rules.WiperSweep)

-- A drop's slot: its image, the drop in it and the opacity drops of its pool show at most.
type Slot = {
	label: ImageLabel,
	drop: WindshieldDrops.Drop?,
	trail: boolean,
	wiped: boolean,
	opacity: number,
}
-- The pane of one car, where its part sits from the car's mass box, and its wiper's sweep.
type Mount = {
	model: Model,
	chassis: BasePart,
	pane: WindshieldDrops.Pane,
	offset: CFrame,
	wiper: WiperSweep.Geometry?,
}

export type Windshield = {
	folder: Folder,
	part: Part,
	gui: SurfaceGui,
	slots: { Slot },
	carry: number,
	-- The washer's drops, their own pool, so a wash never takes the rain's budget.
	washerSlots: { Slot },
	washerCarry: number,
	-- The wiper's sweep last frame; nil until the first frame on a car.
	sweep: number?,
	mount: Mount?,
	random: Random,
}

local SHIELD = Config.WINDSHIELD
local GLASS = Washer.GLASS

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
	local entry = Catalog.of(model)
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
	local wiper = binding.wiper
	local sweep = if wiper
		then WiperSweep.geometry(
			pane,
			carPoint(wiper.hinge.pivot, binding.bodyRaise),
			Hinge.chassis(wiper.hinge.axis),
			carPoint(wiper.blade.inner, binding.bodyRaise),
			carPoint(wiper.blade.outer, binding.bodyRaise),
			wiper.hinge.travel or 0,
			SHIELD.wiperReach
		)
		else nil
	return { model = model, chassis = chassis, pane = pane, offset = offset, wiper = sweep }
end

local function place(shield: Windshield, mount: Mount)
	local pane = mount.pane
	shield.part.Size = Vector3.new(Units.metresToStuds(pane.width), Units.metresToStuds(pane.height), 0.02)
	-- The face toward the driver: +Z of the part points to the back of the car or to the front.
	shield.gui.Face = if mount.offset.LookVector.Z > 0 then Enum.NormalId.Front else Enum.NormalId.Back
end

local function hide(shield: Windshield)
	shield.gui.Enabled = false
	for _, pool in { shield.slots, shield.washerSlots } do
		for _, slot in pool do
			slot.drop = nil
			slot.label.Visible = false
		end
	end
	shield.sweep = nil
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
	label.ImageTransparency = 1 - slot.opacity * opacity
	-- A sliding drop's bead leads: below its trail going down, above it when the air drives
	-- it up the glass.
	local upward = slot.trail and drop.speed < 0
	label.Rotation = if upward then 180 else 0
	local bead = if slot.trail then SHIELD.trail.bead else SHIELD.bead.bead
	label.AnchorPoint = Vector2.new(0.5, if upward then 1 - bead else bead)
	label.Position = UDim2.fromScale(drop.x / pane.width, drop.y / pane.height)
end

local Windshield = {}

local function pool(gui: SurfaceGui, name: string, count: number, opacity: number): { Slot }
	local slots: { Slot } = table.create(count)
	for index = 1, count do
		local label = Instance.new("ImageLabel")
		label.Name = `{name}{index}`
		label.BackgroundTransparency = 1
		label.ImageTransparency = 1
		label.Visible = false
		label.Parent = gui
		table.insert(slots, { label = label, drop = nil, trail = false, wiped = false, opacity = opacity })
	end
	return slots
end

-- A washer drop in a free slot, somewhere in one of the jets' zones with all of its sprite on the
-- windscreen; none if four tries find no such place.
local function landWash(shield: Windshield, slot: Slot, pane: WindshieldDrops.Pane)
	local random = shield.random
	local zones = GLASS.zones
	local zone = zones[random:NextInteger(1, #zones)]
	local sprite = SHIELD.bead
	local size = random:NextNumber(GLASS.width[1], GLASS.width[2]) / sprite.across
	for _ = 1, 4 do
		local angle, distance =
			random:NextNumber(0, 2 * math.pi), zone.radius * math.sqrt(random:NextNumber())
		local x = zone.x * pane.width + math.cos(angle) * distance
		local y = zone.y * pane.height + math.sin(angle) * distance
		if WindshieldDrops.inside(pane.polygon, x, y, size / 2) then
			slot.drop = {
				x = x,
				y = y,
				radius = size / 2,
				slides = false,
				cling = 0,
				speed = 0,
				age = 0,
				life = random:NextNumber(GLASS.life[1], GLASS.life[2]),
			}
			slot.trail, slot.wiped = false, false
			local label = slot.label
			label.Image = sprite.image
			label.Size = UDim2.fromScale(size / pane.width, size / pane.height)
			label.Rotation = 0
			label.Visible = true
			return
		end
	end
end

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
	folder.Parent = Workspace
	return {
		folder = folder,
		part = part,
		gui = gui,
		slots = pool(gui, "Drop", largestPool(), SHIELD.opacity),
		carry = 0,
		washerSlots = pool(gui, "Wash", GLASS.pool, GLASS.opacity),
		washerCarry = 0,
		sweep = nil,
		mount = nil,
		random = Random.new(),
	}
end

-- One frame: in the cockpit view of `model`, drops land, cling, slide and fade, the washer's
-- land while it runs, and the wiper clears what its blade passed since the last frame (`sweep`,
-- the car's WiperSweep); anywhere else the glass is cleared. `cap` is the most rain drops at once
-- (the tier's lens budget).
function Windshield.update(
	shield: Windshield,
	dt: number,
	cockpit: boolean,
	model: Model?,
	intensity: number,
	exposure: number,
	speedKmh: number,
	cap: number,
	sweep: number,
	washing: boolean
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
		shield.sweep = nil
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
	local washes = 0
	if washing then
		washes, shield.washerCarry = RainDensity.accumulate(shield.washerCarry, GLASS.rate, dt, GLASS.pool)
	end
	for _, slot in shield.washerSlots do
		local drop = slot.drop
		if drop and not WindshieldDrops.step(drop, dt, 0, pane.height, tuning) then
			slot.drop = nil
			slot.label.Visible = false
		elseif drop == nil and washes > 0 then
			washes -= 1
			landWash(shield, slot, pane)
		end
		draw(slot, pane)
	end
	local wiper, last = mount.wiper, shield.sweep
	if wiper and last and sweep ~= last then
		Windshield.wipe(shield, function(x: number, y: number): boolean
			return WiperSweep.swept(wiper, last, sweep, x, y)
		end)
	end
	shield.sweep = sweep
end

-- Fades the drops, rain and washer, whose centre `swept` covers, for a wiper's pass.
function Windshield.wipe(shield: Windshield, swept: (x: number, y: number) -> boolean)
	for _, slots in { shield.slots, shield.washerSlots } do
		for _, slot in slots do
			local drop = slot.drop
			if drop and swept(drop.x, drop.y) then
				slot.wiped = true
				drop.life = math.min(drop.life, drop.age + SHIELD.wipeSeconds)
			end
		end
	end
end

function Windshield.destroy(shield: Windshield)
	shield.folder:Destroy()
end

return Windshield
