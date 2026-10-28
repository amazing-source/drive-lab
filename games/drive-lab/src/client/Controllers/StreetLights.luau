--!strict
--[[
	Lights the street lamps on this client: on from dusk to dawn by the local time of day (the
	weather sets Lighting.ClockTime), each lamp switching at its own moment within a couple of
	seconds; only lamps near the camera have their lights enabled, and only the nearest few
	downlights cast shadows. Lit, a lamp's candle-bulbs turn to warm neon. The nearest lit lamps
	in view also get their glints (Effects/LampGlints): a faint flare, and a streak of reflected
	light when the road is wet. The lamps themselves are laid by the server's road
	(Services/Track); everything here is local.
]]
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config.StreetLights)
local GlintConfig = require(ReplicatedStorage.Shared.Config.LampGlints)
local LampGlints = require(script.Parent.Parent.Effects.LampGlints)
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
	-- The verge it stands on (-1 left, 1 right), from the server; 0 if unknown, and no glints.
	side: number,
	connections: { RBXScriptConnection },
}

local lamps: { [Model]: Lamp } = {}
local night = false
local changedAt = -math.huge
local elapsed = 0
local glints: LampGlints.Glints? = nil

local function paintBulb(bulb: BasePart, lit: boolean)
	bulb.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
	bulb.Color = if lit then Config.BULB_ON else Config.BULB_OFF
end

local function adopt(lamp: Lamp, instance: Instance)
	if instance:IsA("SpotLight") then
		table.insert(lamp.downlights, instance)
	elseif instance:IsA("PointLight") then
		table.insert(lamp.glows, instance)
	elseif instance:IsA("BasePart") and instance.Name == "Bulb" and instance.Parent == lamp.model then
		lamp.bulb = instance
		paintBulb(instance, lamp.lit)
	end
end

local function drop(lamp: Lamp, instance: Instance)
	for _, list in { lamp.downlights, lamp.glows } do
		local index = table.find(list, instance :: Light)
		if index then
			table.remove(list, index)
		end
	end
	if lamp.bulb == instance then
		lamp.bulb = nil
	end
end

local function untrack(model: Instance)
	local lamp = lamps[model :: Model]
	if lamp then
		for _, connection in lamp.connections do
			connection:Disconnect()
		end
		lamps[model :: Model] = nil
	end
end

-- With streaming on, a lamp model arrives before its parts and its parts stream out and back in
-- as new instances: its lights and bulb are kept as they come and go (#44: read once on arrival,
-- every lamp stayed dark while its glints were drawn).
local function track(model: Instance)
	-- The lamp kept in ReplicatedStorage is tagged too; only lamps standing in the world count.
	if not model:IsA("Model") or not model:IsDescendantOf(Workspace) or lamps[model] then
		return
	end
	local at = model:GetPivot().Position
	local side = model:GetAttribute("RoadSide")
	local lamp: Lamp = {
		model = model,
		bulb = nil,
		downlights = {},
		glows = {},
		delay = StreetLamps.delay(at.X, at.Z, Config.SWITCH_SPREAD),
		lit = false,
		side = if side == 1 then 1 elseif side == -1 then -1 else 0,
		connections = {},
	}
	for _, instance in model:GetDescendants() do
		adopt(lamp, instance)
	end
	table.insert(
		lamp.connections,
		model.DescendantAdded:Connect(function(instance)
			adopt(lamp, instance)
		end)
	)
	table.insert(
		lamp.connections,
		model.DescendantRemoving:Connect(function(instance)
			drop(lamp, instance)
		end)
	)
	lamps[model] = lamp
end

local function setLit(lamp: Lamp, lit: boolean)
	if lamp.lit == lit then
		return
	end
	lamp.lit = lit
	local bulb = lamp.bulb
	if bulb then
		paintBulb(bulb, lit)
	end
end

-- The nearest lit lamps in view, as many as the larger glint pool holds.
local function inView(near: { { lamp: Lamp, distance: number } }, view: CFrame): { LampGlints.Lamp }
	local wanted = math.max(GlintConfig.FLARES, GlintConfig.REFLECTIONS)
	local found = {}
	for _, entry in near do
		local pivot = entry.lamp.model:GetPivot()
		local offset = pivot.Position - view.Position
		if
			entry.lamp.side ~= 0
			and offset.Magnitude > 0
			and view.LookVector:Dot(offset.Unit) > GlintConfig.IN_VIEW
		then
			table.insert(found, { base = pivot.Position, right = pivot.ZVector, side = entry.lamp.side })
			if #found >= wanted then
				break
			end
		end
	end
	return found
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
			untrack(model)
			continue
		end
		-- Each lamp follows the switch once its own delay has passed.
		local switched = now - changedAt >= lamp.delay
		local lit = if switched then night else not night
		setLit(lamp, lit)
		local distance = (model:GetPivot().Position - eye).Magnitude
		-- A lamp whose parts have not streamed in has nothing to light or to glint.
		local shining = lit and distance < reach and #lamp.downlights > 0
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
	if glints and camera then
		LampGlints.assign(glints, inView(near, camera.CFrame))
	end
end

local function attribute(name: string): number
	local value = Workspace:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

local function renderGlints()
	local camera = Workspace.CurrentCamera
	if glints and camera then
		LampGlints.render(glints, camera, attribute("Wetness"), attribute("RainIntensity"))
	end
end

local Controller = {}

function Controller.start()
	for _, model in CollectionService:GetTagged(TAG) do
		track(model)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(track)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(untrack)
	RunService.Heartbeat:Connect(update)
	glints = LampGlints.new()
	-- After the camera has moved this frame, so the glints are aimed from where it now is.
	RunService:BindToRenderStep("DriveLabLampGlints", Enum.RenderPriority.Camera.Value + 1, renderGlints)
end

return Controller
