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
local RimBlur = require("../RimBlur")
local Types = require("./Types")

export type Driver = {
	grip: DriverArms.Grip,
	footwell: DriverLegs.Footwell,
	-- Both hands through the start-up, keyed against this car's cabin.
	startupPaths: DriverStartup.Paths,
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

function Contract.define(entry: Entry): Entry
	checkStartup(entry)
	checkFootwell(entry)
	checkModes(entry)
	checkDisplay(entry)
	checkSwitches(entry)
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

function Contract.features(entry: Entry): Features
	local switches = entry.switches
	return {
		pitLimiter = switches.pitLimiter ~= nil,
		wiper = switches.wiper ~= nil,
		rainLight = switches.rainLight,
		displayPages = switches.displayPages ~= nil,
		escButton = entry.assists.escButton ~= nil,
		launch = entry.physics.launch ~= nil,
	}
end

return table.freeze(Contract)
