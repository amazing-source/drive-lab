--!strict
--[[
	The instrument cluster: the Aventador SVJ's own face (the Assetto Corsa mod's display texture,
	512 x 256) with its rev counter, gear, speed and drive mode brought to life. Positions are
	pixels of that image; the dial's geometry was measured from it by
	tools/assets/cluster_layers.py, which also cut the three images. Colours per driving mode live
	in Config/ClusterTheme, which only the client needs.
]]
export type Spot = { x: number, y: number, size: number }

export type Cluster = {
	BASE_IMAGE: string,
	LIT_IMAGE: string,
	RED_IMAGE: string,
	IMAGE_WIDTH: number,
	IMAGE_HEIGHT: number,
	DIAL_X: number,
	DIAL_Y: number,
	LIT_SIZE: number,
	DIAL_START: number,
	DIAL_SWEEP: number,
	DIAL_MAX_RPM: number,
	CELLS: number,
	REDLINE_RPM: number,
	GEAR: Spot,
	SPEED: Spot,
	MODE: Spot,
	ESC: Spot,
	TC: Spot,
	ABS: Spot,
	STARTUP_SECONDS: number,
	LIMITER_FLASH_HZ: number,
	-- Shown under the gear, where the ESC light is, while launch control is armed or launching: our
	-- own UI, no source shows the car's (#74).
	LAUNCH_TEXT: string,
	CANVAS_WIDTH: number,
	CANVAS_HEIGHT: number,
	UPDATE_INTERVAL: number,
	BRIGHTNESS: number,
}

local Cluster: Cluster = table.freeze({
	-- The face with its "CORSA" label erased, the rev cells lit in white (tinted per mode), and
	-- the red-zone cells lit in red. Both lit images are squares centred on the dial.
	BASE_IMAGE = "rbxassetid://136505327286786",
	LIT_IMAGE = "rbxassetid://119842934651154",
	RED_IMAGE = "rbxassetid://93745139015553",
	IMAGE_WIDTH = 512,
	IMAGE_HEIGHT = 256,
	-- The dial's centre and the lit squares' side, image pixels.
	DIAL_X = 256.26,
	DIAL_Y = 200.76,
	LIT_SIZE = 352,
	-- Where 0 rpm sits and how far the dial runs to 10,000: degrees clockwise from the right.
	DIAL_START = 209.75,
	DIAL_SWEEP = 120.5,
	DIAL_MAX_RPM = 10000,
	-- One cell per 500 rpm; the last three, from 8500, are the red zone.
	CELLS = 20,
	REDLINE_RPM = 8500,
	-- Live readouts, image pixels: the gear inside the dial, the speed above the face's own km/h,
	-- the mode where the face printed CORSA, the tell-tales beside the gear.
	GEAR = { x = 256, y = 82, size = 30 },
	SPEED = { x = 379, y = 157, size = 20 },
	MODE = { x = 190.5, y = 109.5, size = 8.5 },
	-- The ESC light, under the gear in the free band between the mode and the odometer.
	ESC = { x = 256, y = 110, size = 6 },
	TC = { x = 205, y = 93, size = 6 },
	ABS = { x = 307, y = 93, size = 6 },
	-- The rev counter sweeps to the top and back when START is pressed (unsourced for the SVJ: no
	-- reference of its start-up screen was found, 2026-10-28).
	STARTUP_SECONDS = 1.4,
	LIMITER_FLASH_HZ = 10,
	LAUNCH_TEXT = "LAUNCH",
	-- Pixels of the screen's canvas, about 2.5 : 1 like the screen; the face fills its height.
	CANVAS_WIDTH = 1240,
	CANVAS_HEIGHT = 500,
	UPDATE_INTERVAL = 1 / 30,
	BRIGHTNESS = 1.6,
})

return Cluster
