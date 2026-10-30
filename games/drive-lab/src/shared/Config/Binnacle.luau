--!strict
--[[
	A binnacle display: a race car's screen behind the wheel with pages of readouts and a strip of
	shift lights (Controllers/Binnacle, Rules/Binnacle), the other kind of car display beside
	Config/Cluster's dial face. Pixels are the screen's canvas; colours are 0-255 channels.
]]
local Cluster = require("./Cluster")

-- What a field shows: one of the car's readouts, a fixed text, or nothing Drive Lab simulates.
export type Reading = "rpm" | "gear" | "speed" | "tcs" | "manettino" | "static" | "none"

export type Field = {
	label: string,
	reading: Reading,
	-- The text a "static" field shows.
	text: string?,
}

export type Page = { title: string, fields: { Field } }

-- One light of the strip that is not a rev light: lit steady while its state holds.
export type Lamp = { rgb: Cluster.Rgb, shows: "pitLimiter" | "fault" }

export type RevLights = {
	-- The first light comes on at fromRpm, the last at toRpm, the rest evenly between.
	fromRpm: number,
	toRpm: number,
	-- One colour per light, first to last.
	colours: { Cluster.Rgb },
	-- From this rpm every rev light flashes, at flashHz, lit the first half of each period.
	flashRpm: number,
	flashHz: number,
}

export type Screen = {
	canvasWidth: number,
	canvasHeight: number,
	brightness: number,
	background: Cluster.Rgb,
	text: Cluster.Rgb,
	dim: Cluster.Rgb,
	-- The rpm bar along the top of the first page: its range, its marks (x1000 rpm) and its fill.
	barFromRpm: number,
	barToRpm: number,
	barMarks: { number },
	barRgb: Cluster.Rgb,
	-- The red zone starts here; the HUD's rev segments turn red here too.
	redlineRpm: number,
	pages: { Page },
	-- The strip above the screen, left to right: a lamp, the rev lights, a lamp.
	leftLamp: Lamp,
	revLights: RevLights,
	rightLamp: Lamp,
	-- Canvas pixels of the strip, and of a light in it.
	stripHeight: number,
	lightSize: number,
}

return {}
