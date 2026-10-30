--!strict
--[[
	Exhaust flames, fired with each pop the engine sound plays. After the Assetto Corsa mod's own
	set-up (data/flames.ini, extension/ext_config.ini): flames thrown back and a little up
	(direction 0, 0.175, -1), a light flash with each; textures from its texture/flames folder (a
	blue jet bursting orange, and fireball puffs as a 2 x 2 flipbook). Where the outlets are is the
	car's (its model binding's exhaust).
]]
export type Range = { from: number, to: number }

export type ExhaustFlames = {
	JET_TEXTURE: string,
	FIREBALL_TEXTURE: string,
	RISE: number,
	JET: { lifetime: Range, speed: Range, size: Range, count: Range },
	FIREBALL: { lifetime: Range, speed: Range, size: Range, hot: Color3, cool: Color3 },
	FLASH: { range: number, brightness: number, seconds: number, color: Color3 },
}

local ExhaustFlames: ExhaustFlames = table.freeze({
	JET_TEXTURE = "rbxassetid://104234237829384",
	FIREBALL_TEXTURE = "rbxassetid://82429406576820",
	-- Upward share of the flames' direction, as the mod's 0.175.
	RISE = 0.175,
	-- Studs and seconds at the world scale; a stronger pop throws more and bigger flames.
	JET = table.freeze({
		lifetime = { from = 0.05, to = 0.09 },
		speed = { from = 16, to = 26 },
		size = { from = 0.8, to = 1.7 },
		count = { from = 1, to = 3 },
	}),
	FIREBALL = table.freeze({
		lifetime = { from = 0.08, to = 0.15 },
		speed = { from = 5, to = 9 },
		size = { from = 0.6, to = 1.9 },
		-- The mod's puffs are near white; tinted from a hot yellow to orange as they cool.
		hot = Color3.fromRGB(255, 205, 130),
		cool = Color3.fromRGB(255, 95, 35),
	}),
	-- Checked at night in Studio: brightness 6 over 12 studs lit the whole road orange.
	FLASH = table.freeze({
		range = 10,
		brightness = 3.5,
		seconds = 0.06,
		color = Color3.fromRGB(255, 150, 70),
	}),
})

return ExhaustFlames
