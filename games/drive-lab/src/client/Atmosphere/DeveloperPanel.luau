--!strict
--[[
	Studio-only controls for judging the weather: the four presets, the live RainIntensity and
	Wetness, the quality tier, and a wetness override for captures. The override is labelled on
	screen whenever it is on, so a capture taken with it can never pass for the simulated state.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.Atmosphere)

export type Actions = {
	choose: (name: Config.PresetName) -> (),
	cycleOverride: () -> (),
}

export type Readout = {
	target: string,
	progress: number,
	rainIntensity: number,
	wetness: number,
	simulated: number,
	override: number?,
	tier: Config.Tier,
}

export type Panel = { gui: ScreenGui, status: TextLabel, override: TextButton }

local WIDTH = 230
local ROW = 26
local FONT = Font.fromEnum(Enum.Font.GothamMedium)
local TEXT_SIZE = 14
local TEXT = Color3.fromRGB(235, 238, 242)
local IDLE = Color3.fromRGB(32, 34, 38)
local WARNING = Color3.fromRGB(190, 90, 20)

local function label(parent: Instance, value: string, order: number, rows: number): TextLabel
	local item = Instance.new("TextLabel")
	item.FontFace = FONT
	item.TextSize = TEXT_SIZE
	item.TextColor3 = TEXT
	item.Text = value
	item.BorderSizePixel = 0
	item.BackgroundTransparency = 1
	item.Size = UDim2.new(1, 0, 0, ROW * rows)
	item.LayoutOrder = order
	item.Parent = parent
	return item
end

local function button(parent: Instance, value: string, order: number, pressed: () -> ()): TextButton
	local item = Instance.new("TextButton")
	item.FontFace = FONT
	item.TextSize = TEXT_SIZE
	item.TextColor3 = TEXT
	item.Text = value
	item.BorderSizePixel = 0
	item.Size = UDim2.new(1, 0, 0, ROW)
	item.LayoutOrder = order
	item.AutoButtonColor = true
	item.BackgroundColor3 = IDLE
	item.Activated:Connect(pressed)
	item.Parent = parent
	return item
end

local DeveloperPanel = {}

function DeveloperPanel.new(parent: Instance, actions: Actions): Panel
	local gui = Instance.new("ScreenGui")
	gui.Name = "DriveLabAtmospherePanel"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50

	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(1, 0)
	frame.Position = UDim2.new(1, -12, 0, 60)
	frame.Size = UDim2.fromOffset(WIDTH, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = Color3.fromRGB(18, 19, 22)
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame

	label(frame, "Atmosphere (Studio only)", 0, 1)
	for index, preset in Config.PRESETS do
		button(frame, preset.label, index, function()
			actions.choose(preset.name)
		end)
	end
	local status = label(frame, "", #Config.PRESETS + 1, 3)
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextYAlignment = Enum.TextYAlignment.Top
	local override = button(frame, "Wetness override: off", #Config.PRESETS + 2, actions.cycleOverride)

	gui.Parent = parent
	return { gui = gui, status = status, override = override }
end

function DeveloperPanel.show(panel: Panel, readout: Readout)
	local lines = {
		string.format("RainIntensity  %.2f", readout.rainIntensity),
		string.format("Wetness  %.3f  (simulated %.3f)", readout.wetness, readout.simulated),
		string.format(
			"To %s %d %%  |  tier %s",
			readout.target,
			math.round(readout.progress * 100),
			readout.tier
		),
	}
	panel.status.Text = table.concat(lines, "\n")
	if readout.override then
		panel.override.Text = string.format("CAPTURE OVERRIDE  W = %.2f", readout.override)
		panel.override.BackgroundColor3 = WARNING
	else
		panel.override.Text = "Wetness override: off"
		panel.override.BackgroundColor3 = IDLE
	end
end

function DeveloperPanel.destroy(panel: Panel)
	panel.gui:Destroy()
end

return DeveloperPanel
