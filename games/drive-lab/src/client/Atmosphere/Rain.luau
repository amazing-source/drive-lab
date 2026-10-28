--!strict
--[[
	The rain round the camera: rings of falling streaks (Rules/RainRings), and splash boxes on the
	road ahead that throw crowns and, on a wet road, ripples, with shelter rays so a roof keeps
	the rain off what is under it. Everything is built once at the largest tier; a frame only
	moves parts and sets rates, and the rays are cast every shelterInterval.

	Streaks stay where they were emitted in the world and fall straight down with the wind's
	light lean, in every view: a moving camera runs into them and they never slant with its
	speed. Past the rings, distance is the Atmosphere's haze (Weather, Rules/RainHaze), not more
	streaks. They are lit by the scene (per particle, local lights included, measured in
	Studio), so at night they show in the headlight beams and under the lamps; the weather's
	look sets their albedo (setLook).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config.Atmosphere)
local RainDensity = require(script.Parent.RainDensity)
local RainEmitters = require(script.Parent.RainEmitters)
local RainRings = require(ReplicatedStorage.Shared.Rules.RainRings)
local Units = require(ReplicatedStorage.Shared.Units)

export type View = "OnFoot" | "Chase" | "Hood" | "Cockpit"
-- A car's bounding box as Model:GetBoundingBox gives it: the box's frame (forward is -Z) and size.
export type CarBox = { frame: CFrame, size: Vector3 }
export type Frame = {
	camera: Vector3,
	-- The camera's velocity, studs/s.
	velocity: Vector3,
	view: View,
	car: CarBox?,
	intensity: number,
	-- The road's wetness, 0 to 1: ripples need a wet road.
	wetness: number,
	-- Bodies rain falls on but that shelter nothing: the local character and the cars. Shelter
	-- and ground rays pass through them.
	bodies: { Instance },
}

-- One sprite's emitter in a block, and the share of the block's rate it takes.
type Stream = { emitter: ParticleEmitter, share: number, rate: number }
-- `size` is the part's last written size: a write costs, so only real changes are written.
type Block = { part: Part, streams: { Stream }, exposure: number, size: Vector3, rate: number }
type Ring = { spec: Config.Ring, blocks: { Block }, halfLength: number, lifetime: number }
-- A splash box, the ground its last ray met (no height: nothing to splash on), and whether
-- that ground takes ripples.
type Box = {
	part: Part,
	splashes: Stream,
	ripples: Stream,
	exposure: number,
	size: Vector3,
	height: number?,
	normal: Vector3,
	level: boolean,
}
-- The frame the rain is laid out in: yaw axes, the point the hole is round and the hole's
-- base in those axes, the camera's velocity relative to the drifting streaks in them, and its
-- forward speed.
type Motion = {
	axes: CFrame,
	centre: Vector3,
	base: RainRings.Rect,
	margin: number,
	vx: number,
	vz: number,
	forward: number,
	driving: boolean,
	framed: boolean,
}
type Tone = { color: Config.Rgb, opacity: number, emission: number }

export type Rain = {
	folder: Folder,
	rings: { Ring },
	boxes: { Box },
	tier: Config.Tier,
	budget: Config.Budget,
	sinceShelter: number,
	layout: string,
	idle: boolean,
	ground: number?,
	-- Whether the sky is open over the camera (1) or not (0): the lens and the car read it.
	exposure: number,
	tone: Tone?,
	rays: RaycastParams,
	-- This frame's moves, made in one Workspace:BulkMoveTo.
	moved: { BasePart },
	frames: { CFrame },
}

local RAIN = Config.RAIN
local SPLASH = RAIN.splash
local RIPPLES = RAIN.ripples
local CUBIC_METRES_PER_CUBIC_STUD = Units.METRES_PER_STUD ^ 3
local WIND = Vector3.new(math.sin(RAIN.windHeading), 0, math.cos(RAIN.windHeading))
local DRIFT = WIND * RAIN.fallSpeed * math.tan(RAIN.lean)
-- Turns a part's bottom face from straight down to the rain's leaning fall.
local LEAN = CFrame.fromAxisAngle(Vector3.new(-WIND.Z, 0, WIND.X), RAIN.lean)
local BEHIND = 3
local LEVEL_MATERIALS: { [string]: boolean } = {}
for _, name in RIPPLES.materials do
	LEVEL_MATERIALS[name] = true
end

local function largestBoxes(): number
	local boxes = 0
	for _, budget in Config.BUDGETS do
		boxes = math.max(boxes, RainDensity.splashBoxes(budget))
	end
	return boxes
end

local function flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function yaw(frame: CFrame): CFrame
	local look = flat(frame.LookVector)
	if look.Magnitude < 1e-3 then
		return CFrame.identity
	end
	return CFrame.lookAt(Vector3.zero, look)
end

local function square(half: number): RainRings.Rect
	return { x0 = -half, x1 = half, z0 = -half, z1 = half }
end

local function motionOf(frame: Frame): Motion
	local car = frame.car
	local driving = car ~= nil and frame.view ~= "OnFoot"
	local axes = if car and driving then yaw(car.frame) else CFrame.identity
	local framed = driving and (frame.view == "Cockpit" or frame.view == "Hood")
	local relative = axes:VectorToObjectSpace(frame.velocity - DRIFT)
	local base, centre, margin = square(RAIN.cameraHole), frame.camera, 0
	if car and framed then
		base = { x0 = -car.size.X / 2, x1 = car.size.X / 2, z0 = -car.size.Z / 2, z1 = car.size.Z / 2 }
		centre, margin = car.frame.Position, RAIN.carMargin
	end
	return {
		axes = axes,
		centre = centre,
		base = base,
		margin = margin,
		vx = relative.X,
		vz = relative.Z,
		forward = frame.velocity:Dot(axes.LookVector),
		driving = driving,
		framed = framed,
	}
end

-- Each ring's blocks for this frame: round a hole that holds the one before it and reaches as
-- far along the motion as the camera travels in the ring's streak life. In the car views the
-- outer ring reaches further ahead, through the headlights.
local function layout(rain: Rain, motion: Motion): { { RainRings.Rect } }
	local placed = {}
	local previous: RainRings.Rect? = nil
	for index, ring in rain.rings do
		local hole = RainRings.hole(motion.base, motion.margin, motion.vx, motion.vz, ring.lifetime)
		if previous then
			hole = RainRings.union(hole, previous)
		end
		local ahead = if motion.driving and index == #rain.rings then RAIN.ahead else 0
		placed[index] = RainRings.blocks(hole, ring.spec.depth, ahead)
		previous = RainRings.outer(hole, ring.spec.depth, ahead)
	end
	return placed
end

local function worldPoint(motion: Motion, x: number, z: number, height: number): Vector3
	local point = motion.centre + motion.axes:VectorToWorldSpace(Vector3.new(x, 0, z))
	return Vector3.new(point.X, height, point.Z)
end

-- Where the splash boxes go: ahead of the car's front in the cockpit and hood views (the
-- bonnet hides the road nearer), ahead of the camera in the chase view, round it on foot;
-- always led by the camera's velocity, since splashes stay where they land.
local function splashCells(rain: Rain, frame: Frame, motion: Motion): { Vector3 }
	local budget, car = rain.budget, frame.car
	local forward = motion.axes.LookVector
	local depth = budget.splashRows * SPLASH.cell / 2
	local anchor = frame.camera
	if motion.framed and car then
		anchor = car.frame.Position + forward * (car.size.Z / 2 + SPLASH.ahead + depth)
	elseif motion.driving then
		anchor = frame.camera + forward * depth
	end
	anchor += flat(frame.velocity) * RAIN.leadSeconds
	local cells = {}
	for column = 1, budget.splashColumns do
		for row = 1, budget.splashRows do
			local x = (column - (budget.splashColumns + 1) / 2) * SPLASH.cell
			local z = (row - (budget.splashRows + 1) / 2) * SPLASH.cell
			table.insert(cells, anchor + motion.axes:VectorToWorldSpace(Vector3.new(x, 0, z)))
		end
	end
	return cells
end

local function openSky(rain: Rain, point: Vector3): boolean
	return Workspace:Raycast(point, Vector3.new(0, RAIN.shelterReach, 0), rain.rays) == nil
end

-- Share of a block's sample points (spread over its footprint) with open sky above them.
local function exposure(
	rain: Rain,
	motion: Motion,
	rect: RainRings.Rect,
	samples: number,
	height: number
): number
	local open = 0
	for sample = 1, samples do
		-- Samples along the block's longer side, evenly spaced.
		local share = (sample - 0.5) / samples
		local long = rect.x1 - rect.x0 >= rect.z1 - rect.z0
		local x = if long then rect.x0 + (rect.x1 - rect.x0) * share else (rect.x0 + rect.x1) / 2
		local z = if long then (rect.z0 + rect.z1) / 2 else rect.z0 + (rect.z1 - rect.z0) * share
		if openSky(rain, worldPoint(motion, x, z, height)) then
			open += 1
		end
	end
	return open / samples
end

-- The ground and sky under and over each splash box: a box on water, on steep ground or under
-- a roof splashes nothing; one on level road also ripples.
local function probeBoxes(rain: Rain, frame: Frame, cells: { Vector3 })
	local reach = Vector3.new(0, -RAIN.shelterReach, 0)
	for index, box in rain.boxes do
		local cell = cells[index]
		box.height, box.exposure, box.level = nil, 0, false
		local from = if cell then Vector3.new(cell.X, frame.camera.Y + SPLASH.probeHeight, cell.Z) else nil
		local hit = if from then Workspace:Raycast(from, reach, rain.rays) else nil
		if hit and hit.Material ~= Enum.Material.Water and hit.Normal.Y >= math.cos(SPLASH.maxSlope) then
			box.height, box.normal = hit.Position.Y, hit.Normal
			box.exposure = if openSky(rain, hit.Position + hit.Normal * 0.5) then 1 else 0
			box.level = hit.Normal.Y >= math.cos(RIPPLES.maxSlope)
				and LEVEL_MATERIALS[hit.Material.Name] == true
		end
	end
end

local function refreshShelter(
	rain: Rain,
	frame: Frame,
	motion: Motion,
	placed: { { RainRings.Rect } },
	cells: { Vector3 }
)
	debug.profilebegin("Rain.Occlusion")
	rain.rays.FilterDescendantsInstances = frame.bodies
	local below = Workspace:Raycast(frame.camera, Vector3.new(0, -RAIN.shelterReach, 0), rain.rays)
	rain.ground = if below then below.Position.Y else nil
	rain.exposure = if openSky(rain, frame.camera) then 1 else 0
	for index, ring in rain.rings do
		local samples = if ring.spec.sampled then rain.budget.shelterSamples else 1
		for block, entry in ring.blocks do
			entry.exposure = exposure(rain, motion, placed[index][block], samples, frame.camera.Y)
		end
	end
	probeBoxes(rain, frame, cells)
	debug.profileend()
end

local function setRate(stream: Stream, rate: number)
	if rate ~= stream.rate then
		stream.emitter.Rate = rate
		stream.rate = rate
	end
end

local function move(rain: Rain, part: BasePart, frame: CFrame, size: Vector3, last: Vector3): Vector3
	table.insert(rain.moved, part)
	table.insert(rain.frames, frame)
	if (size - last).Magnitude > 0.02 * size.Magnitude then
		part.Size = size
		return size
	end
	return last
end

-- Moves every ring's blocks to their inlets and works out the rate each asks for; returns the
-- streaks those rates would keep alive.
local function placeRings(
	rain: Rain,
	motion: Motion,
	placed: { { RainRings.Rect } },
	intensity: number
): number
	local ground = rain.ground or (motion.centre.Y - RAIN.groundFallback)
	local budget, requested = rain.budget, 0
	local turn = LEAN * motion.axes.Rotation
	local behind = if motion.driving
		then RAIN.behindShare * RainRings.behind(motion.forward, RAIN.behindSpeed)
		else 1
	for index, ring in rain.rings do
		local spec = ring.spec
		local column = RainRings.column(
			ground,
			spec.height,
			ring.halfLength,
			RAIN.fallSpeed * RAIN.inletSeconds,
			RAIN.fallSpeed
		)
		for number, block in ring.blocks do
			local rect = placed[index][number]
			local width, depth = rect.x1 - rect.x0, rect.z1 - rect.z0
			local at = worldPoint(
				motion,
				(rect.x0 + rect.x1) / 2,
				(rect.z0 + rect.z1) / 2,
				column.top - column.inlet / 2
			)
			local size = Vector3.new(width, column.inlet, depth):Max(Vector3.one * 0.1)
			block.size = move(rain, block.part, CFrame.new(at) * turn, size, block.size)
			local volume = width * depth * (column.top - column.bottom) * CUBIC_METRES_PER_CUBIC_STUD
			local rate = RainDensity.blockRate(
				spec.density * budget.share,
				volume,
				ring.lifetime,
				intensity,
				block.exposure,
				RAIN.rateExponent,
				budget.cap * #block.streams
			)
			block.rate = rate * (if number == BEHIND then behind else 1)
			requested += block.rate * ring.lifetime
		end
	end
	return requested
end

local function setRingRates(rain: Rain, scale: number)
	for _, ring in rain.rings do
		for _, block in ring.blocks do
			for _, stream in block.streams do
				setRate(stream, block.rate * stream.share * scale)
			end
		end
	end
end

local function placeBoxes(rain: Rain, motion: Motion, cells: { Vector3 }, frame: Frame)
	local size = Vector3.new(SPLASH.cell, 0.01, SPLASH.cell)
	for index, box in rain.boxes do
		local cell, height = cells[index], box.height
		local splashes, ripples = 0, 0
		if cell and height then
			local up = box.normal
			local back = motion.axes.RightVector:Cross(up).Unit
			local at = Vector3.new(cell.X, height, cell.Z) + up * SPLASH.lift
			box.size = move(rain, box.part, CFrame.fromMatrix(at, up:Cross(back), up, back), size, box.size)
			splashes = RainDensity.splashes(frame.intensity, box.exposure, rain.budget, RAIN.rateExponent)
			if box.level then
				ripples = RainDensity.ripples(
					frame.intensity,
					box.exposure,
					frame.wetness,
					RIPPLES.wetFrom,
					rain.budget,
					RAIN.rateExponent
				)
			end
		end
		setRate(box.splashes, splashes)
		setRate(box.ripples, ripples)
	end
end

local function buildRing(spec: Config.Ring, index: number, folder: Folder): Ring
	local halfLength = 0
	for _, entry in spec.layer.sprites do
		halfLength = math.max(halfLength, RainEmitters.halfLength(entry.sprite, spec.layer))
	end
	local inlet = RAIN.fallSpeed * RAIN.inletSeconds
	local lifetime = RainRings.column(0, spec.height, halfLength, inlet, RAIN.fallSpeed).lifetime
	local blocks: { Block } = {}
	for number = 1, 4 do
		local part = RainEmitters.invisiblePart(`Ring{index}Block{number}`, folder)
		local streams: { Stream } = {}
		for _, entry in spec.layer.sprites do
			local emitter = RainEmitters.streaks(entry.sprite, spec.layer, lifetime, part)
			table.insert(streams, { emitter = emitter, share = entry.share, rate = 0 })
		end
		table.insert(blocks, { part = part, streams = streams, exposure = 1, size = part.Size, rate = 0 })
	end
	return { spec = spec, blocks = blocks, halfLength = halfLength, lifetime = lifetime }
end

local function buildBox(index: number, folder: Folder): Box
	local part = RainEmitters.invisiblePart(`Splashes{index}`, folder)
	-- Boxes alternate between the ripple sprites, one emitter each.
	local sprite = RIPPLES.sprites[(index - 1) % #RIPPLES.sprites + 1]
	return {
		part = part,
		splashes = { emitter = RainEmitters.splashes(SPLASH, part), share = 1, rate = 0 },
		ripples = { emitter = RainEmitters.ripples(RIPPLES, sprite, part), share = 1, rate = 0 },
		exposure = 0,
		size = part.Size,
		height = nil,
		normal = Vector3.yAxis,
		level = false,
	}
end

local Rain = {}

function Rain.new(tier: Config.Tier): Rain
	local folder = Instance.new("Folder")
	folder.Name = "DriveLabRain"
	local rings: { Ring } = {}
	for index, spec in RAIN.rings do
		table.insert(rings, buildRing(spec, index, folder))
	end
	local boxes: { Box } = {}
	for index = 1, largestBoxes() do
		table.insert(boxes, buildBox(index, folder))
	end
	local rays = RaycastParams.new()
	rays.FilterType = Enum.RaycastFilterType.Exclude
	local rain: Rain = {
		folder = folder,
		rings = rings,
		boxes = boxes,
		tier = tier,
		budget = Config.BUDGETS[tier],
		sinceShelter = math.huge,
		layout = "",
		idle = false,
		ground = nil,
		exposure = 1,
		tone = nil,
		rays = rays,
		moved = {},
		frames = {},
	}
	folder.Parent = Workspace
	Rain.setTier(rain, tier)
	return rain
end

function Rain.setTier(rain: Rain, tier: Config.Tier)
	rain.tier, rain.budget = tier, Config.BUDGETS[tier]
	rain.idle = false
	rain.sinceShelter = math.huge
end

-- The weather's tone on every streak: their albedo, the share of their opacity shown and how
-- additive they blend. Written only when it moved, as a preset blend creeps.
function Rain.setLook(rain: Rain, look: Config.Look)
	local last, color = rain.tone, look.rainColor
	if
		last
		and math.abs(last.color.r - color.r) + math.abs(last.color.g - color.g) + math.abs(
			last.color.b - color.b
		) < 1
		and math.abs(last.opacity - look.rainOpacity) < 0.005
		and math.abs(last.emission - look.rainEmission) < 0.005
	then
		return
	end
	rain.tone = { color = color, opacity = look.rainOpacity, emission = look.rainEmission }
	local tint = RainEmitters.colour(color)
	for _, ring in rain.rings do
		for _, block in ring.blocks do
			for _, stream in block.streams do
				RainEmitters.tone(stream.emitter, ring.spec.layer, tint, look.rainOpacity, look.rainEmission)
			end
		end
	end
end

function Rain.update(rain: Rain, dt: number, frame: Frame)
	local raining = frame.intensity > 0
	if not raining and rain.idle then
		return
	end
	local motion = motionOf(frame)
	local placed = layout(rain, motion)
	local cells = splashCells(rain, frame, motion)
	local name = if motion.framed then "framed" else "camera"
	rain.sinceShelter += dt
	-- A new layout puts different ground under each block: sample it now, not in 0.3 s.
	if raining and (rain.sinceShelter >= RAIN.shelterInterval or name ~= rain.layout) then
		rain.sinceShelter = 0
		refreshShelter(rain, frame, motion, placed, cells)
	end
	rain.layout = name
	local requested = placeRings(rain, motion, placed, frame.intensity)
	setRingRates(rain, RainDensity.within(requested, rain.budget.live))
	placeBoxes(rain, motion, cells, frame)
	Workspace:BulkMoveTo(rain.moved, rain.frames, Enum.BulkMoveMode.FireCFrameChanged)
	table.clear(rain.moved)
	table.clear(rain.frames)
	rain.idle = not raining
end

function Rain.destroy(rain: Rain)
	rain.folder:Destroy()
end

return Rain
