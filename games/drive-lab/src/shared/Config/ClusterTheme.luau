--!strict
export type Theme = { accent: Color3, dim: Color3, text: Color3 }

export type ClusterTheme = {
	MODES: { [string]: Theme },
	WARNING: Color3,
	BACKGROUND: Color3,
}

-- Per driving mode, as the SVJ's cluster recolours itself: Strada cool white, Sport yellow,
-- Corsa orange. The accent tints the lit rev cells and the mode's name; dim is an unlit
-- tell-tale.
local ClusterTheme: ClusterTheme = table.freeze({
	MODES = table.freeze({
		Strada = {
			accent = Color3.fromRGB(150, 225, 255),
			dim = Color3.fromRGB(28, 44, 52),
			text = Color3.fromRGB(235, 245, 255),
		},
		Sport = {
			accent = Color3.fromRGB(255, 214, 40),
			dim = Color3.fromRGB(52, 46, 14),
			text = Color3.fromRGB(255, 248, 225),
		},
		Corsa = {
			accent = Color3.fromRGB(255, 120, 30),
			dim = Color3.fromRGB(56, 30, 12),
			text = Color3.fromRGB(255, 236, 220),
		},
	}),
	-- A tell-tale while its system acts (TC, ABS).
	WARNING = Color3.fromRGB(255, 170, 30),
	-- Around the face, where the screen is wider than the image.
	BACKGROUND = Color3.fromRGB(0, 0, 0),
})

return ClusterTheme
