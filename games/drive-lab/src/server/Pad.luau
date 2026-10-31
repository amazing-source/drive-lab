--!strict
--[[
	Lays the all-asphalt test area for Services/Track: the paving now, so the parked cars have
	ground before Cars rigs them, then the painted lines once the new terrain can be measured.
	The paving is the road's own terrain asphalt, so the tyres, the road audio and the wet look
	find the same road as everywhere else; nothing else is laid.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config.Pad)
local Log = require(ReplicatedStorage.Kit.Log)
local Rules = require(ReplicatedStorage.Shared.Rules.Pad)
local Track = require(ReplicatedStorage.Shared.Config.Track)
local Units = require(ReplicatedStorage.Shared.Units)

local log = Log.scope("Pad")

local function studs(metres: number): number
	return Units.metresToStuds(metres)
end

local function colour(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

-- Where a place in the spawn's frame is: `ground` is the spawn's ground point, `look` its heading.
local function at(ground: Vector3, look: Vector3, along: number, across: number): Vector3
	local right = Vector3.new(-look.Z, 0, look.X)
	return ground + look * studs(along) + right * studs(across)
end

local function pave(ground: Vector3, look: Vector3)
	local depth = studs(Track.GROUND_DEPTH)
	for _, fill in Rules.fills(Config.AREA, Config.PAVING) do
		local centre = at(
			ground,
			look,
			(fill.alongFrom + fill.alongTo) / 2,
			(fill.acrossFrom + fill.acrossTo) / 2
		) - Vector3.new(0, depth / 2, 0)
		Workspace.Terrain:FillBlock(
			CFrame.lookAt(centre, centre + look),
			Vector3.new(studs(fill.acrossTo - fill.acrossFrom), depth, studs(fill.alongTo - fill.alongFrom)),
			Enum.Material.Asphalt
		)
	end
end

local function paint(ground: Vector3, look: Vector3, surface: number, parent: Instance)
	local stripe = Config.STRIPE
	local right = Vector3.new(-look.Z, 0, look.X)
	local height = surface + studs(stripe.lift + stripe.thickness / 2)
	for _, line in Rules.stripes(Config.AREA, Config.MARKINGS) do
		local centre = at(ground, look, line.along, line.across)
		local position = Vector3.new(centre.X, height, centre.Z)
		local direction = look * math.cos(line.yaw) + right * math.sin(line.yaw)
		local part = Instance.new("Part")
		part.Name = `Pad{line.kind}`
		part.Anchored = true
		part.CanCollide = stripe.canCollide
		part.CanQuery = stripe.canQuery
		part.CanTouch = stripe.canTouch
		part.CastShadow = stripe.castShadow
		part.Material = Enum.Material.SmoothPlastic
		part.Color = colour(if line.kind == "Edge" then Config.EDGE_COLOR else Config.LINE_COLOR)
		part.Size = Vector3.new(studs(Config.MARKINGS.width), studs(stripe.thickness), studs(line.length))
		part.CFrame = CFrame.lookAt(position, position + direction)
		part.Parent = parent
	end
end

local Pad = {}

-- Paves round the first car spawn, whose ground point and heading are given, and paints the lines
-- over the next frames; the baseplate goes once the paving holds the cars.
function Pad.start(ground: Vector3, look: Vector3)
	local began = Workspace:GetServerTimeNow()
	pave(ground, look)
	log.info(`paved in {string.format("%.2f", Workspace:GetServerTimeNow() - began)} s`)
	task.spawn(function()
		-- New terrain is not hit by raycasts until the next physics step.
		task.wait()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { Workspace.Terrain }
		local hit = Workspace:Raycast(ground + Vector3.new(0, 50, 0), Vector3.new(0, -100, 0), params)
		if hit == nil then
			log.warn("could not find the paving's surface; the lines may sit off it")
		end
		local lines = Instance.new("Folder")
		lines.Name = "PadLines"
		paint(ground, look, if hit then hit.Position.Y else ground.Y, lines)
		lines.Parent = Workspace
		local baseplate = Workspace:FindFirstChild("Baseplate")
		if baseplate then
			baseplate:Destroy()
		end
		log.info(
			`laid {#lines:GetChildren()} lines, {string.format("%.2f", Workspace:GetServerTimeNow() - began)} s after start`
		)
	end)
end

return Pad
