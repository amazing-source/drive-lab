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
local DriverStartup = require("../DriverStartup")
local Driving = require("../Driving")
local RimBlur = require("../RimBlur")
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
	lights: CarLights.Lights,
	-- The car's display: a dial face, or a binnacle screen with pages and shift lights. One of them.
	cluster: Cluster.Face?,
	binnacle: Binnacle.Screen?,
	assists: DriverAssists.Tuning,
	switches: CarSwitches.Switches,
}

-- What a car has of the controls not every car has (Config/CarSwitches.NEEDS), by name.
export type Features = { [string]: boolean }

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
	local moved: { [string]: boolean } = {}
	for _, move in startup.moves do
		local name = move.control
		assert(controls[name], `the start-up moves "{name}", which the model binding does not hinge`)
		assert(not moved[name], `the start-up moves "{name}" twice`)
		moved[name] = true
		assert(move.move > 0, `"{name}" needs a move time above 0`)
		assert(move.back == nil or move.back >= move.at, `"{name}" turns back before it has arrived`)
	end
	assert(startup.pressAt < startup.drivableAt, "driving unlocks before START is pressed")
	assert(startup.wheelAt <= startup.drivableAt, "driving unlocks before the hands are on the wheel")
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
	for _, pedal in { footwell.throttle, footwell.brake } do
		assert(hinged[pedal.part], `the footwell's "{pedal.part}" is not a pedal the model binding hinges`)
	end
	for _, problem in Contract.footwellMismatches(entry.model, footwell) do
		error(problem)
	end
end

-- The driver's scale and arm lengths need to be usable sizes.
local function checkDriverSize(entry: Entry)
	local driver = entry.driver
	assert(driver.scale == nil or driver.scale > 0, "the driver's scale must be positive")
	local arms = driver.arms
	assert(arms == nil or (arms.upper > 0 and arms.lower > 0), "the driver's arms need positive lengths")
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

local function checkDisplay(entry: Entry)
	local face, screen = entry.cluster, entry.binnacle
	assert((face == nil) ~= (screen == nil), "a car has one display: a dial face or a binnacle screen")
	if face then
		checkCluster(entry, face)
	elseif screen then
		checkBinnacle(entry, screen)
	end
end

-- The switches' numbers are usable: a limiter with a band, a wiper with a wipe time, more than
-- one display page.
local function checkSwitches(entry: Entry)
	local switches = entry.switches
	local pit = switches.pitLimiter
	if pit then
		assert(pit.limitKmh > 0 and pit.band > 0, "the pit limiter needs a limit and a band")
		assert(pit.armBelowKmh <= pit.limitKmh, "the pit limiter arms above its own limit")
	end
	local wiper = switches.wiper
	if wiper then
		assert(wiper.wipeSeconds > 0, "the wiper needs a wipe time")
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

function Contract.define(entry: Entry): Entry
	checkStartup(entry)
	checkFootwell(entry)
	checkDriverSize(entry)
	checkModes(entry)
	checkDisplay(entry)
	checkSwitches(entry)
	Contract.checkStartupSound(entry.startup, entry.audio)
	return deepFreeze(entry)
end

-- Where the car's red zone starts, on its display and the HUD's rev segments.
function Contract.redline(entry: Entry): number
	local face, screen = entry.cluster, entry.binnacle
	if face then
		return face.redlineRpm
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

-- Metres a footwell hinge may sit off the binding's pivot for the same pedal.
local HINGE_TOLERANCE = 0.01

-- Where the footwell disagrees with the binding: Rules/DriverLegs turns each pedal's sole points
-- about the seat's x (the car's right) by the footwell's travel, while the rig turns the pedal's
-- weld about the binding's axis by the binding's travel, so the hinge, the axis and the signed
-- travel have to be the same or the foot and the pedal move apart.
function Contract.footwellMismatches(model: Binding.CarModel, footwell: DriverLegs.Footwell): { string }
	local problems = {}
	local seat = model.seat
	local byPart: { [string]: Binding.Hinge } = {}
	local pedals = model.pedals
	if pedals then
		for _, pedal in pedals do
			byPart[pedal.part] = pedal
		end
	end
	for _, pedal in { footwell.throttle, footwell.brake } do
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
		escButton = entry.assists.escButton ~= nil,
		launch = entry.physics.launch ~= nil,
		cabinLight = entry.model.cabinLight ~= nil,
	}
end

return table.freeze(Contract)
