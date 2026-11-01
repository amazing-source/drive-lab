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
	Which pieces play which lamp is the car's (its lights' `pieces`, Config/CarLights.HOUSE_PIECES
	otherwise); a piece in several shows the brightest, and only its indicator while that side's
	indicator runs. A sequential turn lamp lights its pieces inner to outer on each flash of the
	turn signal (Rules/CarLights.sweepBars). Only what changed is written.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage.Shared.Config.Cars.Catalog)
local Config = require(ReplicatedStorage.Shared.Config.CarLights)
local Rules = require(ReplicatedStorage.Shared.Rules.CarLights)
local Units = require(ReplicatedStorage.Shared.Units)

type Glow = { look: SurfaceAppearance, spec: Config.Glow, strength: number }
-- One lamp piece's glow, shared by every role it plays: what it shows, and this frame's brightest
-- request with its tint.
type LookState = {
	look: SurfaceAppearance,
	strength: number,
	tint: Config.Rgb,
	want: number,
	wantTint: Config.Rgb,
}
-- A piece in one role, with that role's glow.
type RoleGlow = { state: LookState, spec: Config.Glow }
-- A tell-tale LED with no SurfaceAppearance: lit, it is Neon in its tint, darker for a dimmer glow
-- (Neon's glow follows its colour); unlit, plastic in the colour it came with.
type Led = { part: BasePart, spec: Config.Glow, unlit: Color3, strength: number }
-- A light that switches with a lamp; `base` is its brightness at night.
type Switch = { light: Light, base: number, on: boolean, brightness: number }

export type Lamps = {
	lights: Config.Lights,
	pieces: Config.Pieces,
	looks: { LookState },
	drlLeft: { RoleGlow },
	drlRight: { RoleGlow },
	projector: { RoleGlow },
	left: { RoleGlow },
	right: { RoleGlow },
	position: { RoleGlow },
	tail: { RoleGlow },
	stop: { RoleGlow },
	reverse: { RoleGlow },
	sweepLeft: { RoleGlow },
	sweepRight: { RoleGlow },
	-- Each side's indicator pieces, whose other roles give way while that indicator runs.
	indicatorLeft: { [LookState]: true },
	indicatorRight: { [LookState]: true },
	rain: { Glow },
	tellTales: { [string]: { Glow } },
	leds: { [string]: { Led } },
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
-- An LED that arrives glowing (Neon) is shown unlit at this much darker than its tint.
local LED_UNLIT_DARKENING = 0.85
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

-- The role glows of the named pieces that are present, each sharing its piece's state with its
-- other roles; a piece new to `states` starts dark in this role's tint.
local function roleGlows(
	model: Model,
	pieces: { Config.Piece }?,
	specs: { [string]: Config.Glow },
	states: { [SurfaceAppearance]: LookState },
	all: { LookState }
): { RoleGlow }
	local found: { RoleGlow } = {}
	if pieces == nil then
		return found
	end
	for _, item in pieces do
		local part = piece(model, item.name)
		local look = part and part:FindFirstChildOfClass("SurfaceAppearance")
		local spec = specs[item.glow]
		if look and spec then
			local state = states[look]
			if state == nil then
				look.EmissiveTint = colour(spec.tint)
				look.EmissiveStrength = 0
				local filter = spec.filter
				if filter then
					look.Color = colour(filter)
				end
				state = { look = look, strength = 0, tint = spec.tint, want = 0, wantTint = spec.tint }
				states[look] = state
				table.insert(all, state)
			end
			table.insert(found, { state = state, spec = spec })
		end
	end
	return found
end

local function setOf(...: { RoleGlow }): { [LookState]: true }
	local set: { [LookState]: true } = {}
	for index = 1, select("#", ...) do
		for _, glow in (select(index, ...)) do
			set[glow.state] = true
		end
	end
	return set
end

-- The parts of the named pieces that are present.
local function parts(model: Model, pieces: { Config.Piece }?): { BasePart }
	local found: { BasePart } = {}
	if pieces == nil then
		return found
	end
	for _, item in pieces do
		local part = piece(model, item.name)
		if part then
			table.insert(found, part)
		end
	end
	return found
end

local function joined(first: { string }, second: { string }): { string }
	local list = table.clone(first)
	table.move(second, 1, #second, #list + 1, list)
	return list
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

-- Asks each piece in `list` for `level` of its role's glow, unless it gives way (`skip`, `other`);
-- the brightest request of the frame wins.
local function want(
	list: { RoleGlow },
	level: number,
	daylight: number,
	skip: { [LookState]: true }?,
	other: { [LookState]: true }?
)
	for _, glow in list do
		local state = glow.state
		if not ((skip and skip[state]) or (other and other[state])) then
			local spec = glow.spec
			local strength = Rules.strength(level, spec.night, spec.day, daylight)
			if strength > state.want then
				state.want, state.wantTint = strength, spec.tint
			end
		end
	end
end

-- Writes each piece's winning request where it changed, and clears the requests for the next frame.
local function flush(looks: { LookState })
	for _, state in looks do
		if math.abs(state.want - state.strength) > 1e-3 then
			state.strength = state.want
			state.look.EmissiveStrength = state.want
		end
		if state.want > 0 and state.wantTint ~= state.tint then
			state.tint = state.wantTint
			state.look.EmissiveTint = colour(state.wantTint)
		end
		state.want, state.wantTint = 0, state.tint
	end
end

-- A sequential lamp's pieces: lit inner to outer on each flash of its turn signal (`turnFor`
-- seconds in), or flashing together at `level` (the hazards).
local function sweep(list: { RoleGlow }, turnFor: number?, level: number, step: number, daylight: number)
	if turnFor == nil or step <= 0 then
		want(list, level, daylight)
		return
	end
	local tuning = Config.TUNING
	local bars = Rules.sweepBars(turnFor, tuning.blinkHz, tuning.blinkOnShare, #list, step)
	for index, glow in list do
		want({ glow }, if index <= bars then 1 else 0, daylight)
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

-- An amber glow (red on a US car's rear pieces) at each named indicator piece that is present.
local function addIndicators(
	model: Model,
	indicator: {
		range: number,
		brightness: number,
		color: Config.Rgb,
		rearColor: Config.Rgb?,
	},
	blinks: { Switch },
	list: { Config.Piece }?
)
	if list == nil then
		return
	end
	for _, item in list do
		local found = piece(model, item.name)
		if found then
			local color = indicator.color
			local rear = indicator.rearColor
			if item.glow == "rearIndicator" and rear then
				color = rear
			end
			local glow = attach(found, "IndicatorGlow", CFrame.identity)
			table.insert(blinks, switchFor(pointLight(glow, indicator.brightness, indicator.range, color)))
		end
	end
end

local function addSources(lamps: Lamps, model: Model)
	local indicator = lamps.lights.indicator
	local pieces = lamps.pieces
	for _, projector in parts(model, pieces.projector) do
		addBeams(lamps, projector)
	end
	for _, tailPiece in parts(model, pieces.tail) do
		local tail = attach(tailPiece, "TailGlow", CFrame.identity)
		table.insert(lamps.tailGlows, pointLight(tail, 0, 0, lamps.lights.tail.color))
	end
	for _, side in SIDES do
		local blinks = if side == "Left" then lamps.blinksLeft else lamps.blinksRight
		local flashing = if side == "Left" then pieces.left else pieces.right
		local sweeping = if side == "Left" then pieces.sweepLeft else pieces.sweepRight
		addIndicators(model, indicator, blinks, flashing)
		addIndicators(model, indicator, blinks, sweeping)
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
local function reversingLight(model: Model, lights: Config.Lights, pieces: Config.Pieces): Switch?
	local found = parts(model, pieces.reverse)
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

-- Each tell-tale the car has a glow for and its model binding a piece for, by the switch it shows:
-- a glow where the piece has a SurfaceAppearance, an LED where it has none.
local function tellTales(model: Model, entry: Catalog.Entry): ({ [string]: { Glow } }, { [string]: { Led } })
	local looks: { [string]: { Glow } } = {}
	local leds: { [string]: { Led } } = {}
	local specs, pieces = entry.lights.tellTales, entry.model.panelLamps
	if specs == nil or pieces == nil then
		return looks, leds
	end
	for switch, spec in specs do
		local name = pieces[switch]
		local part = name and piece(model, name)
		if part and part:FindFirstChildOfClass("SurfaceAppearance") then
			looks[switch] = glows(model, { part.Name }, spec)
		elseif part then
			local unlit = if part.Material == Enum.Material.Neon
				then colour(spec.tint):Lerp(Color3.new(), LED_UNLIT_DARKENING)
				else part.Color
			part.Material = Enum.Material.SmoothPlastic
			part.Color = unlit
			leds[switch] = { { part = part, spec = spec, unlit = unlit, strength = 0 } }
		end
	end
	return looks, leds
end

local function showLeds(list: { Led }, level: number, daylight: number)
	for _, led in list do
		local spec = led.spec
		local strength = Rules.strength(level, spec.night, spec.day, daylight)
		if math.abs(strength - led.strength) > 1e-3 then
			led.strength = strength
			local lit = strength > 0
			led.part.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
			led.part.Color = if lit
				then Color3.new():Lerp(colour(spec.tint), Rules.ledShare(strength, spec.day))
				else led.unlit
		end
	end
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
	local specs: { [string]: Config.Glow } = glow :: any
	local pieces = entry.lights.pieces or Config.HOUSE_PIECES
	local states: { [SurfaceAppearance]: LookState } = {}
	local looks: { LookState } = {}
	local function role(list: { Config.Piece }?): { RoleGlow }
		return roleGlows(model, list, specs, states, looks)
	end
	local drlLeft, drlRight, projector = role(pieces.drlLeft), role(pieces.drlRight), role(pieces.projector)
	local left, right, position = role(pieces.left), role(pieces.right), role(pieces.position)
	local tail, stop, reverse = role(pieces.tail), role(pieces.stop), role(pieces.reverse)
	local sweepLeft, sweepRight = role(pieces.sweepLeft), role(pieces.sweepRight)
	local lamps: Lamps = {
		lights = entry.lights,
		pieces = pieces,
		looks = looks,
		drlLeft = drlLeft,
		drlRight = drlRight,
		projector = projector,
		left = left,
		right = right,
		position = position,
		tail = tail,
		stop = stop,
		reverse = reverse,
		sweepLeft = sweepLeft,
		sweepRight = sweepRight,
		indicatorLeft = setOf(left, sweepLeft),
		indicatorRight = setOf(right, sweepRight),
		rain = if hasRain then glows(model, FOG, glow.fog) else {},
		tellTales = {},
		leds = {},
		beams = {},
		highBeams = {},
		tailGlows = {},
		blinksLeft = {},
		blinksRight = {},
		rainGlows = {},
		reversing = reversingLight(model, entry.lights, pieces),
		cabin = cabinLight(model, entry),
		tailShown = -1,
		nightShown = -1,
		shadows = nil,
	}
	lamps.tellTales, lamps.leds = tellTales(model, entry)
	addSources(lamps, model)
	return lamps
end

-- Shows what Rules/CarLights decided. `daylight` is Rules.daylight's 0 (night) to 1 (day);
-- `shadows` lets the beams and the cabin light cast shadows (each shadowed light costs a pass).
function CarLamps.apply(lamps: Lamps, lit: Rules.Lit, daylight: number, shadows: boolean)
	local levels = Rules.levels(lit, Config.TAIL_SHARE, Config.TUNING.highBeamLevel)
	local quietLeft = if lit.leftRunning then lamps.indicatorLeft else nil
	local quietRight = if lit.rightRunning then lamps.indicatorRight else nil
	want(lamps.drlLeft, levels.drlLeft, daylight)
	want(lamps.drlRight, levels.drlRight, daylight)
	want(lamps.projector, levels.projector, daylight)
	want(lamps.left, levels.left, daylight)
	want(lamps.right, levels.right, daylight)
	want(lamps.position, levels.position, daylight, quietLeft, quietRight)
	want(lamps.tail, levels.tail, daylight, quietLeft, quietRight)
	want(lamps.stop, levels.stop, daylight, quietLeft, quietRight)
	want(lamps.reverse, levels.reverse, daylight)
	local step = lamps.pieces.sweepStep or 0
	sweep(lamps.sweepLeft, lit.leftTurnFor, levels.left, step, daylight)
	sweep(lamps.sweepRight, lit.rightTurnFor, levels.right, step, daylight)
	flush(lamps.looks)
	show(lamps.rain, levels.rain, daylight)
	for switch, list in lamps.tellTales do
		show(list, if Rules.tellTale(switch, lit) then 1 else 0, daylight)
	end
	for switch, list in lamps.leds do
		showLeds(list, if Rules.tellTale(switch, lit) then 1 else 0, daylight)
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
