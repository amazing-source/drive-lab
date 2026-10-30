--!strict
--[[
	What a binnacle display shows (Config/Binnacle), without the engine: which shift lights are lit
	and in what colour, how far the rpm bar is filled and how many of its segments are lit, which
	page is up, where it sits on the screen, and the text and pill colour of each field.
]]
local Binnacle = require("../Config/Binnacle")
local Cluster = require("../Config/Cluster")
local ClusterRules = require("./Cluster")

-- The car's readouts a field may show.
export type Readout = {
	rpm: number,
	gear: number,
	speedKmh: number,
	tcOn: boolean,
	-- The drive mode's label, as the HUD shows it.
	mode: string,
}

-- The strip's lamp states.
export type Lamps = { pitLimiter: boolean, fault: boolean }

local Rules = {}

-- The rpm at which rev light `index` (1 = the first) comes on.
function Rules.lightRpm(lights: Binnacle.RevLights, index: number): number
	local count = #lights.colours
	if count <= 1 then
		return lights.fromRpm
	end
	return lights.fromRpm + (lights.toRpm - lights.fromRpm) * (index - 1) / (count - 1)
end

-- Each rev light's colour at `rpm` and time `now` (seconds), or nil while it is dark.
function Rules.revLights(lights: Binnacle.RevLights, rpm: number, now: number): { Cluster.Rgb? }
	local shown: { Cluster.Rgb? } = table.create(#lights.colours)
	local flashing = rpm >= lights.flashRpm
	local dark = flashing and (now * lights.flashHz) % 1 >= 0.5
	for index, colour in lights.colours do
		local lit = rpm >= Rules.lightRpm(lights, index) and not dark
		shown[index] = if lit then colour else nil
	end
	return shown
end

-- The whole strip, left to right: the left lamp, the rev lights, the right lamp.
function Rules.strip(screen: Binnacle.Screen, rpm: number, now: number, lamps: Lamps): { Cluster.Rgb? }
	local shown: { Cluster.Rgb? } = {}
	local function lamp(spec: Binnacle.Lamp): Cluster.Rgb?
		return if lamps[spec.shows] then spec.rgb else nil
	end
	shown[1] = lamp(screen.leftLamp)
	local revs = Rules.revLights(screen.revLights, rpm, now)
	for index = 1, #screen.revLights.colours do
		shown[index + 1] = revs[index]
	end
	shown[#screen.revLights.colours + 2] = lamp(screen.rightLamp)
	return shown
end

-- How much of the rpm bar is filled, 0 to 1.
function Rules.barShare(screen: Binnacle.Screen, rpm: number): number
	return math.clamp((rpm - screen.barFromRpm) / (screen.barToRpm - screen.barFromRpm), 0, 1)
end

-- How many of the band's segments are lit at `rpm`, from the first: each lights at its own rpm.
function Rules.litSegments(segments: { Binnacle.Segment }, rpm: number): number
	local lit = 0
	for _, segment in segments do
		if rpm < segment.rpm then
			break
		end
		lit += 1
	end
	return lit
end

-- The colour of a field's pill while it shows `text`, or nil when it has none for that text.
function Rules.pillColour(field: Binnacle.Field, text: string): Cluster.Rgb?
	local pill = field.pill
	return if pill then pill[text] else nil
end

-- Where a page goes on the screen, as shares of the screen: as large as fits, centred. Aspects
-- are width over height.
function Rules.fitPage(screenAspect: number, pageAspect: number): Binnacle.Rect
	if screenAspect >= pageAspect then
		local width = pageAspect / screenAspect
		return { x = (1 - width) / 2, y = 0, width = width, height = 1 }
	end
	local height = screenAspect / pageAspect
	return { x = 0, y = (1 - height) / 2, width = 1, height = height }
end

-- The page shown for `page`, counted from 1 and wrapping round the display's pages.
function Rules.page(screen: Binnacle.Screen, page: number): Binnacle.Page
	local count = #screen.pages
	local index = ((math.floor(page) - 1) % count) + 1
	return screen.pages[index]
end

-- A field's text: the readout it shows, its fixed text, or "--" for what Drive Lab does not
-- simulate.
function Rules.fieldText(field: Binnacle.Field, readout: Readout): string
	local reading = field.reading
	if reading == "rpm" then
		return tostring(math.round(readout.rpm))
	elseif reading == "gear" then
		return ClusterRules.gearLabel(math.round(readout.gear))
	elseif reading == "speed" then
		return tostring(math.round(readout.speedKmh))
	elseif reading == "tcs" then
		return if readout.tcOn then "ON" else "OFF"
	elseif reading == "manettino" then
		return readout.mode
	elseif reading == "static" then
		return field.text or "--"
	end
	return "--"
end

return table.freeze(Rules)
