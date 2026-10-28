--!strict
--[[
	Lights the street lamps on this client: on from dusk to dawn by the local time of day (the
	weather sets Lighting.ClockTime), each lamp switching at its own moment within a couple of
	seconds; only lamps near the camera have their lights enabled, and only the nearest few
	downlights cast shadows. Lit, a lamp's candle-bulbs turn to warm neon. The lamps themselves
	are laid by the server's road (Services/Track); everything here is local.
]]
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config.StreetLights)
local StreetLamps = require(ReplicatedStorage.Shared.Rules.StreetLamps)
local Units = require(ReplicatedStorage.Shared.Units)

local TAG = "DriveLabStreetLamp"

type Lamp = {
	model: Model,
	bulb: BasePart?,
	downlights: { Light },
	glows: { Light },
	delay: number,
	lit: boolean,
}

local lamps: { [Model]: Lamp } = {}
local night = false
local changedAt = -math.huge
local elapsed = 0

local function track(model: Instance)
	-- The lamp kept in ReplicatedStorage is tagged too; only lamps standing in the world count.
	if not model:IsA("Model") or not model:IsDescendantOf(Workspace) then
		return
	end
	local downlights: { Light }, glows: { Light } = {}, {}
	for _, light in model:GetDescendants() do
		if light:IsA("SpotLight") then
			table.insert(downlights, light)
		elseif light:IsA("PointLight") then
			table.insert(glows, light)
		end
	end
	local bulb = model:FindFirstChild("Bulb")
	local at = model:GetPivot().Position
	lamps[model] = {
		model = model,
		bulb = if bulb and bulb:IsA("BasePart") then bulb else nil,
		downlights = downlights,
		glows = glows,
		delay = StreetLamps.delay(at.X, at.Z, Config.SWITCH_SPREAD),
		lit = false,
	}
end

local function setLit(lamp: Lamp, lit: boolean)
	if lamp.lit == lit then
		return
	end
	lamp.lit = lit
	local bulb = lamp.bulb
	if bulb then
		bulb.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
		bulb.Color = if lit then Config.BULB_ON else Config.BULB_OFF
	end
end

local function update(dt: number)
	elapsed += dt
	if elapsed < Config.UPDATE_INTERVAL then
		return
	end
	elapsed = 0
	local now = os.clock()
	local isNight = StreetLamps.isNight(Lighting.ClockTime, Config.DUSK, Config.DAWN)
	if isNight ~= night then
		night, changedAt = isNight, now
	end
	local camera = Workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	local reach = Units.metresToStuds(Config.LIT_DISTANCE)
	local near: { { lamp: Lamp, distance: number } } = {}
	for model, lamp in lamps do
		if model.Parent == nil then
			lamps[model] = nil
			continue
		end
		-- Each lamp follows the switch once its own delay has passed.
		local switched = now - changedAt >= lamp.delay
		local lit = if switched then night else not night
		setLit(lamp, lit)
		local distance = (model:GetPivot().Position - eye).Magnitude
		local shining = lit and distance < reach
		for _, light in lamp.downlights do
			light.Enabled = shining
		end
		for _, light in lamp.glows do
			light.Enabled = shining
		end
		if shining then
			table.insert(near, { lamp = lamp, distance = distance })
		end
	end
	table.sort(near, function(a, b)
		return a.distance < b.distance
	end)
	-- Set once per lamp, so no light's shadows flick off and on within a frame.
	for index, entry in near do
		for _, light in entry.lamp.downlights do
			light.Shadows = index <= Config.SHADOW_LAMPS
		end
	end
end

local Controller = {}

function Controller.start()
	for _, model in CollectionService:GetTagged(TAG) do
		track(model)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(track)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(model)
		if model:IsA("Model") then
			lamps[model] = nil
		end
	end)
	RunService.Heartbeat:Connect(update)
end

return Controller
