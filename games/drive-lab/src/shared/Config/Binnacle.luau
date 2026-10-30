--!strict
--[[
	A binnacle display: a race car's screen behind the wheel with pages of readouts and a strip of
	shift lights (Controllers/Binnacle, Rules/Binnacle), the other kind of car display beside
	Config/Cluster's dial face. Each page is a design image with the live values drawn over it.
	Places on a page are normalised to the page image (0 to 1 from its top left); places in a
	sheet are the sheet's pixels; colours are 0-255 channels.
]]
local Cluster = require("./Cluster")

-- What a field shows: one of the car's readouts, a fixed text, or nothing Drive Lab simulates.
export type Reading = "rpm" | "gear" | "speed" | "tcs" | "manettino" | "static" | "none"

export type Field = {
	label: string,
	reading: Reading,
	-- The text a "static" field shows.
	text: string?,
	-- A field shown on a pill: the pill's colour for each text it shows.
	pill: { [string]: Cluster.Rgb }?,
}

export type Rect = { x: number, y: number, width: number, height: number }

-- A picture in an uploaded sheet.
export type Sprite = { image: string, x: number, y: number, width: number, height: number }

-- One segment of the rpm band: lit from `rpm`; its outline as four corners (x, y pairs, clockwise
-- from the top left); where its lit image goes on the page.
export type Segment = { rpm: number, corners: { number }, rect: Rect, sprite: Sprite }

-- A printed mark of the band (rpm), where its number is printed.
export type Mark = { rpm: number, x: number, y: number }

export type Band = { segments: { Segment }, rgb: Cluster.Rgb, marks: { Mark } }

-- A pill on the page: where it is, its colour in the design, and a white mask of its shape.
export type Pill = { rect: Rect, rgb: Cluster.Rgb, sprite: Sprite }

-- A page's design. The screen is wider than the page, so the sides beside it take its edge
-- colour, and the title strip's colour across its top `height`. Per label: where the label is
-- printed and the slot its value goes in (the value's capitals fill the slot's height, centred
-- across its width).
export type PageArt = {
	art: Sprite,
	edge: Cluster.Rgb,
	title: { height: number, rgb: Cluster.Rgb }?,
	labels: { [string]: Rect },
	slots: { [string]: Rect },
	pills: { [string]: Pill }?,
	band: Band?,
}

-- Each lamp of the strip, left to right: its unlit image and its lit one (grey, tinted with the
-- light's colour).
export type LampArt = { off: { Sprite }, on: { Sprite } }

-- What tools/assets/binnacle_layers.py measures on the design pack.
export type Layout = {
	pages: { [string]: PageArt },
	valueRgb: Cluster.Rgb,
	pillTextRgb: Cluster.Rgb,
	lamps: LampArt,
}

export type Page = { title: string, fields: { Field }, art: PageArt }

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

export type Face = "Front" | "Back" | "Left" | "Right" | "Top" | "Bottom"

export type Font = {
	family: string,
	weight: "Regular" | "Medium" | "SemiBold" | "Bold",
	-- The capitals' height, and how far their middle sits below the middle of the label's box,
	-- as shares of the TextSize.
	capHeight: number,
	capOffset: number,
}

export type Screen = {
	-- The screen's shape, which the pages are centred in at full height.
	canvasWidth: number,
	canvasHeight: number,
	brightness: number,
	-- The screen while it is off.
	background: Cluster.Rgb,
	font: Font,
	valueRgb: Cluster.Rgb,
	pillTextRgb: Cluster.Rgb,
	-- The rpm range of the first page's band and its printed marks (x1000 rpm).
	barFromRpm: number,
	barToRpm: number,
	barMarks: { number },
	-- The red zone starts here; the HUD's rev segments turn red here too.
	redlineRpm: number,
	pages: { Page },
	-- The strip above the screen, left to right: a lamp, the rev lights, a lamp.
	leftLamp: Lamp,
	revLights: RevLights,
	rightLamp: Lamp,
	-- The strip's lens parts on the car's model, left to right, the face each shows the driver,
	-- and their images.
	lenses: { string },
	lensFace: Face,
	lamps: LampArt,
}

return {}
