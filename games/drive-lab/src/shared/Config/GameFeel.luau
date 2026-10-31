--!strict
--[[
	The game-feel level (docs/research/14_game_handling.md): one setting, as racing games' assist
	presets are, that dials between the car as it is and a car that catches its own slides. Each
	notch above Realistic switches on the slide assist (Vehicle/SlideAssist) with that notch's
	values from the car's own profile (Config/Cars/<car>/Handling). Realistic is the car with no
	game help, exactly as it drove before the levels existed.
]]
export type Notch = "Realistic" | "Balanced" | "Forgiving"

export type GameFeel = {
	-- The order the key steps through, wrapping.
	ORDER: { Notch },
	DEFAULT: Notch,
	-- Shown in the HUD's drive-mode place for FLASH_SECONDS after a change.
	LABELS: { [Notch]: string },
	FLASH_SECONDS: number,
}

local ORDER: { Notch } = { "Realistic", "Balanced", "Forgiving" }

local LABELS: { [Notch]: string } = {
	Realistic = "REALISTIC",
	Balanced = "BALANCED",
	Forgiving = "FORGIVING",
}

-- The car stays its own until it is clearly sliding.
local DEFAULT: Notch = "Balanced"

local GameFeel: GameFeel = table.freeze({
	ORDER = table.freeze(ORDER),
	DEFAULT = DEFAULT,
	LABELS = table.freeze(LABELS),
	FLASH_SECONDS = 1.5,
})

return GameFeel
