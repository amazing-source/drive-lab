--!strict
--[[
	One car's lamps on this client. Each lamp is a piece of the car's light mesh with its own
	SurfaceAppearance (tools/blender/split_lights.py), so a lamp glows by its EmissiveStrength
	alone; the housings and the rear fog lamps never glow. Roblox lights added here throw the
	light: a beam per headlight and a farther one on high beam, a red glow behind each tail lamp, an amber glow at each
	indicator, a reversing light, and the cabin light in the roof console. Only what changed is
	written.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage.Shared.Config.Cars.Catalog)
local Config = require(ReplicatedStorage.Shared.Config.CarLights)
local Rules = require(ReplicatedStorage.Shared.Rules.CarLights)
local Units = require(ReplicatedStorage.Shared.Units)

type Glow = { look: SurfaceAppearance, spec: Config.Glow, strength: number }
-- A light that switches with a lamp; `base` is its brightness at night.
type Switch = { light: Light, base: number, on: boolean, brightness: number }

export type Lamps = {
	drlLeft: { Glow },
	drlRight: { Glow },
	projector: { Glow },
	left: { Glow },
	right: { Glow },
	position: { Glow },
	tail: { Glow },
	stop: { Glow },
	reverse: { Glow },
	beams: { Switch },
	highBeams: { Switch },
	tailGlows: { PointLight },
	blinksLeft: { Switch },
	blinksRight: { Switch },
	reversing: Switch,
	cabin: Switch?,
	tailShown: number,
	nightShown: number,
	shadows: boolean?,
}

local SIDES = { "Left", "Right" }
-- Pieces that never glow: each corner's housing and the rear fog lamps (no switch for them).
local DARK = {
	"Light_FrontLeft",
	"Light_FrontRight",
	"Light_RearLeft",
	"Light_RearRight",
	"Light_RearLeft_Fog",
	"Light_RearRight_Fog",
}

local function piece(model: Model, name: string): BasePart?
	local found = model:FindFirstChild(name, true)
	return if found and found:IsA("BasePart") then found else nil
end

local function attach(part: BasePart, name: string, offset: CFrame): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.CFrame = offset
	attachment.Parent = part
	return attachment
end

local function colour(value: Config.Rgb): Color3
	return Color3.fromRGB(value.r, value.g, value.b)
end

local function pointLight(parent: Instance, brightness: number, range: number, color: Config.Rgb): PointLight
	local glow = Instance.new("PointLight")
	glow.Brightness = brightness
	glow.Range = range
	glow.Color = colour(color)
	glow.Shadows = false
	glow.Enabled = false
	glow.Parent = parent
	return glow
end

local function spotLight(
	parent: Instance,
	face: Enum.NormalId,
	angle: number,
	brightness: number,
	range: number,
	color: Config.Rgb
): SpotLight
	local spot = Instance.new("SpotLight")
	spot.Face = face
	spot.Angle = angle
	spot.Brightness = brightness
	spot.Range = range
	spot.Color = colour(color)
	spot.Shadows = false
	spot.Enabled = false
	spot.Parent = parent
	return spot
end

-- The glows of the named pieces that are present, tinted once and dark to begin with.
local function glows(model: Model, names: { string }, spec: Config.Glow): { Glow }
	local found = {}
	for _, name in names do
		local part = piece(model, name)
		local look = part and part:FindFirstChildOfClass("SurfaceAppearance")
		if look then
			look.EmissiveTint = colour(spec.tint)
			look.EmissiveStrength = 0
			local filter = spec.filter
			if filter then
				look.Color = colour(filter)
			end
			table.insert(found, { look = look, spec = spec, strength = 0 })
		end
	end
	return found
end

local function concat(...: { Glow }): { Glow }
	local list = {}
	for index = 1, select("#", ...) do
		for _, glow in (select(index, ...)) do
			table.insert(list, glow)
		end
	end
	return list
end

local function sides(pattern: string): { string }
	return { string.format(pattern, "Left"), string.format(pattern, "Right") }
end

local function switchFor(light: Light): Switch
	return { light = light, base = light.Brightness, on = false, brightness = light.Brightness }
end

-- The roof console's lamp, from the binding's point (metres from the centre of mass, before the
-- body was raised) on the rig's mass box, facing down.
local function cabinLight(model: Model): Switch?
	local name = model:GetAttribute("Car")
	local entry = if typeof(name) == "string" then Catalog[name] else nil
	local point = entry and entry.model.cabinLight
	local chassis = model.PrimaryPart
	if entry == nil or point == nil or chassis == nil then
		return nil
	end
	local offset = Vector3.new(point.right, point.up + entry.model.bodyRaise, -point.forward)
		* Units.metresToStuds(1)
	local settings = Config.CABIN
	local at = attach(chassis, "CabinLight", CFrame.new(offset))
	local spot = spotLight(
		at,
		Enum.NormalId.Bottom,
		settings.angle,
		settings.brightness,
		settings.range,
		settings.color
	)
	return switchFor(spot)
end

-- On while its lamp is lit and the scene has any night in it, at its brightness times `night`.
local function set(switch: Switch?, on: boolean, night: number)
	if switch == nil then
		return
	end
	local shown = on and night > 0.01
	if switch.on ~= shown then
		switch.on = shown
		switch.light.Enabled = shown
	end
	local brightness = switch.base * night
	if shown and math.abs(brightness - switch.brightness) > 1e-3 then
		switch.brightness = brightness
		switch.light.Brightness = brightness
	end
end

local function show(list: { Glow }, level: number, daylight: number)
	for _, glow in list do
		local spec = glow.spec
		local strength = Rules.strength(level, spec.night, spec.day, daylight)
		if math.abs(strength - glow.strength) > 1e-3 then
			glow.strength = strength
			glow.look.EmissiveStrength = strength
		end
	end
end

-- The pieces the lamps cannot do without, or nil while any has not streamed in.
local function required(model: Model): { [string]: BasePart }?
	local names = {}
	for _, lamp in
		{ "Front%s_Projector", "Front%s_Modules", "Rear%s_Tail", "Rear%s_Indicator", "Rear%s_Reverse" }
	do
		for _, name in sides("Light_" .. lamp) do
			table.insert(names, name)
		end
	end
	local parts = {}
	for _, name in names do
		local part = piece(model, name)
		if part == nil then
			return nil
		end
		parts[name] = part
	end
	return parts
end

local function addSources(lamps: Lamps, parts: { [string]: BasePart })
	local headlight, high, indicator = Config.HEADLIGHT, Config.HIGH_BEAM, Config.INDICATOR
	for _, side in SIDES do
		local projector = parts[`Light_Front{side}_Projector`]
		local front = CFrame.new(0, 0, -projector.Size.Z / 2) * CFrame.Angles(headlight.pitch, 0, 0)
		local at = attach(projector, "HeadlightBeam", front)
		local spot = spotLight(
			at,
			Enum.NormalId.Front,
			headlight.angle,
			headlight.brightness,
			headlight.range,
			headlight.color
		)
		table.insert(lamps.beams, switchFor(spot))
		local level = CFrame.new(0, 0, -projector.Size.Z / 2) * CFrame.Angles(high.pitch, 0, 0)
		local reach = attach(projector, "HighBeam", level)
		local far =
			spotLight(reach, Enum.NormalId.Front, high.angle, high.brightness, high.range, headlight.color)
		table.insert(lamps.highBeams, switchFor(far))
		local tail = attach(parts[`Light_Rear{side}_Tail`], "TailGlow", CFrame.identity)
		table.insert(lamps.tailGlows, pointLight(tail, 0, 0, Config.TAIL.color))
		local blinks = if side == "Left" then lamps.blinksLeft else lamps.blinksRight
		for _, name in { `Light_Front{side}_Modules`, `Light_Rear{side}_Indicator` } do
			local glow = attach(parts[name], "IndicatorGlow", CFrame.identity)
			local light = pointLight(glow, indicator.brightness, indicator.range, indicator.color)
			table.insert(blinks, switchFor(light))
		end
	end
end

-- Between the two reversing lamps, facing back.
local function reversingLight(parts: { [string]: BasePart }): Switch
	local left, right = parts.Light_RearLeft_Reverse, parts.Light_RearRight_Reverse
	local middle = left.CFrame:PointToObjectSpace((left.Position + right.Position) / 2)
	local settings = Config.REVERSE
	local at = attach(left, "ReverseLight", CFrame.new(middle))
	local spot =
		spotLight(at, Enum.NormalId.Back, settings.angle, settings.brightness, settings.range, settings.color)
	return switchFor(spot)
end

local CarLamps = {}

-- The lamps of a car once its light pieces have streamed in; nil before that.
function CarLamps.build(model: Model): Lamps?
	local parts = required(model)
	if parts == nil then
		return nil
	end
	for _, name in DARK do
		local part = piece(model, name)
		local look = part and part:FindFirstChildOfClass("SurfaceAppearance")
		if look then
			look.EmissiveStrength = 0
		end
	end
	local glow = Config.GLOW
	local lamps: Lamps = {
		drlLeft = glows(model, { "Light_FrontLeft_Drl" }, glow.drl),
		drlRight = glows(model, { "Light_FrontRight_Drl" }, glow.drl),
		projector = glows(model, sides("Light_Front%s_Projector"), glow.projector),
		left = concat(
			glows(model, { "Light_FrontLeft_Modules" }, glow.frontIndicator),
			glows(model, { "Light_RearLeft_Indicator" }, glow.rearIndicator)
		),
		right = concat(
			glows(model, { "Light_FrontRight_Modules" }, glow.frontIndicator),
			glows(model, { "Light_RearRight_Indicator" }, glow.rearIndicator)
		),
		position = concat(
			glows(model, sides("Light_Front%s_Marker"), glow.frontMarker),
			glows(model, sides("Light_Rear%s_Marker"), glow.rearMarker),
			glows(model, sides("Light_Rear%s_Plate"), glow.plate)
		),
		tail = glows(model, sides("Light_Rear%s_Tail"), glow.tail),
		stop = glows(model, sides("Light_Rear%s_Bar"), glow.stop),
		reverse = glows(model, sides("Light_Rear%s_Reverse"), glow.reverse),
		beams = {},
		highBeams = {},
		tailGlows = {},
		blinksLeft = {},
		blinksRight = {},
		reversing = reversingLight(parts),
		cabin = cabinLight(model),
		tailShown = -1,
		nightShown = -1,
		shadows = nil,
	}
	addSources(lamps, parts)
	return lamps
end

-- Shows what Rules/CarLights decided. `daylight` is Rules.daylight's 0 (night) to 1 (day);
-- `shadows` lets the beams and the cabin light cast shadows (each shadowed light costs a pass).
function CarLamps.apply(lamps: Lamps, lit: Rules.Lit, daylight: number, shadows: boolean)
	local levels = Rules.levels(lit, Config.TAIL_SHARE, Config.TUNING.highBeamLevel)
	show(lamps.drlLeft, levels.drlLeft, daylight)
	show(lamps.drlRight, levels.drlRight, daylight)
	show(lamps.projector, levels.projector, daylight)
	show(lamps.left, levels.left, daylight)
	show(lamps.right, levels.right, daylight)
	show(lamps.position, levels.position, daylight)
	show(lamps.tail, levels.tail, daylight)
	show(lamps.stop, levels.stop, daylight)
	show(lamps.reverse, levels.reverse, daylight)
	local tail = levels.tail

	local night = 1 - daylight
	for _, switch in lamps.beams do
		set(switch, lit.headlights, night)
	end
	for _, switch in lamps.highBeams do
		set(switch, lit.highBeam, night)
	end
	if tail ~= lamps.tailShown or night ~= lamps.nightShown then
		lamps.tailShown = tail
		lamps.nightShown = night
		local settings = Config.TAIL
		for _, glow in lamps.tailGlows do
			glow.Enabled = tail > 0 and night > 0.01
			glow.Range = if lit.brake then settings.brakeRange else settings.range
			glow.Brightness = night * (if lit.brake then settings.brakeBrightness else settings.brightness)
		end
	end
	for _, switch in lamps.blinksLeft do
		set(switch, lit.left, night)
	end
	for _, switch in lamps.blinksRight do
		set(switch, lit.right, night)
	end
	set(lamps.reversing, lit.reverse, night)
	set(lamps.cabin, lit.cabin, night)
	if shadows ~= lamps.shadows then
		lamps.shadows = shadows
		for _, switch in lamps.beams do
			switch.light.Shadows = shadows
		end
		local cabin = lamps.cabin
		if cabin then
			cabin.light.Shadows = shadows
		end
	end
end

return CarLamps
