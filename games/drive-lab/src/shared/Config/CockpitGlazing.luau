--!strict
--[[
	The windows' look in the cockpit view (Controllers/CockpitGlazing). Roblox's Glass draws no
	particles or transparent objects behind it (by design, since 2017), so from inside the car
	the rain outside vanished; in that view the windows become this plastic instead. Nearly
	clear with a faint cool tint, so the glass still reads as glass. Tuned by eye in edit-mode
	captures (2026-10-28).
]]
export type CockpitGlazing = {
	MATERIAL: string,
	TRANSPARENCY: number,
	COLOR: { r: number, g: number, b: number },
	REFLECTANCE: number,
}

local CockpitGlazing: CockpitGlazing = table.freeze({
	MATERIAL = "SmoothPlastic",
	TRANSPARENCY = 0.88,
	COLOR = table.freeze({ r = 188, g = 198, b = 206 }),
	REFLECTANCE = 0,
})

return CockpitGlazing
