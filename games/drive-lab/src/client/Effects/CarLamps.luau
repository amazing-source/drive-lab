--!strict
--[[
	One car's lamps on this client. Each lamp is a piece of the car's light mesh with its own
	SurfaceAppearance (tools/blender/split_lights.py), so a lamp glows by its EmissiveStrength
	alone; the housings never glow, nor do the rear fog lamps on a car without a rain light switch,
	which lights them as its rain light. Roblox lights added here throw the light: a beam per
	headlight and a farther one on high beam, a red glow behind each tail lamp, an amber glow at
	each indicator, a reversing light, a red glow behind each rain light, and the cabin light in the
	roof console. The cockpit's tell-tales glow with the switch they show. Each car names the pieces
	it cannot do without (its lights' `required`); every other piece is lit when the model has it.
	Only what changed is written.
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
	lights: Config.Lights,
	drlLeft: { Glow },
	drlRight: { Glow },
	projector: { Glow },
	left: { Glow },
	right: { Glow },
	position: { Glow },
	tail: { Glow },
	stop: { Glow },
	reverse: { Glow },
	rain: { Glow },
	tellTales: { [string]: { Glow } },
	beams: { Switch },
	highBeams: { Switch },
	tailGlows: { PointLight },
	blinksLeft: { Switch },
	blinksRight: { Switch },
	rainGlows: { Switch },
	reversing: Switch?,
	cabin: Switch?,
	tailShown: number,
	nightShown: number,
	shadows: boolean?,
}

local SIDES = { "Left", "Right" }
-- Each corner's housing never glows; the rear fog lamps glow only as a rain light.
local HOUSINGS = { "Light_FrontLeft", "Light_FrontRight", "Light_RearLeft", "Light_RearRight" }
local FOG = { "Light_RearLeft_Fog", "Light_RearRight_Fog" }

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

local function joined(first: { string }, second: { string }): { string }
	local list = table.clone(first)
	table.move(second, 1, #second, #list + 1, list)
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
local function cabinLight(model: Model, entry: Catalog.Entry): Switch?
	local point = entry.model.cabinLight
	local chassis = model.PrimaryPart
	if point == nil or chassis == nil then
		return nil
	end
	local offset = Vector3.new(point.right, point.up + entry.model.bodyRaise, -point.forward)
		* Units.metresToStuds(1)
	local settings = entry.lights.cabin
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

-- Whether every piece the car's lamps cannot do without has streamed in.
local function hasRequired(model: Model, names: { string }): boolean
	for _, name in names do
		if piece(model, name) == nil then
			return false
		end
	end
	return true
end

local function addBeams(lamps: Lamps, projector: BasePart)
	local headlight, high = lamps.lights.headlight, lamps.lights.highBeam
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
end

local function addSources(lamps: Lamps, model: Model)
	local indicator = lamps.lights.indicator
	for _, side in SIDES do
		local projector = piece(model, `Light_Front{side}_Projector`)
		if projector then
			addBeams(lamps, projector)
		end
		local tailPiece = piece(model, `Light_Rear{side}_Tail`)
		if tailPiece then
			local tail = attach(tailPiece, "TailGlow", CFrame.identity)
			table.insert(lamps.tailGlows, pointLight(tail, 0, 0, lamps.lights.tail.color))
		end
		local blinks = if side == "Left" then lamps.blinksLeft else lamps.blinksRight
		for _, name in { `Light_Front{side}_Modules`, `Light_Rear{side}_Indicator` } do
			local found = piece(model, name)
			if found then
				local glow = attach(found, "IndicatorGlow", CFrame.identity)
				local light = pointLight(glow, indicator.brightness, indicator.range, indicator.color)
				table.insert(blinks, switchFor(light))
			end
		end
	end
	local rain = lamps.lights.rain
	if rain then
		for _, name in FOG do
			local found = piece(model, name)
			if found then
				local glow = attach(found, "RainLightGlow", CFrame.identity)
				table.insert(
					lamps.rainGlows,
					switchFor(pointLight(glow, rain.brightness, rain.range, rain.color))
				)
			end
		end
	end
end

-- Between the reversing lamps the model has (or at its only one), facing back; nil without any.
local function reversingLight(model: Model, lights: Config.Lights): Switch?
	local found: { BasePart } = {}
	for _, name in sides("Light_Rear%s_Reverse") do
		local part = piece(model, name)
		if part then
			table.insert(found, part)
		end
	end
	if #found == 0 then
		return nil
	end
	local host = found[1]
	local sum = Vector3.zero
	for _, part in found do
		sum += part.Position
	end
	local middle = host.CFrame:PointToObjectSpace(sum / #found)
	local settings = lights.reverse
	local at = attach(host, "ReverseLight", CFrame.new(middle))
	local spot =
		spotLight(at, Enum.NormalId.Back, settings.angle, settings.brightness, settings.range, settings.color)
	return switchFor(spot)
end

-- Each tell-tale the car has a glow for and its model binding a piece for, by the switch it shows.
local function tellTales(model: Model, entry: Catalog.Entry): { [string]: { Glow } }
	local found: { [string]: { Glow } } = {}
	local specs, pieces = entry.lights.tellTales, entry.model.panelLamps
	if specs == nil or pieces == nil then
		return found
	end
	for switch, spec in specs do
		local name = pieces[switch]
		if name then
			found[switch] = glows(model, { name }, spec)
		end
	end
	return found
end

local CarLamps = {}

-- The lamps of a car once its light pieces have streamed in; nil before that.
function CarLamps.build(model: Model, entry: Catalog.Entry): Lamps?
	if not hasRequired(model, entry.lights.required) then
		return nil
	end
	local hasRain = entry.lights.rain ~= nil
	local dark: { string } = if hasRain then HOUSINGS else joined(HOUSINGS, FOG)
	for _, name in dark do
		local part = piece(model, name)
		local look = part and part:FindFirstChildOfClass("SurfaceAppearance")
		if look then
			look.EmissiveStrength = 0
		end
	end
	local glow = entry.lights.glow
	local lamps: Lamps = {
		lights = entry.lights,
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
		rain = if hasRain then glows(model, FOG, glow.fog) else {},
		tellTales = tellTales(model, entry),
		beams = {},
		highBeams = {},
		tailGlows = {},
		blinksLeft = {},
		blinksRight = {},
		rainGlows = {},
		reversing = reversingLight(model, entry.lights),
		cabin = cabinLight(model, entry),
		tailShown = -1,
		nightShown = -1,
		shadows = nil,
	}
	addSources(lamps, model)
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
	show(lamps.rain, levels.rain, daylight)
	for switch, list in lamps.tellTales do
		show(list, if Rules.tellTale(switch, lit) then 1 else 0, daylight)
	end
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
		local settings = lamps.lights.tail
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
	for _, switch in lamps.rainGlows do
		set(switch, lit.rainLight, night)
	end
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
