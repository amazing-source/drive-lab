--!strict
--[[
	Draws the street lamps' glints (Rules/LampGlints) for Controllers/StreetLights, from a fixed
	pool of additive beams re-aimed every frame at the lamps the controller hands over, so
	nothing is made or destroyed as lamps come and go.

	Both kinds are camera-facing beams. A flare runs between two points either side of the head
	along the camera's right, so it stays level on screen whatever the view. A streak runs along
	the road from its far end to its near end, on the line from the lamp to the eye's foot: a
	camera-facing ribbon about that line lies flat on the road.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config.LampGlints)
local Rules = require(ReplicatedStorage.Shared.Rules.LampGlints)
local Track = require(ReplicatedStorage.Shared.Config.Track)
local Units = require(ReplicatedStorage.Shared.Units)

-- A lit lamp: its base on the road's surface, the road's right there, and its verge (-1, 1).
export type Lamp = { base: Vector3, right: Vector3, side: number }

type Glint = { beam: Beam, from: Attachment, to: Attachment }

export type Glints = {
	folder: Folder,
	flares: { Glint },
	streaks: { Glint },
	lamps: { Lamp },
}

local METRES = Units.METRES_PER_STUD

local function studs(metres: number): number
	return Units.metresToStuds(metres)
end

local function newGlint(anchor: BasePart, texture: string, brightness: number): Glint
	local from = Instance.new("Attachment")
	local to = Instance.new("Attachment")
	local beam = Instance.new("Beam")
	beam.Texture = texture
	beam.TextureMode = Enum.TextureMode.Stretch
	beam.TextureLength = 1
	beam.Color = ColorSequence.new(Config.COLOUR)
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Brightness = brightness
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Enabled = false
	beam.Attachment0 = from
	beam.Attachment1 = to
	from.Parent = anchor
	to.Parent = anchor
	beam.Parent = anchor
	return { beam = beam, from = from, to = to }
end

local function hide(glint: Glint)
	if glint.beam.Enabled then
		glint.beam.Enabled = false
	end
end

local function show(glint: Glint, from: Vector3, to: Vector3, widths: { number }, opacity: number)
	glint.from.Position = from
	glint.to.Position = to
	glint.beam.Width0 = widths[1]
	glint.beam.Width1 = widths[2]
	glint.beam.Transparency = NumberSequence.new(1 - opacity)
	glint.beam.Enabled = true
end

local function plan(position: Vector3): Rules.Point
	return { x = position.X * METRES, z = position.Z * METRES }
end

local function flare(glint: Glint, lamp: Lamp, view: CFrame, rain: number)
	local head = lamp.base + Vector3.new(0, studs(Config.HEAD_HEIGHT), 0)
	local toEye = view.Position - head
	local look = Rules.flare(toEye.Magnitude * METRES, rain, Config.TUNING)
	if look.opacity <= 0 then
		hide(glint)
		return
	end
	local centre = head + toEye.Unit * studs(Config.TOWARD_EYE)
	local half = view.RightVector * studs(look.length / 2)
	show(glint, centre - half, centre + half, { studs(look.height), studs(look.height) }, look.opacity)
end

local function streak(glint: Glint, lamp: Lamp, eye: Vector3, wetness: number)
	local surface = lamp.base.Y
	local inward = -lamp.right * lamp.side
	local edge = lamp.base + inward * studs(Track.LAMP_SETBACK)
	local found = Rules.reflection(
		plan(eye),
		(eye.Y - surface) * METRES,
		plan(lamp.base),
		Config.HEAD_HEIGHT,
		plan(edge),
		{ x = inward.X, z = inward.Z },
		wetness,
		Config.TUNING
	)
	if found == nil then
		hide(glint)
		return
	end
	local y = surface + studs(Config.STREAK_LIFT)
	local far = Vector3.new(found.far.x / METRES, y, found.far.z / METRES)
	local near = Vector3.new(found.near.x / METRES, y, found.near.z / METRES)
	-- A beam draws its texture's last column at Attachment0 (seen in Studio): the streak's
	-- bright end, so it goes at the near end.
	show(glint, near, far, { studs(found.nearWidth), studs(found.farWidth) }, found.opacity)
end

local LampGlints = {}

function LampGlints.new(): Glints
	local folder = Instance.new("Folder")
	folder.Name = "DriveLabLampGlints"
	local anchor = Instance.new("Part")
	anchor.Name = "Anchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.identity
	anchor.Parent = folder
	local flares, streaks = {}, {}
	for _ = 1, Config.FLARES do
		table.insert(flares, newGlint(anchor, Config.FLARE_IMAGE, Config.FLARE_BRIGHTNESS))
	end
	for _ = 1, Config.REFLECTIONS do
		table.insert(streaks, newGlint(anchor, Config.REFLECTION_IMAGE, Config.REFLECTION_BRIGHTNESS))
	end
	folder.Parent = Workspace
	return { folder = folder, flares = flares, streaks = streaks, lamps = {} }
end

-- The lit lamps in view, nearest first; each pool draws as many as it holds.
function LampGlints.assign(glints: Glints, lamps: { Lamp })
	glints.lamps = lamps
end

-- Re-aims every glint at its lamp for this frame's camera; wetness and rain are 0 to 1.
function LampGlints.render(glints: Glints, camera: Camera, wetness: number, rain: number)
	local view = camera.CFrame
	for index, glint in glints.flares do
		local lamp = glints.lamps[index]
		if lamp then
			flare(glint, lamp, view, rain)
		else
			hide(glint)
		end
	end
	for index, glint in glints.streaks do
		local lamp = glints.lamps[index]
		if lamp then
			streak(glint, lamp, view.Position, wetness)
		else
			hide(glint)
		end
	end
end

function LampGlints.destroy(glints: Glints)
	glints.folder:Destroy()
end

return LampGlints
