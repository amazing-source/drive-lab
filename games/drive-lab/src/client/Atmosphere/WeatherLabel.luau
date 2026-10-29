--!strict
--[[
	The name of the weather the player's key just chose, shown for a moment near the top of the
	screen in the controls hint's style (Controllers/ControlsHelp).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Help = require(ReplicatedStorage.Shared.Config.ControlsHelp)
local Hud = require(ReplicatedStorage.Shared.Config.Hud)

local ControlsPanel = require(script.Parent.Parent.Ui.ControlsPanel)

export type WeatherLabel = { gui: ScreenGui, label: TextLabel, stroke: UIStroke, token: number }

local WeatherLabel = {}

function WeatherLabel.new(parent: Instance): WeatherLabel
	local gui = Instance.new("ScreenGui")
	gui.Name = "DriveLabWeather"
	gui.ResetOnSpawn = false
	-- Level with the controls hint (6), above the driving HUD (5).
	gui.DisplayOrder = 6

	local label = Instance.new("TextLabel")
	label.Name = "Weather"
	label.Active = false
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.fromScale(0.5, 0.08)
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.BackgroundColor3 = ControlsPanel.panelColor()
	label.BackgroundTransparency = 1
	label.TextTransparency = 1
	label.FontFace = ControlsPanel.BOLD
	label.TextSize = Help.GROUP_SIZE + 3
	label.TextColor3 = Hud.WHITE
	label.Parent = gui
	ControlsPanel.pad(label, Help.PADDING, Help.PADDING / 2)
	local stroke = ControlsPanel.round(label, 8, Hud.YELLOW)
	stroke.Transparency = 1

	gui.Parent = parent
	return { gui = gui, label = label, stroke = stroke, token = 0 }
end

local function fade(weather: WeatherLabel, shown: boolean)
	local info = TweenInfo.new(Help.FADE_SECONDS)
	local transparency = if shown then 0 else 1
	TweenService:Create(weather.label, info, {
		TextTransparency = transparency,
		BackgroundTransparency = if shown then Help.PANEL_TRANSPARENCY else 1,
	}):Play()
	TweenService:Create(weather.stroke, info, { Transparency = transparency }):Play()
end

-- Shows `text` for `seconds`; a newer call restarts the clock.
function WeatherLabel.show(weather: WeatherLabel, text: string, seconds: number)
	weather.token += 1
	local token = weather.token
	weather.label.Text = text
	fade(weather, true)
	task.delay(seconds, function()
		if weather.token == token and weather.gui.Parent then
			fade(weather, false)
		end
	end)
end

function WeatherLabel.destroy(weather: WeatherLabel)
	weather.token += 1
	weather.gui:Destroy()
end

return WeatherLabel
