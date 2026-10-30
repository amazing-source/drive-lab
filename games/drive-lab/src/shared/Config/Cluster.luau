--!strict
--[[
	The instrument cluster: the shape of a car's display (its entry's cluster), an image face whose
	rev counter, gear, speed and drive mode are brought to life, and what every car's display
	shares. Positions are pixels of the face image; tools/assets/cluster_layers.py measures them
	and cuts the images.
]]
export type Spot = { x: number, y: number, size: number }

-- Colours as 0-255 channels, so Lune can load every car's entry.
export type Rgb = { r: number, g: number, b: number }

-- A drive mode's colours: the accent tints the lit rev cells and the mode's name; dim is an unlit
-- tell-tale.
export type Theme = { accent: Rgb, dim: Rgb, text: Rgb }

export type Face = {
	-- The face, its rev cells lit in white (tinted per mode), and its red-zone cells lit in red;
	-- both lit images are squares centred on the dial.
	baseImage: string,
	litImage: string,
	redImage: string,
	imageWidth: number,
	imageHeight: number,
	-- The dial's centre and the lit squares' side, image pixels.
	dialX: number,
	dialY: number,
	litSize: number,
	-- Where 0 rpm sits and how far the dial runs to dialMaxRpm: degrees clockwise from the right.
	dialStart: number,
	dialSweep: number,
	dialMaxRpm: number,
	cells: number,
	-- The red zone starts here; the HUD's rev segments turn red here too.
	redlineRpm: number,
	-- Live readouts, image pixels.
	gear: Spot,
	speed: Spot,
	mode: Spot,
	esc: Spot,
	tc: Spot,
	abs: Spot,
	-- Seconds the rev counter takes to sweep to the top and back when START is pressed.
	startupSeconds: number,
	limiterFlashHz: number,
	-- Pixels of the screen's canvas; the face fills its height.
	canvasWidth: number,
	canvasHeight: number,
	brightness: number,
	-- Per drive mode, a tell-tale while its system acts (TC, ABS), and around the face where the
	-- screen is wider than the image.
	modes: { [string]: Theme },
	warning: Rgb,
	background: Rgb,
}

export type Cluster = {
	-- Shown under the gear, where the ESC light is, while launch control is armed or launching: our
	-- own UI, no source shows the car's (#74).
	LAUNCH_TEXT: string,
	UPDATE_INTERVAL: number,
}

local Cluster: Cluster = table.freeze({
	LAUNCH_TEXT = "LAUNCH",
	UPDATE_INTERVAL = 1 / 30,
})

return Cluster
