--!strict
--[[
	Water drops on the camera's lens, drawn as a screen overlay from a fixed pool of images (the
	largest tier's count), placed and aged by Rules/LensDrops. The overlay sits under the HUD
	and holds nothing in the cockpit view. A frame creates nothing: it moves, fades and shows
	or hides the pooled images.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Atmosphere = require(ReplicatedStorage.Shared.Config.Atmosphere)
local Config = require(ReplicatedStorage.Shared.Config.RainOptics)
local LensDrops = require(ReplicatedStorage.Shared.Rules.LensDrops)
local RainDensity = require(script.Parent.RainDensity)

type Sprite = { image: ImageLabel, drop: LensDrops.Drop? }

export type Lens = { gui: ScreenGui, sprites: { Sprite }, carry: number, random: Random }

local LENS = Config.LENS
local TUNING = LENS.drops

local function largest(): number
	local count = 0
	for _, budget in Atmosphere.BUDGETS do
		count = math.max(count, budget.lensDrops)
	end
	return count
end

local function sprite(parent: Instance, index: number): Sprite
	local image = Instance.new("ImageLabel")
	image.Name = `Drop{index}`
	image.BackgroundTransparency = 1
	image.Image = LENS.texture
	image.ImageColor3 = Color3.fromRGB(LENS.color.r, LENS.color.g, LENS.color.b)
	image.ImageRectSize = Vector2.one * LENS.cellSize
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	-- Sized by the screen's height on both axes, so a drop stays round on any aspect ratio.
	image.SizeConstraint = Enum.SizeConstraint.RelativeYY
	image.Visible = false
	image.Parent = parent
	return { image = image, drop = nil }
end

local function land(lens: Lens, item: Sprite)
	local random = lens.random
	local drop = LensDrops.new(
		random:NextNumber(),
		random:NextNumber(),
		random:NextNumber(),
		random:NextNumber(),
		TUNING
	)
	local cell = random:NextInteger(0, LENS.cells * LENS.cells - 1)
	local image = item.image
	image.ImageRectOffset = Vector2.new(cell % LENS.cells, cell // LENS.cells) * LENS.cellSize
	image.Size = UDim2.fromScale(drop.size, drop.size)
	image.Position = UDim2.fromScale(drop.x, drop.y)
	image.ImageTransparency = 1
	image.Visible = true
	item.drop = drop
end

-- Writes a drop's image only when it moved about a pixel or faded visibly: GUI writes cost,
-- and a sliding drop moves a ten-thousandth of the screen a frame.
local function draw(item: Sprite, drop: LensDrops.Drop)
	local image = item.image
	if math.abs(image.Position.Y.Scale - drop.y) > 0.001 then
		image.Position = UDim2.fromScale(drop.x, drop.y)
	end
	local transparency = 1 - LensDrops.opacity(drop, TUNING) * (1 - LENS.transparency)
	if math.abs(image.ImageTransparency - transparency) > 0.01 then
		image.ImageTransparency = transparency
	end
end

local Lens = {}

function Lens.new(parent: Instance): Lens
	local gui = Instance.new("ScreenGui")
	gui.Name = "DriveLabLensDrops"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- Under the driving HUD (5): the HUD reads as glass in front of the lens.
	gui.DisplayOrder = 1
	local sprites = {}
	for index = 1, largest() do
		table.insert(sprites, sprite(gui, index))
	end
	gui.Parent = parent
	return { gui = gui, sprites = sprites, carry = 0, random = Random.new() }
end

-- Lands, ages and draws the drops; returns how many landed this frame (the contact blur
-- reads it). `limit` is the tier's most drops at once.
function Lens.update(
	lens: Lens,
	dt: number,
	intensity: number,
	exposure: number,
	view: LensDrops.View,
	speedKmh: number,
	limit: number
): number
	local wet = view ~= "Cockpit" and intensity > 0 and exposure > 0
	local live = 0
	for _, item in lens.sprites do
		local drop = item.drop
		if drop and (view == "Cockpit" or not LensDrops.step(drop, dt, wet, TUNING)) then
			item.drop, item.image.Visible = nil, false
		elseif drop then
			live += 1
			draw(item, drop)
		end
	end
	local free = math.max(math.min(limit, #lens.sprites) - live, 0)
	local due
	due, lens.carry = RainDensity.accumulate(
		lens.carry,
		LensDrops.rate(intensity, exposure, view, speedKmh, TUNING),
		dt,
		free
	)
	local landed = 0
	for _, item in lens.sprites do
		if landed >= due then
			break
		end
		if item.drop == nil then
			land(lens, item)
			landed += 1
		end
	end
	return landed
end

function Lens.destroy(lens: Lens)
	lens.gui:Destroy()
end

return Lens
