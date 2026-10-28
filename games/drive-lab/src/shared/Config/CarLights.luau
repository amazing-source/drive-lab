--!strict
--[[
	A car's lights. The model's light meshes are split in four clusters (tools/blender/
	split_lights.py) whose SurfaceAppearance glow is driven here, plus Roblox lights added at
	run time: a headlight beam per front cluster, a red glow per rear one, an amber blink per
	cluster for the indicators, and a reversing light. Colours after the Assetto Corsa mod's
	own: headlights 1500,1500,1540 (a cool white), brake 350,27,0, indicators 230,120,0.
]]
local CarLights = require("../Rules/CarLights")

export type Glow = { strength: number, tint: Color3 }

export type CarLightsConfig = {
	PARTS: { frontLeft: string, frontRight: string, rearLeft: string, rearRight: string },
	TUNING: CarLights.Tuning,
	FRONT_DRL: number,
	FRONT_HEADLIGHTS: number,
	REAR_POSITION: number,
	REAR_BRAKE: number,
	REAR_TINT: Color3,
	INDICATOR_TINT: Color3,
	HEADLIGHT: {
		range: number,
		angle: number,
		brightness: number,
		color: Color3,
		pitch: number,
		inset: number,
	},
	TAIL: { range: number, brightness: number, brakeRange: number, brakeBrightness: number, color: Color3 },
	INDICATOR: { range: number, brightness: number, color: Color3 },
	REVERSE: { range: number, angle: number, brightness: number, color: Color3, drop: number },
}

local Config: CarLightsConfig = table.freeze({
	PARTS = table.freeze({
		frontLeft = "Light_FrontLeft",
		frontRight = "Light_FrontRight",
		rearLeft = "Light_RearLeft",
		rearRight = "Light_RearRight",
	}),
	-- Headlights come on by themselves at night or in rain this heavy; a brake pedal past this
	-- lights the brakes; indicators blink at 1.5 Hz, as the law's 60-120 a minute asks.
	TUNING = table.freeze({ rainOn = 0.3, brakeOn = 0.05, blinkHz = 1.5 }),
	-- SurfaceAppearance glow (EmissiveStrength): the daytime running lights are always on and
	-- the headlights add to them; the rear position lights glow with them, the brakes far more.
	FRONT_DRL = 1,
	FRONT_HEADLIGHTS = 1.8,
	REAR_POSITION = 0.6,
	REAR_BRAKE = 2.6,
	-- The model's rear clusters glow white through their emissive map; the SVJ's LEDs are red.
	REAR_TINT = Color3.fromRGB(255, 45, 30),
	INDICATOR_TINT = Color3.fromRGB(255, 140, 20),
	-- One beam per headlight from the front of its cluster: range at Roblox's 60-stud maximum,
	-- dipped a little (radians), shadows on so the road ahead reads.
	HEADLIGHT = table.freeze({
		range = 60,
		angle = 55,
		brightness = 5,
		color = Color3.fromRGB(240, 240, 255),
		pitch = math.rad(-3),
		-- Studs in from the cluster's front end, where the lamp itself sits.
		inset = 0.6,
	}),
	TAIL = table.freeze({
		range = 4,
		brightness = 0.4,
		brakeRange = 8,
		brakeBrightness = 2.2,
		color = Color3.fromRGB(255, 25, 0),
	}),
	INDICATOR = table.freeze({ range = 6, brightness = 1.6, color = Color3.fromRGB(255, 140, 20) }),
	-- Below the rear clusters at the car's centre, facing back; drop is studs down from them.
	REVERSE = table.freeze({
		range = 24,
		angle = 100,
		brightness = 2,
		color = Color3.fromRGB(255, 255, 250),
		drop = 1.2,
	}),
})

return Config
