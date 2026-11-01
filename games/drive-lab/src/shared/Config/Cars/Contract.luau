--!strict
--[[
	Everything that differs from one car to the next, as one entry per car in Catalog. Shared
	systems read a car's part of it from the entry of the model they serve, never from a car's
	own modules. `define` checks that an entry's parts agree with each other, so a bad car fails
	at load time, and freezes it, so nothing can tune a car at run time.
]]
local Binding = require("./Binding")
local Binnacle = require("../Binnacle")
local CarAudio = require("../CarAudio")
local CarCamera = require("../CarCamera")
local CarEntry = require("../CarEntry")
local CarLights = require("../CarLights")
local CarSwitches = require("../CarSwitches")
local Cluster = require("../Cluster")
local DriverArms = require("../DriverArms")
local DriverLegs = require("../DriverLegs")
local DriverAssists = require("../../Rules/DriverAssists")
local DriverGestures = require("../DriverGestures")
local DriverShift = require("../DriverShift")
local DriverStartup = require("../DriverStartup")
local Driving = require("../Driving")
local ExhaustFlames = require("../../Rules/ExhaustFlames")
local GaugeRules = require("../../Rules/Gauges")
local Gauges = require("../Gauges")
local GearboxModes = require("../../Rules/GearboxModes")
local HudDesign = require("../HudDesign")
local RimBlur = require("../RimBlur")
local ShiftHand = require("../../Rules/ShiftHand")
local StartupArms = require("../../Rules/StartupArms")
local Types = require("./Types")

export type Driver = {
	grip: DriverArms.Grip,
	footwell: DriverLegs.Footwell,
	-- Both hands through the start-up, keyed against this car's cabin.
	startupPaths: DriverStartup.Paths,
	-- The character's scale from the door mark to the seat and back, when this car's seat needs
	-- another than Driving.DRIVER_SCALE; its clips and seated pose are authored for it.
	scale: number?,
	-- The drawn arms' lengths (studs at character scale 1), when this car's wheel needs other
	-- than Config/DriverArms'.
	arms: { upper: number, lower: number }?,
	-- Where the drawn hands start when the body hands its arms over (each wrist in the DriverSeat
	-- frame, as the start-up's keys), and the seconds they take to ease to their resting pose:
	-- for a car whose body arms cannot end on the drawn ones' rest without entering the car.
	handOver: { seconds: number, right: StartupArms.Pose, left: StartupArms.Pose }?,
	-- What the hands do on the wheel's buttons and the panel's switches; none on a car without.
	gestures: DriverGestures.Gestures?,
	-- The right hand's way to an H-pattern lever's knob and its grip there (Rules/ShiftHand); none
	-- on a car without a lever.
	shift: DriverShift.Shift?,
}

export type Entry = {
	physics: Types.CarConfig,
	-- What the HUD calls each of the car's drive modes.
	modeLabels: { [string]: string },
	model: Binding.CarModel,
	door: CarEntry.Door,
	startup: CarEntry.Startup,
	driver: Driver,
	camera: CarCamera.CarViews,
	rimBlur: RimBlur.Rims,
	audio: CarAudio.Pack,
	-- Which of its pops throw flame; without it, every pop does.
	flames: ExhaustFlames.CarFlames?,
	lights: CarLights.Lights,
	-- The car's display: a dial face, a binnacle screen with pages and shift lights, or an analog
	-- cluster of needles. One of them.
	cluster: Cluster.Face?,
	binnacle: Binnacle.Screen?,
	gauges: Gauges.Cluster?,
	-- The car's own driving HUD; without it, Config/Hud's.
	hud: HudDesign.Design?,
	assists: DriverAssists.Tuning,
	switches: CarSwitches.Switches,
}

-- What a car has of the controls not every car has (Config/CarSwitches.NEEDS), by name.
export type Features = { [string]: boolean }

-- One of a pack's loops, for the region check.
type Loop = { soundId: string, region: CarAudio.Region?, what: string }

-- Seconds two readings of one start-up's timing may differ by: about a frame.
local TIMING_TOLERANCE = 0.02

local Contract = {}

local function deepFreeze<T>(value: T): T
	if type(value) == "table" and not table.isfrozen(value) then
		for _, child in value :: { [unknown]: unknown } do
			deepFreeze(child)
		end
		table.freeze(value)
	end
	return value
end

local function checkStartup(entry: Entry)
	local startup = entry.startup
	local controls = entry.model.controls or {}
	for _, move in startup.moves do
		local name = move.control
		assert(controls[name], `the start-up moves "{name}", which the model binding does not hinge`)
		assert(move.move > 0, `"{name}" needs a move time above 0`)
		assert(move.back == nil or move.back >= move.at, `"{name}" turns back before it has arrived`)
	end
	assert(startup.pressAt < startup.drivableAt, "driving unlocks before START is pressed")
	assert(startup.wheelAt <= startup.drivableAt, "driving unlocks before the hands are on the wheel")
	local clutch = startup.clutch
	assert(clutch == nil or (clutch > 0 and clutch <= 1), "the start-up's clutch is a share above 0, up to 1")
	assert(
		startup.interlock ~= "Clutch" or clutch ~= nil,
		"a clutch interlock needs the start-up to press the clutch"
	)
	local keys = startup.keys
	if keys then
		for mode, key in keys do
			assert(
				table.find(entry.physics.modeOrder, mode),
				`the start-up's key for "{mode}" names no drive mode`
			)
			assert(key ~= "" and key ~= CarEntry.STANDARD_KEY, `the key for "{mode}" is not a key of its own`)
		end
	end
end

-- The legs press the pedals the rig turns: each footwell pedal is one the binding hinges.
local function checkFootwell(entry: Entry)
	local hinged: { [string]: boolean } = {}
	local pedals = entry.model.pedals
	if pedals then
		for _, pedal in pedals do
			hinged[pedal.part] = true
		end
	end
	local footwell = entry.driver.footwell
	for _, pedal in Contract.footwellPedals(footwell) do
		assert(hinged[pedal.part], `the footwell's "{pedal.part}" is not a pedal the model binding hinges`)
	end
	for _, problem in Contract.footwellMismatches(entry.model, footwell) do
		error(problem)
	end
end

-- A shift hand needs a lever to hold: one the model binds, on a manual gearbox whose every gate
-- the binding turns the lever to (ShiftHand.leverFromBinding errors otherwise).
function Contract.checkShift(entry: Entry)
	if entry.driver.shift == nil then
		return
	end
	local shifter = entry.model.shifter
	assert(shifter, "the driver's shift hand needs a gear lever in the model binding")
	local gearbox = entry.physics.gearbox
	local manual = gearbox.manual
	assert(gearbox.kind == "manual" and manual, "the driver's shift hand needs a manual gearbox")
	ShiftHand.leverFromBinding(shifter, manual.gates, entry.model.seat)
end

-- The driver's scale and arm lengths need to be usable sizes.
local function checkDriverSize(entry: Entry)
	local driver = entry.driver
	assert(driver.scale == nil or driver.scale > 0, "the driver's scale must be positive")
	local arms = driver.arms
	assert(arms == nil or (arms.upper > 0 and arms.lower > 0), "the driver's arms need positive lengths")
	local handOver = driver.handOver
	assert(handOver == nil or handOver.seconds > 0, "the driver's hand-over needs a positive duration")
end

local DRAWN_SHAPES = table.freeze({ Grip = true, Rest = true, Point = true, Pinch = true })

local function checkTrack(
	entry: Entry,
	gesture: DriverGestures.Gesture,
	name: string,
	track: DriverGestures.Track
)
	local what = `the {gesture.control} gesture's "{name}" track`
	local keys = track.keys
	assert(#keys >= 2 and keys[1][1] == 0, `{what} needs keys from 0`)
	for index = 2, #keys do
		assert(keys[index][1] > keys[index - 1][1], `{what} has keys out of order`)
	end
	assert(#track.shapes > 0 and track.shapes[1].at == 0, `{what} needs a shape from 0`)
	local meshes = (entry.driver.gestures :: DriverGestures.Gestures).MESHES
	for _, change in track.shapes do
		assert(
			DRAWN_SHAPES[change.shape] or meshes[change.shape],
			`{what} draws "{change.shape}", which has no mesh`
		)
	end
	assert(gesture.frame == "Wheel" or track.gripBlend, `{what} leaves the wheel's frame with no grip blend`)
	local turn = track.turn
	if turn then
		assert(gesture.latch, `{what} turns a control but tracks no state`)
		assert(turn.start < turn.finish and turn.finish <= keys[#keys][1], `{what} turns outside its keys`)
		local knob = entry.model.modeKnob
		local controls = entry.model.controls or {}
		local bound = if gesture.latch == "Mode"
			then knob and knob.hinge.part == turn.control
			else controls[turn.control] and controls[turn.control].travel ~= nil
		assert(bound, `{what} turns "{turn.control}", which the binding does not hinge for it`)
	end
end

-- Each gesture plays on a control the car has, with a track for every state it can be pressed in.
local function checkGestures(entry: Entry)
	local gestures = entry.driver.gestures
	if gestures == nil then
		return
	end
	local features = Contract.features(entry)
	local seen: { [string]: boolean } = {}
	for _, gesture in gestures.list do
		local control = gesture.control
		assert(not seen[control], `two gestures play on {control}`)
		seen[control] = true
		local need = CarSwitches.NEEDS[control]
		assert(need == nil or features[need], `a gesture plays on {control}, which the car does not have`)
		assert(gesture.side == 1 or gesture.side == -1, `the {control} gesture needs a side`)
		local states: { string } = if gesture.latch == "Mode"
			then entry.physics.modeOrder
			elseif gesture.latch == "Toggle" then { "Off", "On" }
			else { "Press" }
		for _, state in states do
			local track = gesture.tracks[state]
			assert(track, `the {control} gesture has no track for "{state}"`)
			checkTrack(entry, gesture, state, track)
		end
	end
	assert(gestures.HOLD_MIN >= 0, "a gesture's hold cannot be negative")
end

-- Every key of a table keyed by drive mode is one of the car's modes.
local function checkNames<V>(entry: Entry, values: { [string]: V }, what: string)
	for name in values do
		assert(entry.physics.modes[name], `{what} names "{name}", which the car has no mode for`)
	end
end

-- A table keyed by drive mode has a value for each of the car's modes, and for no other.
local function checkCovers<V>(entry: Entry, values: { [string]: V }, what: string)
	for _, name in entry.physics.modeOrder do
		assert(values[name] ~= nil, `{what} has nothing for the {name} mode`)
	end
	checkNames(entry, values, what)
end

-- Every part keyed by drive mode knows each of the car's modes.
local function checkModes(entry: Entry)
	checkCovers(entry, entry.modeLabels, "the mode labels")
	checkCovers(entry, entry.camera.shiftKick, "the camera's shift kick")
	local pops = entry.audio.popTriggers
	checkCovers(entry, pops.liftChance, "the lift pops")
	checkCovers(entry, pops.upshiftChance, "the upshift pops")
	checkCovers(entry, pops.downshiftChance, "the downshift pops")
	local modes = entry.assists.modes
	if modes then
		checkNames(entry, modes, "the assists")
	end
	local flames = entry.flames
	if flames then
		checkCovers(entry, flames.chance, "the flames")
	end
end

local function share(value: number): boolean
	return value >= 0 and value <= 1
end

-- The flames' chances and shares are shares, 0 to 1.
local function checkFlames(entry: Entry)
	local flames = entry.flames
	if flames == nil then
		return
	end
	for mode, chances in flames.chance do
		assert(
			share(chances.Lift) and share(chances.Downshift) and share(chances.Upshift),
			`the flames' chances in the {mode} mode are not shares`
		)
	end
	assert(share(flames.minStrength), "the flames' quietest pop is not a share")
	assert(share(flames.fireballFrom), "the flames' fireball threshold is not a share")
	assert(share(flames.dayShare), "the flames' daylight brightness is not a share")
end

-- A dial face draws every drive mode the car has in that mode's colours, and its red zone on its
-- dial.
local function checkCluster(entry: Entry, face: Cluster.Face)
	checkCovers(entry, face.modes, "the cluster's colours")
	assert(
		face.redlineRpm > 0 and face.redlineRpm < face.dialMaxRpm,
		"the cluster's redline lies off its dial"
	)
end

-- A binnacle screen has a page for each the SCROLL button steps through, a strip of a lamp, its
-- rev lights in rising order and a lamp, its redline on its rpm bar, and the shape of the screen
-- it is drawn on; each field has its slot (and its pill) on its page's design, and each lamp its
-- lens and images.
local function checkBinnacle(entry: Entry, screen: Binnacle.Screen)
	assert(
		#screen.pages == (entry.switches.displayPages or 1),
		"the binnacle's pages are not the ones its page switch steps through"
	)
	local lights = screen.revLights
	assert(#lights.colours >= 1, "the binnacle's strip has no rev lights")
	assert(lights.fromRpm < lights.toRpm, "the binnacle's rev lights do not rise")
	assert(
		screen.redlineRpm > screen.barFromRpm and screen.redlineRpm <= screen.barToRpm,
		"the binnacle's redline lies off its rpm bar"
	)
	local glass = entry.model.cluster
	local shape = (screen.canvasWidth / screen.canvasHeight) / (glass.width / glass.height)
	assert(math.abs(shape - 1) <= 0.05, "the binnacle's canvas is not the shape of its screen")
	for _, page in screen.pages do
		local art = page.art
		for _, field in page.fields do
			assert(art.slots[field.label], `the binnacle's {field.label} has no slot on its page`)
			assert(
				field.pill == nil or (art.pills and art.pills[field.label]),
				`the binnacle's {field.label} has no pill on its page`
			)
		end
	end
	local lamps = #lights.colours + 2
	assert(
		#screen.lenses == lamps and #screen.lamps.off == lamps and #screen.lamps.on == lamps,
		"the binnacle's strip needs a lens, an unlit and a lit image for each lamp"
	)
end

-- What is wrong with a dial's scale: under two points, readings that do not rise, shares outside
-- 0 to 1 or falling.
local function scaleProblem(dial: Gauges.Dial): string?
	local scale = dial.scale
	if #scale < 2 then
		return "has under two points on its scale"
	end
	for index, point in scale do
		if point[2] < 0 or point[2] > 1 then
			return "has a share off its needle's travel"
		end
		local before = scale[index - 1]
		if before and (point[1] <= before[1] or point[2] < before[2]) then
			return "has a scale whose readings do not rise or whose shares fall"
		end
	end
	return nil
end

local function dialProblems(model: Binding.CarModel, cluster: Gauges.Cluster, problems: { string })
	local needles = model.needles or {}
	local used: { [string]: boolean } = {}
	for _, dial in cluster.dials do
		local what = `the {dial.needle} dial`
		local needle = needles[dial.needle]
		if needle == nil or needle.travel == nil or needle.travel <= 0 then
			table.insert(problems, `{what} turns a needle the binding does not bind with a sweep`)
		end
		if used[dial.needle] then
			table.insert(problems, `two dials turn {dial.needle}`)
		end
		used[dial.needle] = true
		if not GaugeRules.unitFits(dial.reading, dial.unit) then
			table.insert(problems, `{what} prints its {dial.reading} in {dial.unit}`)
		end
		local scale = scaleProblem(dial)
		if scale then
			table.insert(problems, `{what} {scale}`)
		end
		if not (dial.response > 0 and dial.catchUp > 0 and dial.maxRate > 0) then
			table.insert(problems, `{what} needs a positive response, catch-up and top speed`)
		end
	end
end

--[[
	Everything wrong with an analog cluster against the car's binding and start-up: each dial turns
	a bound needle of its own, prints its reading in a unit it can be read in, on a usable scale,
	with usable needle timings; the cluster lights with a control its start-up moves; its screens
	are displays the binding has. Kept apart from `define` so a car still out of the catalog can be
	checked.
]]
function Contract.gaugeProblems(
	model: Binding.CarModel,
	startup: CarEntry.Startup,
	cluster: Gauges.Cluster
): { string }
	local problems: { string } = {}
	dialProblems(model, cluster, problems)
	if GaugeRules.lightAt(startup, cluster.lightsWith) == nil then
		table.insert(problems, `the gauges light with "{cluster.lightsWith}", which the start-up never moves`)
	end
	if cluster.redlineRpm <= 0 then
		table.insert(problems, "the gauges' redline is not a speed")
	end
	if cluster.sweep ~= nil and cluster.sweep <= 0 then
		table.insert(problems, "the gauges' sweep needs a duration")
	end
	local displays = model.displays or {}
	local screens: { string } = {}
	if cluster.readout then
		table.insert(screens, cluster.readout.display)
	end
	if cluster.message then
		table.insert(screens, cluster.message.display)
	end
	for _, display in screens do
		if displays[display] == nil then
			table.insert(problems, `the gauges draw on the {display} display, which the binding lacks`)
		end
	end
	return problems
end

local function checkDisplay(entry: Entry)
	local face, screen, gauges = entry.cluster, entry.binnacle, entry.gauges
	local count = (if face then 1 else 0) + (if screen then 1 else 0) + (if gauges then 1 else 0)
	assert(count == 1, "a car has one display: a dial face, a binnacle screen or analog gauges")
	if face then
		checkCluster(entry, face)
	elseif screen then
		checkBinnacle(entry, screen)
	elseif gauges then
		for _, problem in Contract.gaugeProblems(entry.model, entry.startup, gauges) do
			error(problem)
		end
	end
end

-- The switches' numbers are usable: a limiter with a band that arms in a forward gear, a wiper
-- with a wipe time per speed, slowest first, more than one display page.
local function checkSwitches(entry: Entry)
	local switches = entry.switches
	local pit = switches.pitLimiter
	if pit then
		assert(pit.limitKmh > 0 and pit.band > 0, "the pit limiter needs a limit and a band")
		assert(
			pit.armBelowKmh == nil or pit.armBelowKmh <= pit.limitKmh,
			"the pit limiter arms above its own limit"
		)
		assert(pit.armFromGear >= 1 and pit.armFromGear % 1 == 0, "the pit limiter arms from a forward gear")
		assert(pit.armToGear == nil or pit.armToGear >= pit.armFromGear, "the pit limiter has no arming gear")
	end
	local wiper = switches.wiper
	if wiper then
		assert(#wiper.speeds >= 1, "the wiper needs a speed")
		for index, seconds in wiper.speeds do
			assert(seconds > 0, "the wiper needs a wipe time at each speed")
			assert(index == 1 or seconds < wiper.speeds[index - 1], "the wiper's speeds go slowest first")
		end
		assert(
			wiper.afterWash >= 0 and wiper.afterWash % 1 == 0,
			"the wiper's wipes after a wash are a count"
		)
	end
	local pages = switches.displayPages
	assert(pages == nil or (pages >= 2 and pages % 1 == 0), "a display with pages has two or more")
end

-- Seconds after the press at which a start-up's revs leave the starter's.
local function crankingEnds(curve: CarEntry.Curve): number
	local index = 1
	while curve.values[index + 1] == curve.values[1] do
		index += 1
	end
	return curve.times[index]
end

-- A start-up played from its own sound keeps to the start-up's timing: it is an uploaded asset
-- with a level, its times run in order, the engine catches in it when the start-up says, and the
-- instruments hold the starter's revs from the starter's end to the catch.
function Contract.checkStartupSound(startup: CarEntry.Startup, pack: CarAudio.Pack)
	local sound = pack.startup.sound
	if sound == nil then
		return
	end
	assert(string.match(sound.id, "^rbxassetid://%d+$") ~= nil, "the start-up sound is not an uploaded asset")
	assert(sound.volume > 0, "the start-up sound has no level")
	assert(
		0 <= sound.from
			and sound.from < sound.starterEnds
			and sound.starterEnds <= sound.catchAt
			and sound.catchAt < sound.handOver
			and sound.handOver < sound.to,
		"the start-up sound's times are out of order"
	)
	assert(
		math.abs(startup.catchAfter - (sound.catchAt - sound.from)) <= TIMING_TOLERANCE,
		"the engine catches in the start-up sound at another time than the start-up says"
	)
	local cranking = crankingEnds(startup.rpm)
	assert(
		cranking >= sound.starterEnds - sound.from - TIMING_TOLERANCE
			and cranking <= startup.catchAfter + TIMING_TOLERANCE,
		"the instruments leave the starter's revs before the start-up sound's starter stops or after it catches"
	)
end

-- A pack's loops (its engine layers, limiter and far loop) may share one uploaded file, each
-- looping its own region of it: every region runs forward from 0 or later, and loops that share a
-- file each have a region, none overlapping another's.
function Contract.checkLoopRegions(pack: CarAudio.Pack)
	local loops: { Loop } = {}
	for _, layer in pack.engineLayers do
		table.insert(
			loops,
			{ soundId = layer.soundId, region = layer.region, what = `the {layer.name} loop` }
		)
	end
	table.insert(
		loops,
		{ soundId = pack.limiter.soundId, region = pack.limiter.region, what = "the limiter" }
	)
	table.insert(loops, { soundId = pack.far.soundId, region = pack.far.region, what = "the far loop" })
	local byFile: { [string]: { Loop } } = {}
	for _, loop in loops do
		local region = loop.region
		assert(
			region == nil or (region.from >= 0 and region.to > region.from),
			`{loop.what}'s region does not run forward from 0 or later`
		)
		local shared = byFile[loop.soundId] or {}
		table.insert(shared, loop)
		byFile[loop.soundId] = shared
	end
	for _, shared in byFile do
		if #shared < 2 then
			continue
		end
		for index, loop in shared do
			local region = loop.region
			assert(region, `{loop.what} shares its file with another loop but has no region`)
			for later = index + 1, #shared do
				local other = shared[later]
				local otherRegion = other.region
				assert(
					otherRegion == nil or region.to <= otherRegion.from or otherRegion.to <= region.from,
					`{loop.what} and {other.what} overlap in their file`
				)
			end
		end
	end
end

function Contract.define(entry: Entry): Entry
	checkStartup(entry)
	checkFootwell(entry)
	Contract.checkShift(entry)
	checkDriverSize(entry)
	checkModes(entry)
	checkDisplay(entry)
	if entry.hud then
		HudDesign.check(entry.hud)
	end
	checkSwitches(entry)
	checkGestures(entry)
	checkFlames(entry)
	Contract.checkStartupSound(entry.startup, entry.audio)
	Contract.checkLoopRegions(entry.audio)
	return deepFreeze(entry)
end

-- Where the car's red zone starts, on its display and the HUD's rev segments.
function Contract.redline(entry: Entry): number
	local face, screen, gauges = entry.cluster, entry.binnacle, entry.gauges
	if face then
		return face.redlineRpm
	elseif gauges then
		return gauges.redlineRpm
	end
	assert(screen, "a car has a display")
	return screen.redlineRpm
end

-- The character's scale while it uses this car.
function Contract.driverScale(entry: Entry): number
	return entry.driver.scale or Driving.DRIVER_SCALE
end

-- The drawn arms' upper and lower lengths, studs at character scale 1.
function Contract.armLengths(entry: Entry): (number, number)
	local arms = entry.driver.arms
	if arms then
		return arms.upper, arms.lower
	end
	return DriverArms.UPPER_LENGTH, DriverArms.LOWER_LENGTH
end

-- The pedals a footwell's feet work: the throttle and the brake, and the clutch in a car that has one.
function Contract.footwellPedals(footwell: DriverLegs.Footwell): { DriverLegs.Pedal }
	local pedals = { footwell.throttle, footwell.brake }
	if footwell.clutch then
		table.insert(pedals, footwell.clutch)
	end
	return pedals
end

-- Metres a footwell hinge may sit off the binding's pivot for the same pedal.
local HINGE_TOLERANCE = 0.01
-- Metres a throttle's or clutch's hinge sits above its ball when the pedal hangs from above.
local HUNG_HINGE_RISE = 0.1

-- Where the footwell disagrees with the binding: Rules/DriverLegs turns each pedal's sole points
-- about the seat's x (the car's right) by the footwell's travel, while the rig turns the pedal's
-- weld about the binding's axis by the binding's travel, so the hinge, the axis and the signed
-- travel have to be the same or the foot and the pedal move apart.
function Contract.footwellMismatches(model: Binding.CarModel, footwell: DriverLegs.Footwell): { string }
	local problems = {}
	-- Unmarked, a hung throttle's heel would swing round its hinge, and a hung clutch's would stay
	-- put while the ball rides its long travel.
	local mustHang = { footwell.throttle }
	if footwell.clutch then
		table.insert(mustHang, footwell.clutch)
	end
	for _, pedal in mustHang do
		if not pedal.hangs and pedal.hinge.y > pedal.ball.y + HUNG_HINGE_RISE then
			table.insert(problems, `the footwell's {pedal.part} hangs from above but is not marked hangs`)
		end
	end
	local seat = model.seat
	local byPart: { [string]: Binding.Hinge } = {}
	local pedals = model.pedals
	if pedals then
		for _, pedal in pedals do
			byPart[pedal.part] = pedal
		end
	end
	for _, pedal in Contract.footwellPedals(footwell) do
		local bound = byPart[pedal.part]
		if bound then
			local hinge = {
				x = bound.pivot.right - seat.right,
				y = bound.pivot.up - seat.up,
				z = -(bound.pivot.forward - seat.forward),
			}
			local off = math.sqrt(
				(hinge.x - pedal.hinge.x) ^ 2 + (hinge.y - pedal.hinge.y) ^ 2 + (hinge.z - pedal.hinge.z) ^ 2
			)
			if off > HINGE_TOLERANCE then
				table.insert(problems, `the footwell's {pedal.part} hinge is {off} m off the binding's pivot`)
			end
			if bound.axis.right < 0.999 then
				table.insert(
					problems,
					`the binding turns {pedal.part} about another axis than the car's right`
				)
			end
			if bound.travel and math.abs(bound.travel - pedal.travel) > 1e-4 then
				table.insert(
					problems,
					`the footwell turns {pedal.part} by {pedal.travel} rad, the binding by {bound.travel}`
				)
			end
		end
	end
	return problems
end

function Contract.features(entry: Entry): Features
	local switches = entry.switches
	return {
		pitLimiter = switches.pitLimiter ~= nil,
		wiper = switches.wiper ~= nil,
		rainLight = switches.rainLight,
		displayPages = switches.displayPages ~= nil,
		radio = switches.radio == true,
		escButton = entry.assists.escButton ~= nil,
		launch = entry.physics.launch ~= nil,
		cabinLight = entry.model.cabinLight ~= nil,
		playerClutch = GearboxModes.offersClutch(entry.physics.gearbox, true),
	}
end

return table.freeze(Contract)
