--!strict
--[[
	Turns a car's merged 3D manifest (drive-lab-assets/<car>/work/manifest) into its model binding
	(Config/Cars/Binding): checks that every part's group leads to the body, moves every point from
	the manifest's frame (the rear-axle midpoint on the ground) to the rig's (the centre of mass),
	and lists what the binding still lacks instead of inventing it: a part the settings name that the
	manifest does not carry yet is pending, and a car with anything pending stays out of the catalog.
	A feature a car does not have (a drive-mode knob, a display screen, shift lights) is simply left
	out of its settings. Pure: tools/car_binding reads and writes the files (tools/CarBindings).
]]
local Binding = require("../src/shared/Config/Cars/Binding")
local Hinge = require("../src/shared/Rules/Hinge")
local Types = require("../src/shared/Config/Cars/Types")

export type Point = Hinge.CarPoint

export type Screen =
	{ centre: Point, width_m: number, height_m: number, normal: Point, tilt_back_deg: number }

export type Part = {
	name: string,
	group: string,
	motion: string,
	pivot: Point?,
	axis: Point?,
	-- A travel from rest, or the angles of its positions with the modelled rest first.
	range: (number | { number })?,
	positive: string?,
	mesh: boolean?,
	screen: Screen?,
	outlet: { centre: Point, axis: Point, diameter_m: number }?,
	-- A "gate" part (an H-pattern lever): its two axes and each gear's [side, fore] angles.
	axis_fore: Point?,
	axis_side: Point?,
	gates_rad: { [string]: { number } }?,
	-- The knob's ball with the lever in neutral, and how far it goes down into reverse's lockout.
	knob: { centre: Point, radius_m: number }?,
	push_m: number?,
	-- The knob centre's offset from its neutral place in each gate (Blender's own gate pose); specs only.
	knob_offset_m: { [string]: Point }?,
}

-- Named points with no part, such as the driver's hip point.
export type Manifest = { parts: { Part }, points: { [string]: Point }? }

-- What the writer is told about a car beyond its manifest: which parts play which role, and the
-- values the manifest does not carry yet, each with why it has the value it has.
export type Settings = {
	-- Each corner's group, front left first, and the part in it whose bounding box is the tyre:
	-- the rig finds the ground and the model's scale from it.
	wheelGroups: { string },
	tyreSuffix: string,
	calipers: { { string } },
	steeringWheel: string,
	-- Groups that name no part: the part that moves them, or the body.
	assemblies: { [string]: string },
	door: { group: string, hinge: string }?,
	controls: { string },
	pedals: { string },
	modeKnob: { part: string, modes: { string } }?,
	glazing: { string },
	-- The live display's screen part; nil on a car with none (its gauges are needles).
	screen: string?,
	-- An analog cluster's needle parts (rotary, each with its dial's sweep as its range), and its
	-- small live screens by name, each a part carrying a `screen`.
	needles: { string }?,
	displays: { [string]: string }?,
	exhaust: { string },
	shiftLights: { string }?,
	panelLamps: { [string]: string }?,
	-- The H-pattern gear lever's "gate" part.
	shifter: string?,
	steeringWheelLift: number,
	bodyRaise: number,
	hullClearance: number,
	-- The driver's hip point, by its name among the manifest's points.
	hipPoint: string,
	-- The windscreen's corners among the manifest's points, in the binding's order: top left, top
	-- right, bottom right, bottom left, the driver's left first.
	windshield: { string },
	-- Each start-up control's rest and other end, as angles from its modelled pose.
	controlStates: { [string]: { rest: number, other: number } },
	-- The wiper's arm (a hinge part, modelled parked), its blade's two ends among the manifest's
	-- points, inner first, and the washer's jets (manifest frame, as the manifest has none).
	wiper: { arm: string, blade: { string }, nozzles: { Point } }?,
}

local ManifestBinding = {}

ManifestBinding.BODY = "Chassis"

local MAX_DEPTH = 8
-- An exterior lamp: Light_<corner>_<role>, lit by the car's lamp set (Config/Cars/<Car>/Lights).
local CORNERS = { FrontLeft = true, FrontRight = true, RearLeft = true, RearRight = true }

function ManifestBinding.index(manifest: Manifest): { [string]: Part }
	local byName: { [string]: Part } = {}
	for _, part in manifest.parts do
		byName[part.name] = part
	end
	return byName
end

-- The group a part rides: the body, another part, or an assembly the settings name.
local function parentGroup(byName: { [string]: Part }, settings: Settings, part: Part): string?
	local group = part.group
	if group == ManifestBinding.BODY or group == part.name then
		return nil
	end
	if byName[group] then
		return group
	end
	local mover = settings.assemblies[group]
	if mover == nil or mover == ManifestBinding.BODY or mover == part.name then
		return nil
	end
	return mover
end

-- Everything wrong with the manifest's names and groups: a name used twice, a group that names
-- neither the body, a part nor a known assembly, a chain that loops or never reaches the body.
function ManifestBinding.problems(manifest: Manifest, settings: Settings): { string }
	local found: { string } = {}
	local byName: { [string]: Part } = {}
	for _, part in manifest.parts do
		if byName[part.name] then
			table.insert(found, `{part.name} is named twice`)
		end
		byName[part.name] = part
	end
	for _, part in manifest.parts do
		local group = part.group
		local known = group == ManifestBinding.BODY
			or byName[group] ~= nil
			or settings.assemblies[group] ~= nil
		if not known then
			table.insert(
				found,
				`{part.name} rides {group}, which is neither the body, a part nor an assembly`
			)
			continue
		end
		local seen: { [string]: boolean } = { [part.name] = true }
		local current: Part? = part
		local depth = 0
		while current do
			local parent = parentGroup(byName, settings, current)
			if parent == nil then
				break
			end
			depth += 1
			if seen[parent] or depth > MAX_DEPTH then
				table.insert(found, `{part.name}'s chain loops at {parent}`)
				break
			end
			seen[parent] = true
			current = byName[parent]
		end
	end
	table.sort(found)
	return found
end

-- The part each part rides, by name, walking past parts that do not move (a static pivot such as
-- the steering column rides the body with everything on it). Nil for the body.
function ManifestBinding.mover(byName: { [string]: Part }, settings: Settings, part: Part): string?
	local parent = parentGroup(byName, settings, part)
	while parent do
		local carrier = byName[parent]
		if carrier == nil or carrier.motion ~= "static" then
			return parent
		end
		parent = parentGroup(byName, settings, carrier)
	end
	return nil
end

-- Whether the manifest carries any exterior lamp: an emissive part named Light_<corner>_<role>.
function ManifestBinding.hasLamps(manifest: Manifest): boolean
	for _, part in manifest.parts do
		local corner, role = string.match(part.name, "^Light_(%a+)_(%a+)$")
		if part.motion == "emissive" and corner and role and CORNERS[corner] then
			return true
		end
	end
	return false
end

-- The windscreen's corners from the centre of mass, or nil if the manifest lacks any of them.
local function windscreen(points: { [string]: Point }, settings: Settings, centre: Point): { Point }?
	if #settings.windshield == 0 then
		return nil
	end
	local corners: { Point } = {}
	for _, name in settings.windshield do
		local point = points[name]
		if point == nil then
			return nil
		end
		table.insert(corners, ManifestBinding.toRig(point, centre))
	end
	return corners
end

-- The centre of mass in the manifest's frame, where the rig puts it (Car/CarRig rigFrame).
function ManifestBinding.centreOfMass(car: Types.CarConfig): Point
	return { forward = car.wheelbase * car.frontWeightShare, right = 0, up = car.cgHeight }
end

local function round(value: number): number
	return math.round(value * 1e5) / 1e5
end

function ManifestBinding.toRig(point: Point, centre: Point): Point
	return {
		forward = round(point.forward - centre.forward),
		right = round(point.right - centre.right),
		up = round(point.up - centre.up),
	}
end

local function direction(axis: Point): Point
	local length = math.sqrt(axis.forward ^ 2 + axis.right ^ 2 + axis.up ^ 2)
	return {
		forward = round(axis.forward / length),
		right = round(axis.right / length),
		up = round(axis.up / length),
	}
end

-- A part's travel from its modelled rest: the range itself, or its last position less its first.
function ManifestBinding.travel(part: Part): number?
	local range = part.range
	if type(range) == "number" then
		return range
	elseif type(range) == "table" and #range >= 2 then
		return range[#range] - range[1]
	end
	return nil
end

local function need<T>(value: T?, what: string): T
	assert(value ~= nil, what)
	return value
end

local function hinge(
	byName: { [string]: Part },
	name: string,
	centre: Point,
	state: { rest: number, other: number }?
): Binding.Hinge
	local part = need(byName[name], `the manifest has no {name}`)
	local pivot = need(part.pivot, `{name} has no pivot`)
	local axis = need(part.axis, `{name} has no axis`)
	return {
		part = name,
		pivot = ManifestBinding.toRig(pivot, centre),
		axis = direction(axis),
		rest = if state and state.rest ~= 0 then round(state.rest) else nil,
		travel = if state then round(state.other - state.rest) else ManifestBinding.travel(part),
	}
end

-- The car's binding from its manifest, and what it still lacks, in words.
function ManifestBinding.binding(
	manifest: Manifest,
	car: Types.CarConfig,
	settings: Settings
): (Binding.CarModel, { string })
	local problems = ManifestBinding.problems(manifest, settings)
	assert(#problems == 0, `the manifest has problems: {table.concat(problems, "; ")}`)
	local byName = ManifestBinding.index(manifest)
	local centre = ManifestBinding.centreOfMass(car)
	local pending: { string } = {}
	-- Whether the manifest carries a part the settings name; one it lacks is listed as pending.
	local function has(name: string, what: string): boolean
		if byName[name] then
			return true
		end
		table.insert(pending, `{what}: the manifest has no {name}`)
		return false
	end

	-- The tyre stands for its corner (the rig's ground and scale); the rest of the corner rides it.
	local wheels: { string } = {}
	local parents: { [string]: string } = {}
	local corner: { [string]: string } = {}
	for _, group in settings.wheelGroups do
		local tyre = group .. settings.tyreSuffix
		has(tyre, "wheels")
		table.insert(wheels, tyre)
		corner[group] = tyre
	end
	local door = settings.door
	local doorParts: { string } = {}
	for _, part in manifest.parts do
		if corner[part.group] and part.name ~= corner[part.group] then
			parents[part.name] = corner[part.group]
		elseif door and part.group == door.group then
			table.insert(doorParts, part.name)
		else
			local mover = ManifestBinding.mover(byName, settings, part)
			if mover and not corner[mover] then
				parents[part.name] = mover
			end
		end
	end
	table.sort(doorParts)

	local steeringHub = nil
	if has(settings.steeringWheel, "steering wheel") then
		local wheel = byName[settings.steeringWheel]
		local wheelPivot = need(wheel.pivot, "the steering wheel has no pivot")
		local wheelAxis = need(wheel.axis, "the steering wheel has no axis")
		steeringHub = if wheel.mesh == false
			then { pivot = ManifestBinding.toRig(wheelPivot, centre), axis = direction(wheelAxis) }
			else nil
	end

	local doorBinding = nil
	if door and has(door.hinge, "door") then
		local doorHinge = hinge(byName, door.hinge, centre)
		doorBinding = {
			parts = doorParts,
			pivot = doorHinge.pivot,
			axis = doorHinge.axis,
			openAngle = need(doorHinge.travel, `{door.hinge} has no range`),
		}
	end

	local controls: { [string]: Binding.Hinge } = {}
	for _, name in settings.controls do
		if has(name, "controls") then
			local state = need(settings.controlStates[name], `{name} has no rest and other end`)
			controls[name] = hinge(byName, name, centre, state)
		end
	end
	-- Controllers/DriverLegs turns a pedal about the seat's x, the car's right, by its footwell's
	-- signed travel; so every pedal's axis points right, and its travel carries the sign that presses
	-- it (a manifest's positive turn presses it).
	local pedals: { Binding.Hinge } = {}
	for _, name in settings.pedals do
		if has(name, "pedals") then
			local pedal = hinge(byName, name, centre)
			if pedal.axis.right < 0 then
				local axis = pedal.axis
				pedal.axis = { forward = -axis.forward + 0, right = -axis.right, up = -axis.up + 0 }
				pedal.travel = if pedal.travel then -pedal.travel else nil
			end
			table.insert(pedals, pedal)
			if byName[name].positive == nil then
				table.insert(pending, `{name}: no "positive" note; which way presses it is unchecked`)
			end
		end
	end

	local modeKnob = nil
	local knob = settings.modeKnob
	if knob and has(knob.part, "drive-mode knob") then
		local detents = byName[knob.part].range
		assert(type(detents) == "table" and #detents == #knob.modes, `{knob.part} has a position per mode`)
		local positions: { [string]: number } = {}
		for index, mode in knob.modes do
			positions[mode] = round(detents[index] - detents[1])
		end
		modeKnob = { hinge = hinge(byName, knob.part, centre), positions = positions }
	end

	local function screenOf(name: string): Binding.Screen
		local screen: Screen = need(byName[name].screen, `{name} has no screen`)
		return {
			forward = round(screen.centre.forward - centre.forward),
			right = round(screen.centre.right - centre.right),
			up = round(screen.centre.up - centre.up),
			width = round(screen.width_m),
			height = round(screen.height_m),
			tilt = round(math.rad(screen.tilt_back_deg)),
		}
	end
	local cluster = { forward = 0, right = 0, up = 0, width = 0, height = 0, tilt = 0 }
	local screenName = settings.screen
	local needleNames = settings.needles or {}
	if screenName == nil then
		if #needleNames == 0 then
			table.insert(pending, "cluster: no live display screen named")
		end
	elseif has(screenName, "cluster") then
		cluster = screenOf(screenName)
	end

	-- A needle's range runs from the dial's zero to its full scale, as angles from its modelled pose.
	local needles: { [string]: Binding.Hinge } = {}
	for _, name in needleNames do
		if has(name, "needles") then
			local range = byName[name].range
			if type(range) == "table" and #range >= 2 then
				needles[name] = hinge(byName, name, centre, { rest = range[1], other = range[#range] })
			else
				table.insert(pending, `needles: {name} has no measured sweep (its range)`)
			end
		end
	end
	local displays: { [string]: Binding.Screen } = {}
	for display, name in settings.displays or {} do
		if has(name, `displays ({display})`) then
			displays[display] = screenOf(name)
		end
	end

	local outlets = {}
	for _, name in settings.exhaust do
		if has(name, "exhaust") then
			local outlet = need(byName[name].outlet, `{name} has no outlet`)
			table.insert(outlets, {
				centre = ManifestBinding.toRig(outlet.centre, centre),
				axis = direction(outlet.axis),
				diameter = round(outlet.diameter_m),
			})
		end
	end

	for _, set in settings.calipers do
		for _, name in set do
			has(name, "calipers")
		end
	end
	for _, name in settings.glazing do
		has(name, "glazing")
	end
	local shiftLights = settings.shiftLights
	if shiftLights then
		for _, name in shiftLights do
			has(name, "shift lights")
		end
	end
	local panelLamps = settings.panelLamps
	if panelLamps then
		for _, name in panelLamps do
			has(name, "panel lamps")
		end
	end

	local points = manifest.points or {}
	local seat = { forward = 0, right = 0, up = 0 }
	local hip = points[settings.hipPoint]
	if hip then
		seat = ManifestBinding.toRig(hip, centre)
	else
		table.insert(pending, `seat: the manifest has no point {settings.hipPoint}`)
	end
	local windshield = windscreen(points, settings, centre)
	if windshield == nil then
		table.insert(pending, "windshield: no windscreen corners in the manifest")
	end
	if not ManifestBinding.hasLamps(manifest) then
		table.insert(pending, "lamps: no exterior lamps in the manifest")
	end

	local wiper = nil
	local wiperSettings = settings.wiper
	if wiperSettings and has(wiperSettings.arm, "wiper") then
		local arm = hinge(byName, wiperSettings.arm, centre)
		need(arm.travel, `{wiperSettings.arm} has no range`)
		local inner, outer = points[wiperSettings.blade[1]], points[wiperSettings.blade[2]]
		if inner and outer then
			local nozzles = {}
			for index, nozzle in wiperSettings.nozzles do
				nozzles[index] = ManifestBinding.toRig(nozzle, centre)
			end
			wiper = {
				hinge = arm,
				blade = {
					inner = ManifestBinding.toRig(inner, centre),
					outer = ManifestBinding.toRig(outer, centre),
				},
				nozzles = nozzles,
			}
		else
			table.insert(pending, "wiper: the manifest has no point for an end of the blade")
		end
	end

	local shifter = nil
	local lever = settings.shifter
	if lever and has(lever, "gear lever") then
		local part = byName[lever]
		local gates: { [string]: { side: number, fore: number } } = {}
		for gear, angles in need(part.gates_rad, `{lever} has no gates`) do
			gates[gear] = { side = round(angles[1]), fore = round(angles[2]) }
		end
		local push = part.push_m
		if push == nil then
			table.insert(pending, `gear lever: the manifest has no push_m on {lever} (reverse's push-down)`)
		end
		shifter = {
			part = lever,
			pivot = ManifestBinding.toRig(need(part.pivot, `{lever} has no pivot`), centre),
			axisFore = direction(need(part.axis_fore, `{lever} has no fore axis`)),
			axisSide = direction(need(part.axis_side, `{lever} has no side axis`)),
			gates = gates,
			knob = ManifestBinding.toRig(need(part.knob, `{lever} has no knob`).centre, centre),
			push = round(push or 0),
		}
	end
	table.sort(pending)

	local model: Binding.CarModel = {
		wheels = wheels,
		calipers = settings.calipers,
		steeringWheel = settings.steeringWheel,
		steeringWheelLift = settings.steeringWheelLift,
		seat = seat,
		hullClearance = settings.hullClearance,
		bodyRaise = settings.bodyRaise,
		cluster = cluster,
		glazing = settings.glazing,
		windshield = windshield or {},
		door = doorBinding,
		controls = controls,
		pedals = pedals,
		parents = parents,
		steeringHub = steeringHub,
		modeKnob = modeKnob,
		exhaustOutlets = if #outlets > 0 then outlets else nil,
		shiftLights = shiftLights,
		panelLamps = panelLamps,
		wiper = wiper,
		shifter = shifter,
		needles = if next(needles) then needles else nil,
		displays = if next(displays) then displays else nil,
	}
	return model, pending
end

-- Fields in the order a reader expects them; any other key follows, sorted.
local ORDER = {
	"part",
	"forward",
	"right",
	"up",
	"width",
	"height",
	"tilt",
	"centre",
	"pivot",
	"axis",
	"axisFore",
	"axisSide",
	"gates",
	"side",
	"fore",
	"knob",
	"push",
	"rest",
	"travel",
	"diameter",
	"hinge",
	"blade",
	"inner",
	"outer",
	"nozzles",
	"positions",
	"parts",
	"openAngle",
	"wheels",
	"calipers",
	"steeringWheel",
	"steeringWheelLift",
	"seat",
	"hullClearance",
	"bodyRaise",
	"cluster",
	"glazing",
	"windshield",
	"door",
	"controls",
	"pedals",
	"parents",
	"steeringHub",
	"modeKnob",
	"exhaustOutlets",
	"shiftLights",
	"panelLamps",
	"wiper",
	"shifter",
	"needles",
	"displays",
}
local RANK: { [string]: number } = {}
for index, key in ORDER do
	RANK[key] = index
end

local function keyText(key: string): string
	return if string.match(key, "^[%a_][%w_]*$") then key else `["{key}"]`
end

local function valueText(value: unknown, indent: string): string
	if type(value) == "number" then
		local text = string.format("%.5f", value)
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "%.$", "")
		return if text == "-0" then "0" else text
	elseif type(value) == "string" then
		return string.format("%q", value)
	elseif type(value) == "boolean" then
		return tostring(value)
	end
	assert(type(value) == "table", `cannot write a {type(value)}`)
	local list = value :: { unknown }
	local inner = indent .. "\t"
	local lines: { string } = {}
	if #list > 0 then
		for _, item in list do
			table.insert(lines, `{inner}{valueText(item, inner)},`)
		end
	else
		local map = value :: { [string]: unknown }
		local keys: { string } = {}
		for key in map do
			table.insert(keys, key)
		end
		table.sort(keys, function(a: string, b: string): boolean
			local ra, rb = RANK[a] or math.huge, RANK[b] or math.huge
			if ra ~= rb then
				return ra < rb
			end
			return a < b
		end)
		for _, key in keys do
			table.insert(lines, `{inner}{keyText(key)} = {valueText(map[key], inner)},`)
		end
	end
	if #lines == 0 then
		return "{}"
	end
	-- A short table on one line, as the repo's configs write a point or a list of names.
	local items: { string } = {}
	for _, line in lines do
		local item = string.gsub(string.gsub(line, "^%s+", ""), ",$", "")
		table.insert(items, item)
	end
	local inline = "{ " .. table.concat(items, ", ") .. " }"
	if not string.find(inline, "\n", 1, true) and #indent + #inline <= 80 then
		return inline
	end
	return "{\n" .. table.concat(lines, "\n") .. `\n{indent}}`
end

-- The binding and its pending list as Luau modules, for tools/<car>_binding to write.
function ManifestBinding.render(model: Binding.CarModel, pending: { string }, tool: string): (string, string)
	local header =
		`--!strict\n--[[\n\tWritten by {tool} from the car's 3D manifest: do not edit by hand, run the tool again.\n]]\n`
	local modelText = header
		.. 'local Binding = require("../Binding")\n\n'
		.. `local Model: Binding.CarModel = {valueText(model, "")}\n\nreturn Model\n`
	local pendingText = header
		.. "-- What the binding still lacks or estimates; a car joins the catalog once this is empty.\n"
		.. `return {valueText(pending, "")}\n`
	return modelText, pendingText
end

return table.freeze(ManifestBinding)
