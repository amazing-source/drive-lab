--!strict
--[[
	The driven car's wiper arm and washer jets, drawn from its switches' readouts (WiperSweep and
	Washing, Controllers/CarSwitches): the arm turns about its hinge by its sweep, and the jets spray
	at the windscreen while the washer runs (Config/Washer). Like the switches, local to the
	driver's client: other clients see the wiper parked. The drops on the glass are the
	windscreen's (Atmosphere/Windshield). Writes nothing but the arm's weld C0 and its own jets.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Binding = require(ReplicatedStorage.Shared.Config.Cars.Binding)
local CarRig = require(ReplicatedStorage.Shared.Car.CarRig)
local Catalog = require(ReplicatedStorage.Shared.Config.Cars.Catalog)
local Units = require(ReplicatedStorage.Shared.Units)
local Washer = require(ReplicatedStorage.Shared.Config.Washer)
local WindshieldDrops = require(ReplicatedStorage.Shared.Rules.WindshieldDrops)

type Drive = {
	model: Model,
	binding: Binding.CarModel,
	wiper: Binding.Wiper,
	chassis: BasePart,
	arm: CarRig.Hinged?,
	written: number?,
	jets: { ParticleEmitter }?,
	-- Seconds until the arm is looked for again, while its part has not streamed in.
	retry: number,
}

local RETRY_SECONDS = 1
local JETS = Washer.JETS

local localPlayer = Players.LocalPlayer
local drive: Drive? = nil

local function seatedModel(): Model?
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	local model = seat and seat.Parent
	return if model and model:IsA("Model") and model:HasTag(CarRig.TAG) then model else nil
end

-- A binding point (metres from the centre of mass, car frame) in the chassis's space, in studs.
local function chassisPoint(point: Binding.CarPoint, raise: number): Vector3
	return Vector3.new(point.right, point.up + raise, -point.forward) * Units.metresToStuds(1)
end

local function rgb(colour: Washer.Rgb): Color3
	return Color3.fromRGB(colour.r, colour.g, colour.b)
end

-- One jet per nozzle, each aimed at its zone of the windscreen (the zones in turn).
local function makeJets(current: Drive): { ParticleEmitter }
	local binding = current.binding
	local corners = {}
	for index, corner in binding.windshield do
		corners[index] = { x = corner.right, y = corner.up + binding.bodyRaise, z = -corner.forward }
	end
	local pane = WindshieldDrops.pane(corners, { x = 0, y = 0, z = 1 })
	local zones = Washer.GLASS.zones
	local jets: { ParticleEmitter } = {}
	for index, nozzle in current.wiper.nozzles do
		local zone = zones[(index - 1) % #zones + 1]
		local aim = WindshieldDrops.point(pane, zone.x * pane.width, zone.y * pane.height)
		local from = chassisPoint(nozzle, binding.bodyRaise)
		local attachment = Instance.new("Attachment")
		attachment.Name = "DriveLabWasherJet"
		attachment.CFrame = CFrame.lookAt(from, Vector3.new(aim.x, aim.y, aim.z) * Units.metresToStuds(1))
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = JETS.texture
		emitter.Color = ColorSequence.new(rgb(JETS.color))
		emitter.EmissionDirection = Enum.NormalId.Front
		emitter.Rate = JETS.rate
		emitter.Speed = NumberRange.new(JETS.speed)
		emitter.SpreadAngle = Vector2.new(JETS.spread, JETS.spread)
		emitter.Size = NumberSequence.new(JETS.size[1], JETS.size[2])
		emitter.Lifetime = NumberRange.new(JETS.lifetime[1], JETS.lifetime[2])
		emitter.Transparency = NumberSequence.new(JETS.transparency[1], JETS.transparency[2])
		emitter.LightInfluence = 1
		emitter.Enabled = false
		emitter.Parent = attachment
		attachment.Parent = current.chassis
		table.insert(jets, emitter)
	end
	return jets
end

local function park(current: Drive)
	local arm = current.arm
	if arm and arm.weld.Parent then
		arm.weld.C0 = arm.rest
	end
	local jets = current.jets
	if jets then
		for _, emitter in jets do
			local attachment = emitter.Parent
			if attachment then
				attachment:Destroy()
			end
		end
	end
end

-- Follows the seat: a car with a wiper, nothing otherwise.
local function follow(): Drive?
	local model = seatedModel()
	local current = drive
	if current and current.model == model then
		return current
	end
	if current then
		park(current)
	end
	drive = nil
	local entry = model and Catalog.of(model)
	local wiper = entry and entry.model.wiper
	local chassis = model and model.PrimaryPart
	if model == nil or entry == nil or wiper == nil or chassis == nil then
		return nil
	end
	local fresh: Drive = {
		model = model,
		binding = entry.model,
		wiper = wiper,
		chassis = chassis,
		arm = nil,
		written = nil,
		jets = nil,
		retry = 0,
	}
	drive = fresh
	return fresh
end

local function update(dt: number)
	local current = follow()
	if current == nil then
		return
	end
	local model = current.model
	if current.arm == nil then
		current.retry -= dt
		if current.retry <= 0 then
			current.retry = RETRY_SECONDS
			local rig = CarRig.find(model, current.binding)
			current.arm = rig and rig.wiper
		end
	end
	local arm = current.arm
	local sweep = model:GetAttribute("WiperSweep")
	local angle = (current.wiper.hinge.travel or 0) * (if typeof(sweep) == "number" then sweep else 0)
	if arm and angle ~= current.written then
		arm.weld.C0 = arm.rest * CFrame.Angles(angle, 0, 0)
		current.written = angle
	end
	local washing = model:GetAttribute("Washing") == true
	local jets = current.jets
	if washing and jets == nil then
		jets = makeJets(current)
		current.jets = jets
	end
	if jets then
		for _, emitter in jets do
			emitter.Enabled = washing
		end
	end
end

local Controller = {}

function Controller.start()
	RunService.Heartbeat:Connect(update)
end

return Controller
