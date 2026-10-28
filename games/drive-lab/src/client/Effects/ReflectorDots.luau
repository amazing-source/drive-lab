--!strict
--[[
	The bright dot a reflector makes in the headlights, for Controllers/Reflectors. A reflector
	is a few centimetres across, under a pixel past 40 m, yet at night it is the brightest thing
	beside the road for hundreds of metres: drawn at its true size the row of posts vanishes. Each
	lit reflector nearest the car gets a round billboard of a fixed few pixels, larger close by,
	hidden by whatever stands in front of it. A fixed pool is re-pointed every update.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config.Reflectors)

-- A lit reflector: its part, its glow colour, its step (0 to 1) and its distance in metres.
export type Lit = { part: BasePart, colour: Color3, level: number, distance: number }

type Dot = { gui: BillboardGui, disc: Frame }

export type Dots = { folder: Folder, dots: { Dot } }

local function newDot(parent: Folder): Dot
	local gui = Instance.new("BillboardGui")
	gui.Name = "ReflectorDot"
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.Brightness = Config.DOTS.brightness
	gui.Enabled = false
	local disc = Instance.new("Frame")
	disc.BorderSizePixel = 0
	disc.Size = UDim2.fromScale(1, 1)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = disc
	disc.Parent = gui
	gui.Parent = parent
	return { gui = gui, disc = disc }
end

local function pixels(distance: number): number
	local dots = Config.DOTS
	local t = math.clamp((distance - dots.nearDistance) / (dots.farDistance - dots.nearDistance), 0, 1)
	return math.floor(dots.nearPixels + (dots.farPixels - dots.nearPixels) * t + 0.5)
end

local ReflectorDots = {}

function ReflectorDots.new(): Dots
	local folder = Instance.new("Folder")
	folder.Name = "DriveLabReflectorDots"
	local dots = table.create(Config.DOTS.count)
	for _ = 1, Config.DOTS.count do
		table.insert(dots, newDot(folder))
	end
	folder.Parent = Workspace
	return { folder = folder, dots = dots }
end

-- Puts a dot on each of the nearest lit reflectors (`lit` sorted nearest first) and hides the rest.
function ReflectorDots.show(dots: Dots, lit: { Lit })
	for index, dot in dots.dots do
		local entry = lit[index]
		if entry == nil then
			dot.gui.Enabled = false
			continue
		end
		local size = pixels(entry.distance)
		dot.gui.Adornee = entry.part
		dot.gui.Size = UDim2.fromOffset(size, size)
		dot.disc.BackgroundColor3 = entry.colour
		dot.disc.BackgroundTransparency = 1 - entry.level
		dot.gui.Enabled = true
	end
end

function ReflectorDots.destroy(dots: Dots)
	dots.folder:Destroy()
end

return ReflectorDots
