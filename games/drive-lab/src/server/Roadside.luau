--!strict
--[[
	Lays a stretch of road's furniture and surface marks for Services/Track: delineator posts,
	guardrails, sign gantries and the marks on the asphalt, where Rules/Roadside puts them. The
	models are kept in the place under ReplicatedStorage.DriveLabAssets, built for a prop on the
	road's right with +X along the road and +Z away from it; a left-side prop is turned half a
	turn, which also keeps each reflector's red face towards the traffic on its own side.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.Roadside)
local Log = require(ReplicatedStorage.Kit.Log)
local Rules = require(ReplicatedStorage.Shared.Rules.Roadside)
local Track = require(ReplicatedStorage.Shared.Config.Track)
local Units = require(ReplicatedStorage.Shared.Units)

-- The road at arc length s (metres): its centreline at the surface, in studs, and the unit
-- direction along it.
export type Frame = (s: number) -> (Vector3, Vector3)

local log = Log.scope("Roadside")
local warned: { [string]: boolean } = {}
local placed = 0

local function studs(metres: number): number
	return Units.metresToStuds(metres)
end

local function rightOf(along: Vector3): Vector3
	return Vector3.new(-along.Z, 0, along.X)
end

local function asset(name: string): Model?
	local assets = ReplicatedStorage:FindFirstChild("DriveLabAssets")
	local found = assets and assets:FindFirstChild(name)
	if found and found:IsA("Model") then
		return found
	end
	if not warned[name] then
		warned[name] = true
		log.warn(`ReplicatedStorage.DriveLabAssets.{name} is missing; the road goes without it`)
	end
	return nil
end

local function settle()
	placed += 1
	if placed % Config.YIELD_EVERY == 0 then
		task.wait()
	end
end

local function place(name: string, cframe: CFrame, parent: Instance)
	local template = asset(name)
	if template == nil then
		return
	end
	local model = template:Clone()
	model:PivotTo(cframe)
	model.Parent = parent
	settle()
end

-- A verge prop's frame: on side (-1 left, 1 right) setback metres past the road's edge at s,
-- its +X along the road for the right side and against it for the left.
local function vergeFrame(frame: Frame, s: number, side: number, setback: number): CFrame
	local centre, along = frame(s)
	local position = centre + rightOf(along) * (side * studs(Track.ROAD_WIDTH / 2 + setback))
	return CFrame.fromMatrix(position, along * side, Vector3.yAxis)
end

local function layDelineators(frame: Frame, from: number, to: number, seed: number, parent: Instance)
	local spots =
		Rules.delineators(from, to, seed, Config.DELINEATORS, Config.GUARDRAILS, Config.DELINEATOR_CLEARANCE)
	for _, spot in spots do
		place(
			Config.ASSETS.delineator,
			vergeFrame(frame, spot.s, spot.side, Config.DELINEATOR_SETBACK),
			parent
		)
	end
end

local function layGuardrails(frame: Frame, from: number, to: number, seed: number, parent: Instance)
	local layout = Config.GUARDRAILS
	for _, piece in Rules.guardrailPieces(from, to, seed, layout) do
		if piece.kind == "Section" then
			-- Laid along the chord of its 12 m, from whichever end is the model's origin.
			local first = frame(piece.s)
			local last = frame(piece.s + layout.section)
			local chord = (last - first).Unit
			local right = rightOf(chord)
			local offset = right * (piece.side * studs(Track.ROAD_WIDTH / 2 + Config.GUARDRAIL_SETBACK))
			local origin = (if piece.side > 0 then first else last) + offset
			local cframe = CFrame.fromMatrix(origin, chord * piece.side, Vector3.yAxis)
			place(Config.ASSETS.sections[piece.variant], cframe, parent)
		else
			-- Turned for the left side, the model's start terminal sits at the stretch's far end.
			local atStart = (piece.kind == "Start") == (piece.side > 0)
			local name = if atStart then Config.ASSETS.start else Config.ASSETS.finish
			place(name, vergeFrame(frame, piece.s, piece.side, Config.GUARDRAIL_SETBACK), parent)
		end
	end
end

local function layGantries(frame: Frame, from: number, to: number, seed: number, parent: Instance)
	for _, s in Rules.gantries(from, to, seed, Config.GANTRIES) do
		local centre, along = frame(s)
		place(Config.ASSETS.gantry, CFrame.fromMatrix(centre, along, Vector3.yAxis), parent)
	end
end

local function layMark(frame: Frame, mark: Rules.Mark, parent: Instance)
	local look = Config.MARK_LOOKS[mark.kind]
	local centre, along = frame(mark.s)
	local right = rightOf(along)
	local direction = along * math.cos(mark.yaw) + right * math.sin(mark.yaw)
	local position = centre + right * studs(mark.offset) + Vector3.new(0, look.lift, 0)
	local part = Instance.new("Part")
	part.Name = `Mark{mark.kind}`
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(studs(mark.width), Config.MARK_THICKNESS, studs(mark.length))
	part.CFrame = CFrame.lookAt(position, position + direction)
	local decal = Instance.new("Decal")
	decal.Face = Enum.NormalId.Top
	decal.Texture = look.image
	decal.Transparency = look.transparency.min + (look.transparency.max - look.transparency.min) * mark.shade
	decal.Parent = part
	part.Parent = parent
	settle()
end

local Roadside = {}

-- Lays the furniture and marks of road arc lengths [from, to) (metres) into parent, yielding
-- every few pieces.
function Roadside.lay(frame: Frame, from: number, to: number, seed: number, parent: Instance)
	for _, mark in Rules.marks(from, to, seed, Config.MARKS) do
		layMark(frame, mark, parent)
	end
	layDelineators(frame, from, to, seed, parent)
	layGuardrails(frame, from, to, seed, parent)
	layGantries(frame, from, to, seed, parent)
end

return Roadside
