--!strict
--[[
	The lights of every car on this client. Each car's four light clusters glow through their
	SurfaceAppearance (daytime running lights always, headlights brighter, brake lights far
	brighter, an indicator's side tinted amber in its blink), and Roblox lights added here throw
	the light: a beam per headlight, a red glow behind, amber blinks, a reversing light.

	H cycles the headlights (automatic, on, off; automatic means at night or in heavy rain), X and
	C toggle the left and right indicators. The car this player drives also shows its brakes and
	reverse from its readouts; other cars show what this client can know: headlights by the time
	of day and the weather. Everything here is local.
]]
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CarRig = require(ReplicatedStorage.Shared.Car.CarRig)
local Config = require(ReplicatedStorage.Shared.Config.CarLights)
local Controls = require(ReplicatedStorage.Shared.Config.Controls)
local Rules = require(ReplicatedStorage.Shared.Rules.CarLights)
local StreetLamps = require(ReplicatedStorage.Shared.Rules.StreetLamps)
local StreetLights = require(ReplicatedStorage.Shared.Config.StreetLights)

type Cluster = {
	look: SurfaceAppearance?,
	glow: PointLight?,
	blink: PointLight,
	beam: SpotLight?,
}

type Car = {
	model: Model,
	left: { Cluster },
	right: { Cluster },
	front: { Cluster },
	rear: { Cluster },
	reverse: SpotLight,
}

local WHITE = Color3.new(1, 1, 1)

local localPlayer = Players.LocalPlayer
local cars: { [Model]: Car } = {}
local mode: Rules.Mode = "Auto"
local indicator: Rules.Side? = nil
local sinceScan = 0

local function attach(part: BasePart, name: string, offset: CFrame): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.CFrame = offset
	attachment.Parent = part
	return attachment
end

local function pointLight(parent: Instance, range: number, brightness: number, color: Color3): PointLight
	local light = Instance.new("PointLight")
	light.Range = range
	light.Brightness = brightness
	light.Color = color
	light.Shadows = false
	light.Enabled = false
	light.Parent = parent
	return light
end

local function cluster(part: BasePart, front: boolean): Cluster
	local size = part.Size
	-- Front clusters run back along the car's flank; the lamp is at their front end.
	local lamp = if front then CFrame.new(0, 0, -size.Z / 2 + Config.HEADLIGHT.inset) else CFrame.new(0, 0, 0)
	local point = attach(part, "LightPoint", lamp)
	local beam: SpotLight? = nil
	if front then
		local aim = attach(part, "HeadlightBeam", lamp * CFrame.Angles(Config.HEADLIGHT.pitch, 0, 0))
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Front
		spot.Range = Config.HEADLIGHT.range
		spot.Angle = Config.HEADLIGHT.angle
		spot.Brightness = Config.HEADLIGHT.brightness
		spot.Color = Config.HEADLIGHT.color
		spot.Enabled = false
		spot.Parent = aim
		beam = spot
	end
	return {
		look = part:FindFirstChildOfClass("SurfaceAppearance"),
		glow = if front
			then nil
			else pointLight(point, Config.TAIL.range, Config.TAIL.brightness, Config.TAIL.color),
		blink = pointLight(
			point,
			Config.INDICATOR.range,
			Config.INDICATOR.brightness,
			Config.INDICATOR.color
		),
		beam = beam,
	}
end

local function part(model: Model, name: string): BasePart?
	local found = model:FindFirstChild(name, true)
	return if found and found:IsA("BasePart") then found else nil
end

local function track(model: Instance)
	if not model:IsA("Model") or cars[model] then
		return
	end
	local names = Config.PARTS
	local frontLeft, frontRight = part(model, names.frontLeft), part(model, names.frontRight)
	local rearLeft, rearRight = part(model, names.rearLeft), part(model, names.rearRight)
	if frontLeft == nil or frontRight == nil or rearLeft == nil or rearRight == nil then
		return
	end
	local fl, fr = cluster(frontLeft, true), cluster(frontRight, true)
	local rl, rr = cluster(rearLeft, false), cluster(rearRight, false)
	-- The reversing light: between the rear clusters, lower, facing back.
	local middle = (rearLeft.Position + rearRight.Position) / 2
		- rearLeft.CFrame.UpVector * Config.REVERSE.drop
	local reverseAt = attach(rearLeft, "ReverseLight", CFrame.new(rearLeft.CFrame:PointToObjectSpace(middle)))
	local reverse = Instance.new("SpotLight")
	reverse.Face = Enum.NormalId.Back
	reverse.Range = Config.REVERSE.range
	reverse.Angle = Config.REVERSE.angle
	reverse.Brightness = Config.REVERSE.brightness
	reverse.Color = Config.REVERSE.color
	reverse.Enabled = false
	reverse.Parent = reverseAt
	cars[model] = {
		model = model,
		left = { fl, rl },
		right = { fr, rr },
		front = { fl, fr },
		rear = { rl, rr },
		reverse = reverse,
	}
end

local function drivenModel(): Model?
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	local model = seat and seat.Parent
	return if model and model:IsA("Model") and cars[model] then model else nil
end

local function number(model: Model, name: string, default: number): number
	local value = model:GetAttribute(name)
	return if typeof(value) == "number" then value else default
end

local function setGlow(look: SurfaceAppearance?, strength: number, tint: Color3)
	if look == nil then
		return
	end
	if look.EmissiveStrength ~= strength then
		look.EmissiveStrength = strength
	end
	if look.EmissiveTint ~= tint then
		look.EmissiveTint = tint
	end
end

local function show(car: Car, lit: Rules.Lit, shadows: boolean)
	for _, front in car.front do
		local beam = front.beam
		if beam then
			beam.Enabled = lit.headlights
			beam.Shadows = shadows
		end
	end
	for _, side in { car.left, car.right } do
		local on = if side == car.left then lit.left else lit.right
		for index, lamp in side do
			local isFront = index == 1
			local strength = if isFront
				then (if lit.headlights then Config.FRONT_HEADLIGHTS else Config.FRONT_DRL)
				else (if lit.brake then Config.REAR_BRAKE else Config.REAR_POSITION)
			setGlow(
				lamp.look,
				strength,
				if on then Config.INDICATOR_TINT elseif isFront then WHITE else Config.REAR_TINT
			)
			lamp.blink.Enabled = on
			local glow = lamp.glow
			if glow then
				glow.Enabled = lit.headlights or lit.brake
				glow.Range = if lit.brake then Config.TAIL.brakeRange else Config.TAIL.range
				glow.Brightness = if lit.brake then Config.TAIL.brakeBrightness else Config.TAIL.brightness
			end
		end
	end
	car.reverse.Enabled = lit.reverse
end

local function update(dt: number)
	-- A car streamed in without its light parts yet is picked up on a later scan.
	sinceScan += dt
	if sinceScan > 1 then
		sinceScan = 0
		for _, model in CollectionService:GetTagged(CarRig.TAG) do
			track(model)
		end
	end
	local night = StreetLamps.isNight(Lighting.ClockTime, StreetLights.DUSK, StreetLights.DAWN)
	local rain = Workspace:GetAttribute("RainIntensity")
	local driven = drivenModel()
	local now = os.clock()
	for model, car in cars do
		if model.Parent == nil then
			cars[model] = nil
			continue
		end
		local mine = model == driven
		local lit = Rules.decide({
			mode = if mine then mode else "Auto",
			night = night,
			rain = if typeof(rain) == "number" then rain else 0,
			brake = if mine then number(model, "Brake", 0) else 0,
			gear = if mine then number(model, "Gear", 1) else 1,
			indicator = if mine then indicator else nil,
			time = now,
		}, Config.TUNING)
		-- Shadowed beams cost a pass each; only the car this player drives casts them.
		show(car, lit, mine)
		if mine then
			-- For the HUD's tell-tales; local, like every readout on the driven car.
			model:SetAttribute("HeadlightsOn", lit.headlights)
			model:SetAttribute("IndicatorLeft", lit.left)
			model:SetAttribute("IndicatorRight", lit.right)
		end
	end
end

local Controller = {}

function Controller.start()
	for _, model in CollectionService:GetTagged(CarRig.TAG) do
		track(model)
	end
	CollectionService:GetInstanceAddedSignal(CarRig.TAG):Connect(track)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or drivenModel() == nil then
			return
		end
		if table.find(Controls.HEADLIGHTS, input.KeyCode) then
			mode = Rules.nextMode(mode)
		elseif table.find(Controls.INDICATOR_LEFT, input.KeyCode) then
			indicator = if indicator == "Left" then nil else "Left"
		elseif table.find(Controls.INDICATOR_RIGHT, input.KeyCode) then
			indicator = if indicator == "Right" then nil else "Right"
		end
	end)
	RunService.Heartbeat:Connect(update)
end

return Controller
