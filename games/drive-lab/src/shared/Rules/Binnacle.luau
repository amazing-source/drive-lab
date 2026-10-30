--!strict
--[[
	What a binnacle display shows (Config/Binnacle), without the engine: which shift lights are lit
	and in what colour, how far the rpm bar is filled, which page is up and the text of each field.
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
