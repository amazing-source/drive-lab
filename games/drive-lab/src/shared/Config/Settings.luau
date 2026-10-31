--!strict
--[[
	The player's settings, shown in their own section of the controls screen (Ui/ControlsPanel)
	and kept for the session only (src/client/Settings): a new setting is one more entry here,
	read by whatever it changes with Settings.get(id).
]]
local Rules = require("../Rules/Settings")

export type SettingsConfig = {
	TITLE: string,
	LIST: { Rules.Setting },
}

local Settings: SettingsConfig = table.freeze({
	TITLE = "Settings",
	LIST = table.freeze({
		table.freeze({
			id = "MotionBlur",
			label = "Motion blur",
			text = "How much the view blurs when the camera turns fast, at speed and under hard acceleration. Light is a third of Full; Off switches it off. Rain on the lens is weather and stays.",
			options = table.freeze({ "Off", "Light", "Full" }),
			default = "Light",
		}),
	}),
})

return Settings
