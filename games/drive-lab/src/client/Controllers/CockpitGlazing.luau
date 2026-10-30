--!strict
--[[
	The windows of the car this player drives, while the cockpit view is on. Glass draws no
	particles behind it, so from the driver's seat the rain outside was invisible; in the
	cockpit view the car's window meshes (its model binding's glazing) become a see-through
	plastic, on this client only, and get their own look back on leaving the view or the car.
	Reads the camera's DriveLabView and the seat; writes nothing but those windows' look.
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CarRig = require(ReplicatedStorage.Shared.Car.CarRig)
local Catalog = require(ReplicatedStorage.Shared.Config.Cars.Catalog)
local Config = require(ReplicatedStorage.Shared.Config.CockpitGlazing)
local Log = require(ReplicatedStorage.Kit.Log)

type Saved = {
	part: BasePart,
	material: Enum.Material,
	transparency: number,
	color: Color3,
	reflectance: number,
}

local localPlayer = Players.LocalPlayer
local log = Log.scope("CockpitGlazing")
local swapped: { Saved } = {}
local glazed: Model? = nil
local watching: RBXScriptConnection? = nil

local material = Enum.Material:FromName(Config.MATERIAL)
assert(material, `Config.CockpitGlazing names an unknown material: {Config.MATERIAL}`)
local tint = Color3.fromRGB(Config.COLOR.r, Config.COLOR.g, Config.COLOR.b)

local function seatedCar(): Model?
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	local model = seat and seat.Parent
	if model and model:IsA("Model") and CollectionService:HasTag(model, CarRig.TAG) then
		return model
	end
	return nil
end

local function restore()
	for _, saved in swapped do
		local part = saved.part
		if part.Parent then
			part.Material = saved.material
			part.Transparency = saved.transparency
			part.Color = saved.color
			part.Reflectance = saved.reflectance
		end
	end
	table.clear(swapped)
	glazed = nil
end

local function glaze(model: Model)
	local entry = Catalog.of(model)
	if entry == nil then
		return
	end
	for _, partName in entry.model.glazing do
		local part = model:FindFirstChild(partName, true)
		if part and part:IsA("BasePart") then
			table.insert(swapped, {
				part = part,
				material = part.Material,
				transparency = part.Transparency,
				color = part.Color,
				reflectance = part.Reflectance,
			})
			part.Material = material :: Enum.Material
			part.Transparency = Config.TRANSPARENCY
			part.Color = tint
			part.Reflectance = Config.REFLECTANCE
		else
			log.warn(`{model:GetFullName()} has no window part {partName}`)
		end
	end
	glazed = model
end

local function refresh(camera: Camera)
	local target = if camera:GetAttribute("DriveLabView") == "Cockpit" then seatedCar() else nil
	if target == glazed then
		return
	end
	restore()
	if target then
		glaze(target)
	end
end

local function bind(camera: Camera?)
	if watching then
		watching:Disconnect()
		watching = nil
	end
	restore()
	if camera == nil then
		return
	end
	watching = camera:GetAttributeChangedSignal("DriveLabView"):Connect(function()
		refresh(camera)
	end)
	refresh(camera)
end

local Controller = {}

function Controller.start()
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		bind(Workspace.CurrentCamera)
	end)
	bind(Workspace.CurrentCamera)
end

return Controller
