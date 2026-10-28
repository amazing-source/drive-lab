--!strict
--[[
	The roadside reflectors' glow in the driven car's headlights (Rules/Reflectors,
	Controllers/Reflectors). Reflector parts are tagged in the roadside models; each one's face
	points along its model's -X (red, towards traffic on its own side) or +X (white, towards the
	oncoming traffic), as tools/blender/roadside_props.py builds them.
]]
local Reflectors = require("../Rules/Reflectors")

export type Config = {
	TAG: string,
	FACING: { [string]: Vector3 },
	GLOW: { [string]: Color3 },
	UPDATE_INTERVAL: number,
	TUNING: Reflectors.Tuning,
	DOTS: {
		count: number,
		nearPixels: number,
		farPixels: number,
		nearDistance: number,
		farDistance: number,
		brightness: number,
	},
}

local Config: Config = table.freeze({
	TAG = "DriveLabReflector",
	-- Each reflector part's face, in its model's axes, by part name.
	FACING = table.freeze({
		ReflectorRed = Vector3.new(-1, 0, 0),
		ReflectorWhite = Vector3.new(1, 0, 0),
	}),
	-- Lit colours: the neon's brightness follows the colour, so a dimmer step is a darker one.
	GLOW = table.freeze({
		ReflectorRed = Color3.fromRGB(255, 34, 18),
		ReflectorWhite = Color3.fromRGB(255, 246, 225),
	}),
	UPDATE_INTERVAL = 0.1,
	TUNING = table.freeze({
		-- Bright to 70 m, gone by 320 m: a delineator is seen from much further than the
		-- headlights light the road.
		fullTo = 70,
		reach = 320,
		-- Within 18 degrees of the car's heading in full, out by 38 degrees.
		cone = math.cos(math.rad(18)),
		coneEdge = math.cos(math.rad(38)),
		edgeOn = 0.15,
		faceOn = 0.5,
		levels = 4,
	}),
	-- The glow dots (Effects/ReflectorDots) on the nearest lit reflectors: pixels across, from
	-- near at 20 m to far at 250 m; brightness over 1 lets them bloom.
	DOTS = table.freeze({
		count = 40,
		nearPixels = 5,
		farPixels = 2,
		nearDistance = 20,
		farDistance = 250,
		brightness = 1.6,
	}),
})

return Config
