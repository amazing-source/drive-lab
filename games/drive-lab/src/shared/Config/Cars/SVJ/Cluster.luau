--!strict
--[[
	The Aventador SVJ's own cluster face (the Assetto Corsa mod's display texture, 512 x 256), its
	geometry measured from the image by tools/assets/cluster_layers.py, which also cut the three
	images (Config/Cluster Face).
]]
local Cluster = require("../../Cluster")

local function rgb(r: number, g: number, b: number): Cluster.Rgb
	return table.freeze({ r = r, g = g, b = b })
end

local Face: Cluster.Face = {
	-- The face with its "CORSA" label erased, the rev cells lit in white (tinted per mode), and
	-- the red-zone cells lit in red. Both lit images are squares centred on the dial.
	baseImage = "rbxassetid://136505327286786",
	litImage = "rbxassetid://119842934651154",
	redImage = "rbxassetid://93745139015553",
	imageWidth = 512,
	imageHeight = 256,
	dialX = 256.26,
	dialY = 200.76,
	litSize = 352,
	dialStart = 209.75,
	dialSweep = 120.5,
	dialMaxRpm = 10000,
	-- One cell per 500 rpm; the last three, from 8500, are the red zone.
	cells = 20,
	redlineRpm = 8500,
	-- The gear inside the dial, the speed above the face's own km/h, the mode where the face
	-- printed CORSA, the tell-tales beside the gear; the ESC light under the gear in the free band
	-- between the mode and the odometer.
	gear = table.freeze({ x = 256, y = 82, size = 30 }),
	speed = table.freeze({ x = 379, y = 157, size = 20 }),
	mode = table.freeze({ x = 190.5, y = 109.5, size = 8.5 }),
	esc = table.freeze({ x = 256, y = 110, size = 6 }),
	tc = table.freeze({ x = 205, y = 93, size = 6 }),
	abs = table.freeze({ x = 307, y = 93, size = 6 }),
	-- Unsourced for the SVJ: no reference of its start-up screen was found, 2026-10-28.
	startupSeconds = 1.4,
	limiterFlashHz = 10,
	-- About 2.5 : 1 like the screen.
	canvasWidth = 1240,
	canvasHeight = 500,
	brightness = 1.6,
	-- As the SVJ's cluster recolours itself: Strada cool white, Sport yellow, Corsa orange.
	modes = table.freeze({
		Strada = table.freeze({
			accent = rgb(150, 225, 255),
			dim = rgb(28, 44, 52),
			text = rgb(235, 245, 255),
		}),
		Sport = table.freeze({ accent = rgb(255, 214, 40), dim = rgb(52, 46, 14), text = rgb(255, 248, 225) }),
		Corsa = table.freeze({ accent = rgb(255, 120, 30), dim = rgb(56, 30, 12), text = rgb(255, 236, 220) }),
	}),
	warning = rgb(255, 170, 30),
	background = rgb(0, 0, 0),
}

return table.freeze(Face)
