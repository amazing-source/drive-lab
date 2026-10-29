--!strict
--[[
	The driving HUD, from the owner's ChatGPT design of 2026-10-28 (a Lamborghini-style frame).
	The frame is one image with every rev segment unlit and the live readouts cleared; the game
	draws the rest over it at the boxes below. tools/assets/hud_layers.py cuts the design and
	prints every box; docs/pipelines/DRIVING_HUD.md has the steps. Boxes are { x0, y0, x1, y1 } in
	the frame's pixels (FRAME_SIZE), before its upload at 1024 wide; text is sized so its capitals
	fill its box's height. Colours are sampled from the design.

	A rev segment is a thousand rpm and fills as a needle would, red past the redline. In manual
	the lit segments flash blue past it for the upshift, at 2.5 Hz (under the 3 flashes a second
	that risk seizures, per the racing-HUD research of 2026-10-28).
]]
export type Box = { number }

export type HudConfig = {
	FRAME_IMAGE: string,
	PARTS_IMAGE: string,
	FRAME_SIZE: Vector2,
	SEGMENTS: { Box },
	PARTS: { first: Box, middle: Box, last: Box, light: Box },
	READOUTS: {
		mode: Box,
		tcText: Box,
		tcLine: Box,
		absText: Box,
		absLine: Box,
		box: Box,
		gear: Box,
		speed: Box,
		light: Box,
		indicatorLeft: Box,
		indicatorRight: Box,
	},
	HEIGHT: number,
	COCKPIT_HEIGHT: number,
	MAX_WIDTH: number,
	MARGIN: number,
	MINIMAL_SCALE: number,
	RPM_PER_SEGMENT: number,
	REDLINE_RPM: number,
	FLASH_HZ: number,
	CAP_HEIGHT: number,
	YELLOW: Color3,
	RED: Color3,
	BLUE: Color3,
	WHITE: Color3,
	GREY: Color3,
	LINE_GREY: Color3,
	GREEN: Color3,
	OFF: Color3,
	UPDATE_INTERVAL: number,
	GEAR_POP: number,
	-- Shown in the drive mode's place while launch control is armed or launching: our own UI, no
	-- source shows the car's (#74).
	LAUNCH_TEXT: string,
}

local Hud: HudConfig = table.freeze({
	FRAME_IMAGE = "rbxassetid://136575325662647",
	-- White masks the game tints: the first, a middle and the last rev segment, and the
	-- headlight icon. PARTS are their rectangles { x, y, width, height } in this image.
	PARTS_IMAGE = "rbxassetid://122022683037511",
	FRAME_SIZE = Vector2.new(2078, 477),
	SEGMENTS = table.freeze({
		{ 314, 65, 499, 101 },
		{ 479, 62, 647, 101 },
		{ 625, 62, 788, 101 },
		{ 767, 62, 929, 101 },
		{ 908, 62, 1071, 101 },
		{ 1050, 62, 1211, 101 },
		{ 1190, 62, 1350, 101 },
		{ 1332, 62, 1500, 101 },
		{ 1474, 62, 1642, 101 },
		{ 1618, 62, 1750, 93 },
	}),
	PARTS = table.freeze({
		first = { 0, 0, 185, 36 },
		middle = { 189, 0, 168, 39 },
		last = { 361, 0, 132, 31 },
		light = { 497, 0, 80, 62 },
	}),
	READOUTS = table.freeze({
		mode = { 271, 244, 489, 280 },
		tcText = { 305, 341, 355, 366 },
		tcLine = { 284, 389, 376, 396 },
		absText = { 518, 342, 599, 366 },
		absLine = { 510, 390, 609, 395 },
		box = { 1021, 194, 1058, 219 },
		gear = { 910, 240, 1115, 438 },
		-- Right edge 24 px in from the design's: Montserrat's italic leans past its box into km/h.
		speed = { 1347, 219, 1765, 345 },
		light = { 1763, 378, 1825, 425 },
		-- Not in the design: drawn only while they blink, either side of the light icon.
		indicatorLeft = { 1708, 376, 1743, 428 },
		indicatorRight = { 1843, 376, 1878, 428 },
	}),
	-- Share of the screen's height, the width following the frame's shape but kept within
	-- MAX_WIDTH of the screen. Bottom centre in the chase and hood views; bottom right, smaller,
	-- in the cockpit, where the centre is the steering wheel and the hands.
	HEIGHT = 0.17,
	COCKPIT_HEIGHT = 0.13,
	MAX_WIDTH = 0.9,
	MARGIN = 14,
	-- The minimal mode is the same HUD this much smaller.
	MINIMAL_SCALE = 0.72,
	RPM_PER_SEGMENT = 1000,
	REDLINE_RPM = 8500,
	FLASH_HZ = 2.5,
	-- Montserrat's capitals are this share of the TextSize, measured in Studio 2026-10-28
	-- (59 px at TextSize 100, centred on the label).
	CAP_HEIGHT = 0.59,
	YELLOW = Color3.fromRGB(253, 208, 2),
	RED = Color3.fromRGB(240, 20, 24),
	BLUE = Color3.fromRGB(61, 123, 255),
	WHITE = Color3.fromRGB(242, 242, 242),
	GREY = Color3.fromRGB(82, 82, 83),
	LINE_GREY = Color3.fromRGB(61, 61, 60),
	GREEN = Color3.fromRGB(0, 216, 55),
	-- The light icon when the headlights are off: the unlit segments' grey.
	OFF = Color3.fromRGB(58, 57, 56),
	UPDATE_INTERVAL = 1 / 30,
	-- Seconds the gear digit takes to settle after it pops on a change.
	GEAR_POP = 0.12,
	LAUNCH_TEXT = "LAUNCH",
})

return Hud
