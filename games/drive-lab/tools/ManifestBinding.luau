--!strict
--[[
	Turns a car's merged 3D manifest (drive-lab-assets/<car>/work/manifest) into its model binding
	(Config/Cars/Binding): checks that every part's group leads to the body, moves every point from
	the manifest's frame (the rear-axle midpoint on the ground) to the rig's (the centre of mass),
	and lists what the binding still lacks instead of inventing it. Pure: tools/dr458_binding reads
	and writes the files.
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
	door: { group: string, hinge: string },
	controls: { string },
	pedals: { string },
	modeKnob: { part: string, modes: { string } },
	glazing: { string },
	screen: string,
	exhaust: { string },
	shiftLights: { string },
	panelLamps: { [string]: string },
	steeringWheelLift: number,
	bodyRaise: number,
	hullClearance: number,
	-- The driver's hip point, by its name among the manifest's points.
	hipPoint: string,
	-- Each start-up control's rest and other end, as angles from its modelled pose.
	controlStates: { [string]: { rest: number, other: number } },
}

local ManifestBinding = {}

ManifestBinding.BODY = "Chassis"

local MAX_DEPTH = 8

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

-- `point` turned by `angle` about the line through `pivot` along `axis`, all in the manifest's
-- frame; the turn follows the right-hand rule in Roblox's frame (Rules/Hinge), where the manifest
-- says a positive turn keeps its sense.
function ManifestBinding.turned(point: Point, pivot: Point, axis: Point, angle: number): Point
	local moved = Hinge.rotate(Hinge.chassis(point), Hinge.chassis(pivot), Hinge.chassis(axis), angle)
	return { forward = -moved.z, right = moved.x, up = moved.y }
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

	-- The tyre stands for its corner (the rig's ground and scale); the rest of the corner rides it.
	local wheels: { string } = {}
	local parents: { [string]: string } = {}
	local corner: { [string]: string } = {}
	for _, group in settings.wheelGroups do
		local tyre = group .. settings.tyreSuffix
		need(byName[tyre], `the manifest has no {tyre}`)
		table.insert(wheels, tyre)
		corner[group] = tyre
	end
	local door = settings.door
	local doorParts: { string } = {}
	for _, part in manifest.parts do
		if corner[part.group] and part.name ~= corner[part.group] then
			parents[part.name] = corner[part.group]
		elseif part.group == door.group then
			table.insert(doorParts, part.name)
		else
			local mover = ManifestBinding.mover(byName, settings, part)
			if mover and not corner[mover] then
				parents[part.name] = mover
			end
		end
	end
	table.sort(doorParts)

	local wheel = need(byName[settings.steeringWheel], `the manifest has no {settings.steeringWheel}`)
	local wheelPivot = need(wheel.pivot, "the steering wheel has no pivot")
	local wheelAxis = need(wheel.axis, "the steering wheel has no axis")
	local steeringHub = if wheel.mesh == false
		then { pivot = ManifestBinding.toRig(wheelPivot, centre), axis = direction(wheelAxis) }
		else nil

	local doorHinge = hinge(byName, door.hinge, centre)
	local openAngle = need(doorHinge.travel, `{door.hinge} has no range`)

	local controls: { [string]: Binding.Hinge } = {}
	for _, name in settings.controls do
		local state = need(settings.controlStates[name], `{name} has no rest and other end`)
		controls[name] = hinge(byName, name, centre, state)
	end
	local pedals: { Binding.Hinge } = {}
	for _, name in settings.pedals do
		table.insert(pedals, hinge(byName, name, centre))
		if byName[name].positive == nil then
			table.insert(pending, `{name}: no "positive" note; which way presses it is unchecked`)
		end
	end

	local knob = settings.modeKnob
	local knobPart = need(byName[knob.part], `the manifest has no {knob.part}`)
	local detents = knobPart.range
	assert(type(detents) == "table" and #detents == #knob.modes, `{knob.part} has a position per mode`)
	local positions: { [string]: number } = {}
	for index, mode in knob.modes do
		positions[mode] = round(detents[index] - detents[1])
	end

	local screenPart = need(byName[settings.screen], `the manifest has no {settings.screen}`)
	local screen: Screen = need(screenPart.screen, `{settings.screen} has no screen`)

	local outlets = {}
	for _, name in settings.exhaust do
		local outlet = need(need(byName[name], `the manifest has no {name}`).outlet, `{name} has no outlet`)
		table.insert(outlets, {
			centre = ManifestBinding.toRig(outlet.centre, centre),
			axis = direction(outlet.axis),
			diameter = round(outlet.diameter_m),
		})
	end

	for _, name in settings.glazing do
		need(byName[name], `the manifest has no {name}`)
	end
	for _, name in settings.shiftLights do
		need(byName[name], `the manifest has no {name}`)
	end
	for _, name in settings.panelLamps do
		need(byName[name], `the manifest has no {name}`)
	end

	local points = manifest.points or {}
	local seat = ManifestBinding.toRig(
		need(points[settings.hipPoint], `the manifest has no point {settings.hipPoint}`),
		centre
	)
	table.insert(pending, "windshield: no windscreen corners in the manifest")
	table.insert(pending, "lamps: no exterior lamps in the manifest")
	table.sort(pending)

	local model: Binding.CarModel = {
		wheels = wheels,
		calipers = settings.calipers,
		steeringWheel = settings.steeringWheel,
		steeringWheelLift = settings.steeringWheelLift,
		seat = seat,
		hullClearance = settings.hullClearance,
		bodyRaise = settings.bodyRaise,
		cluster = {
			forward = round(screen.centre.forward - centre.forward),
			right = round(screen.centre.right - centre.right),
			up = round(screen.centre.up - centre.up),
			width = round(screen.width_m),
			height = round(screen.height_m),
			tilt = round(math.rad(screen.tilt_back_deg)),
		},
		glazing = settings.glazing,
		windshield = {},
		door = {
			parts = doorParts,
			pivot = doorHinge.pivot,
			axis = doorHinge.axis,
			openAngle = openAngle,
		},
		controls = controls,
		pedals = pedals,
		parents = parents,
		steeringHub = steeringHub,
		modeKnob = { hinge = hinge(byName, knob.part, centre), positions = positions },
		exhaustOutlets = outlets,
		shiftLights = settings.shiftLights,
		panelLamps = settings.panelLamps,
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
	"rest",
	"travel",
	"diameter",
	"hinge",
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
