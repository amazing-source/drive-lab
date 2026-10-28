--!strict
--[[
	Lights the roadside reflectors in this player's headlights: each tagged reflector the beams
	reach turns to neon of its colour, as bright as Rules/Reflectors says, and back to its plain
	plastic outside them; the nearest lit ones also get a glow dot (Effects/ReflectorDots), since
	a reflector is under a pixel past 40 m. Only the car this player drives lights them: a
	reflector returns light to its source, so only that car's driver sees it. Everything here is
	local.
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config.Reflectors)
local ReflectorDots = require(script.Parent.Parent.Effects.ReflectorDots)
local Rules = require(ReplicatedStorage.Shared.Rules.Reflectors)
local Units = require(ReplicatedStorage.Shared.Units)

type Reflector = {
	part: BasePart,
	facing: Vector3,
	glow: Color3,
	plain: Color3,
	material: Enum.Material,
	level: number,
}

local reflectors: { [BasePart]: Reflector } = {}
local elapsed = 0
local dots: ReflectorDots.Dots? = nil

local function track(instance: Instance)
	-- The models kept in ReplicatedStorage are tagged too; only reflectors in the world count.
	if not instance:IsA("BasePart") or not instance:IsDescendantOf(Workspace) then
		return
	end
	local facing: Vector3?, glow: Color3? = Config.FACING[instance.Name], Config.GLOW[instance.Name]
	if facing == nil or glow == nil then
		return
	end
	reflectors[instance] = {
		part = instance,
		facing = facing,
		glow = glow,
		plain = instance.Color,
		material = instance.Material,
		level = 0,
	}
end

local function show(reflector: Reflector, level: number)
	if reflector.level == level then
		return
	end
	reflector.level = level
	local part = reflector.part
	if level <= 0 then
		part.Material = reflector.material
		part.Color = reflector.plain
	else
		part.Material = Enum.Material.Neon
		part.Color = Color3.new():Lerp(reflector.glow, level)
	end
end

-- Where the headlights of the car this player drives are and which way they point, when on.
local function headlights(): (Vector3?, Vector3?)
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	local car = seat and seat.Parent
	if seat == nil or car == nil or car:GetAttribute("HeadlightsOn") ~= true then
		return nil, nil
	end
	return seat.Position, seat.CFrame.LookVector
end

local function level(reflector: Reflector, at: Vector3, heading: Vector3, reach: number): (number, number)
	local offset = at - reflector.part.Position
	local distance = offset.Magnitude
	if distance >= reach or distance <= 0 then
		return 0, distance
	end
	local toCar = offset / distance
	local glow = Rules.glow({
		headlights = true,
		distance = Units.studsToMetres(distance),
		ahead = -heading:Dot(toCar),
		-- Imported meshes keep their model's axes, so the face turns with the part.
		facing = reflector.part.CFrame:VectorToWorldSpace(reflector.facing):Dot(toCar),
	}, Config.TUNING)
	return Rules.level(glow, Config.TUNING.levels), distance
end

local function update(dt: number)
	elapsed += dt
	if elapsed < Config.UPDATE_INTERVAL then
		return
	end
	elapsed = 0
	local at, heading = headlights()
	local reach = Units.metresToStuds(Config.TUNING.reach)
	local lit: { ReflectorDots.Lit } = {}
	for part, reflector in reflectors do
		if part.Parent == nil then
			reflectors[part] = nil
			continue
		end
		local step, distance = 0, 0
		if at and heading then
			step, distance = level(reflector, at, heading, reach)
		end
		show(reflector, step)
		if step > 0 then
			table.insert(lit, {
				part = part,
				colour = reflector.glow,
				level = step,
				distance = Units.studsToMetres(distance),
			})
		end
	end
	if dots then
		table.sort(lit, function(a, b)
			return a.distance < b.distance
		end)
		ReflectorDots.show(dots, lit)
	end
end

local Controller = {}

function Controller.start()
	for _, part in CollectionService:GetTagged(Config.TAG) do
		track(part)
	end
	CollectionService:GetInstanceAddedSignal(Config.TAG):Connect(track)
	CollectionService:GetInstanceRemovedSignal(Config.TAG):Connect(function(part)
		if part:IsA("BasePart") then
			reflectors[part] = nil
		end
	end)
	dots = ReflectorDots.new()
	RunService.Heartbeat:Connect(update)
end

return Controller
