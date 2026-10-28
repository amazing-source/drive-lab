--!strict
--[[
	The controls screen's panel (Config/ControlsHelp, laid out by Rules/ControlsHelp): a title, the
	groups in balanced columns, each row's label, keyboard and gamepad inputs and an (i). The (i)'s
	sentence shows beside it on hover or gamepad selection, and stays on a click or tap until the
	next. Built for one screen width, in the HUD's palette (Config/Hud).
]]
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config.ControlsHelp)
local Hud = require(ReplicatedStorage.Shared.Config.Hud)
local Rules = require(ReplicatedStorage.Shared.Rules.ControlsHelp)

local MONTSERRAT = "rbxasset://fonts/families/Montserrat.json"
local BODY = Font.new(MONTSERRAT, Enum.FontWeight.Medium)
local BOLD = Font.new(MONTSERRAT, Enum.FontWeight.Bold)
local KEY_HEX = `#{Hud.YELLOW:ToHex()}`
local INFO_GLYPH = "i"
local CLOSE_GLYPH = "×"

export type Panel = {
	gui: ScreenGui,
	columns: number,
	infos: { TextButton },
	tip: Frame,
	tipText: TextLabel,
	pinned: TextButton?,
}

local ControlsPanel = {}

ControlsPanel.BOLD = BOLD

function ControlsPanel.panelColor(): Color3
	local rgb = Config.PANEL_RGB
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

function ControlsPanel.round(item: GuiObject, radius: number, stroke: Color3): UIStroke
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = item
	local line = Instance.new("UIStroke")
	line.Color = stroke
	line.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	line.Parent = item
	return line
end

function ControlsPanel.pad(item: GuiObject, across: number, down: number)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, across)
	padding.PaddingRight = UDim.new(0, across)
	padding.PaddingTop = UDim.new(0, down)
	padding.PaddingBottom = UDim.new(0, down)
	padding.Parent = item
end

function ControlsPanel.columnsFor(screen: Vector2): number
	local room = screen.X - 2 * (Config.MARGIN + Config.PADDING) + Config.COLUMN_GAP
	return Rules.columnCount(room, Config.COLUMN_WIDTH + Config.COLUMN_GAP, Config.MAX_COLUMNS)
end

local function escape(text: string): string
	return (string.gsub(text, "[&<>]", { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;" }))
end

local function keysText(shown: Rules.Shown): string
	if #shown.keys == 0 then
		return Config.NO_INPUT
	end
	local parts = table.create(#shown.keys)
	for _, key in shown.keys do
		table.insert(parts, `<font color="{KEY_HEX}"><b>{escape(key)}</b></font>`)
	end
	local keys = table.concat(parts, " / ")
	return if shown.gesture then `{escape(shown.gesture)} {keys}` else keys
end

local function label(parent: Instance, text: string, font: Font, size: number, color: Color3): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.FontFace = font
	item.TextSize = size
	item.TextColor3 = color
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.TextYAlignment = Enum.TextYAlignment.Top
	item.TextWrapped = true
	item.RichText = true
	item.AutomaticSize = Enum.AutomaticSize.Y
	item.Size = UDim2.new(1, 0, 0, Config.ROW_HEIGHT)
	item.Text = text
	item.Parent = parent
	return item
end

local function cell(parent: Instance, text: string, from: number, share: number, color: Color3): TextLabel
	local item = label(parent, text, BODY, Config.TEXT_SIZE, color)
	item.Position = UDim2.fromScale(from, 0)
	item.Size = UDim2.new(share, -6, 0, Config.ROW_HEIGHT)
	return item
end

local function hideTip(panel: Panel)
	panel.pinned = nil
	panel.tip.Visible = false
end

local function showTip(panel: Panel, button: TextButton, text: string)
	local origin = panel.gui.AbsolutePosition
	local at = button.AbsolutePosition - origin
	local high = at.Y < panel.gui.AbsoluteSize.Y / 2
	local x = at.X - Config.TOOLTIP_WIDTH - 8
	if x < Config.MARGIN then
		x = at.X + button.AbsoluteSize.X + 8
	end
	panel.tip.AnchorPoint = Vector2.new(0, if high then 0 else 1)
	panel.tip.Position = UDim2.fromOffset(x, if high then at.Y - 4 else at.Y + button.AbsoluteSize.Y + 4)
	panel.tipText.Text = text
	panel.tip.Visible = true
end

local function info(panel: Panel, parent: Instance, text: string): TextButton
	local button = Instance.new("TextButton")
	button.Name = "Info"
	button.AnchorPoint = Vector2.new(1, 0)
	button.Position = UDim2.new(1, -2, 0, (Config.ROW_HEIGHT - Config.INFO_SIZE) / 2)
	button.Size = UDim2.fromOffset(Config.INFO_SIZE, Config.INFO_SIZE)
	button.AutoButtonColor = false
	button.BackgroundColor3 = Hud.LINE_GREY
	button.FontFace = BOLD
	button.TextSize = Config.TEXT_SIZE - 2
	button.TextColor3 = Hud.WHITE
	button.Text = INFO_GLYPH
	button.Parent = parent
	ControlsPanel.round(button, Config.INFO_SIZE / 2, Hud.GREY)
	button.MouseEnter:Connect(function()
		showTip(panel, button, text)
	end)
	button.MouseLeave:Connect(function()
		if panel.pinned ~= button then
			hideTip(panel)
		end
	end)
	button.SelectionGained:Connect(function()
		showTip(panel, button, text)
	end)
	button.SelectionLost:Connect(function()
		hideTip(panel)
	end)
	button.Activated:Connect(function()
		if panel.pinned == button then
			hideTip(panel)
		else
			showTip(panel, button, text)
			panel.pinned = button
		end
	end)
	table.insert(panel.infos, button)
	return button
end

local function row(
	panel: Panel,
	parent: Instance,
	entry: Rules.Row,
	bindings: Rules.Bindings,
	values: { [string]: string }
)
	local frame = Instance.new("Frame")
	frame.Name = entry.label
	frame.BackgroundTransparency = 1
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.Size = UDim2.new(1, 0, 0, Config.ROW_HEIGHT)
	frame.Parent = parent
	local keyboard, gamepad = Rules.inputs(entry, bindings, Config.HELP.keyNames)
	local shares = Config.SHARES
	cell(frame, escape(entry.label), 0, shares.label, Hud.WHITE)
	cell(frame, keysText(keyboard), shares.label, shares.keyboard, Hud.WHITE)
	cell(frame, keysText(gamepad), shares.label + shares.keyboard, shares.gamepad, Hud.WHITE)
	info(panel, frame, Rules.fill(entry.text, values))
end

local function captions(parent: Instance)
	local frame = Instance.new("Frame")
	frame.Name = "Captions"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, Config.ROW_HEIGHT)
	frame.Parent = parent
	local shares = Config.SHARES
	cell(frame, Config.KEYBOARD_CAPTION, shares.label, shares.keyboard, Hud.GREY)
	cell(frame, Config.GAMEPAD_CAPTION, shares.label + shares.keyboard, shares.gamepad, Hud.GREY)
end

local function list(parent: Instance, direction: Enum.FillDirection, gap: number)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = direction
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, gap)
	layout.Parent = parent
	return layout
end

local function header(frame: Frame, titles: { [string]: string }, onClose: () -> ())
	local title = label(frame, Config.TITLE, BOLD, Config.TITLE_SIZE, Hud.WHITE)
	title.Size = UDim2.new(1, -40, 0, Config.TITLE_SIZE)
	local subtitle =
		label(frame, escape(Rules.fill(Config.SUBTITLE, titles)), BODY, Config.TEXT_SIZE, Hud.WHITE)
	subtitle.Position = UDim2.fromOffset(0, Config.TITLE_SIZE + 4)
	subtitle.Size = UDim2.new(1, -40, 0, Config.TEXT_SIZE)
	subtitle.TextTransparency = 0.3

	local close = Instance.new("TextButton")
	close.Name = "Close"
	-- Frees a locked mouse (first person on foot) while the screen is open.
	close.Modal = true
	close.Selectable = false
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.fromScale(1, 0)
	close.Size = UDim2.fromOffset(32, 32)
	close.BackgroundTransparency = 1
	close.FontFace = BOLD
	close.TextSize = Config.TITLE_SIZE
	close.TextColor3 = Hud.WHITE
	close.Text = CLOSE_GLYPH
	close.Parent = frame
	close.Activated:Connect(onClose)
end

local function tooltip(gui: ScreenGui): (Frame, TextLabel)
	local tip = Instance.new("Frame")
	tip.Name = "Tip"
	tip.Visible = false
	tip.ZIndex = 5
	tip.BackgroundColor3 = ControlsPanel.panelColor()
	tip.AutomaticSize = Enum.AutomaticSize.Y
	tip.Size = UDim2.fromOffset(Config.TOOLTIP_WIDTH, 0)
	tip.Parent = gui
	ControlsPanel.round(tip, 6, Hud.YELLOW)
	ControlsPanel.pad(tip, 8, 8)
	local text = label(tip, "", BODY, Config.TEXT_SIZE, Hud.WHITE)
	text.ZIndex = 6
	text.Size = UDim2.fromScale(1, 0)
	text.RichText = false
	return tip, text
end

function ControlsPanel.build(
	parent: Instance,
	bindings: Rules.Bindings,
	screen: Vector2,
	titles: { [string]: string },
	onClose: () -> ()
): Panel
	local gui = Instance.new("ScreenGui")
	gui.Name = "ControlsHelp"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	local columns = ControlsPanel.columnsFor(screen)
	local room = screen.X - 2 * (Config.MARGIN + Config.PADDING)
	local width = math.min(Config.COLUMN_WIDTH, room)
	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.BackgroundColor3 = ControlsPanel.panelColor()
	frame.BackgroundTransparency = Config.PANEL_TRANSPARENCY
	frame.Parent = gui
	ControlsPanel.round(frame, 10, Hud.LINE_GREY)
	ControlsPanel.pad(frame, Config.PADDING, Config.PADDING)
	header(frame, titles, onClose)

	local body = Instance.new("ScrollingFrame")
	body.Name = "Body"
	body.Selectable = false
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Position = UDim2.fromOffset(0, Config.HEADER_HEIGHT)
	body.Size = UDim2.new(1, 0, 1, -Config.HEADER_HEIGHT)
	body.CanvasSize = UDim2.new()
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.ScrollingDirection = Enum.ScrollingDirection.Y
	body.ScrollBarThickness = 4
	body.Parent = frame
	local layout = list(body, Enum.FillDirection.Horizontal, Config.COLUMN_GAP)

	local tip, tipText = tooltip(gui)
	local panel: Panel =
		{ gui = gui, columns = columns, infos = {}, tip = tip, tipText = tipText, pinned = nil }
	local groups = Config.HELP.groups
	local heights = table.create(#groups)
	for _, group in groups do
		table.insert(heights, #group.rows + 1)
	end
	local values = Rules.formatted(Config.HELP.values)
	for index, members in Rules.columns(heights, columns) do
		local column = Instance.new("Frame")
		column.Name = `Column{index}`
		column.LayoutOrder = index
		column.BackgroundTransparency = 1
		column.AutomaticSize = Enum.AutomaticSize.Y
		column.Size = UDim2.fromOffset(width, 0)
		column.Parent = body
		list(column, Enum.FillDirection.Vertical, 2)
		captions(column)
		for _, member in members do
			local group = groups[member]
			local title = label(column, escape(group.title), BOLD, Config.GROUP_SIZE, Hud.YELLOW)
			title.Size = UDim2.new(1, 0, 0, Config.ROW_HEIGHT + 4)
			title.TextYAlignment = Enum.TextYAlignment.Bottom
			for _, entry in group.rows do
				row(panel, column, entry, bindings, values)
			end
		end
	end

	local function fit()
		local content = layout.AbsoluteContentSize.Y + Config.HEADER_HEIGHT + 2 * Config.PADDING
		local tallest = math.max(gui.AbsoluteSize.Y - 2 * Config.MARGIN, Config.HEADER_HEIGHT * 2)
		local wide = columns * width + (columns - 1) * Config.COLUMN_GAP + 2 * Config.PADDING
		frame.Size = UDim2.fromOffset(wide, math.min(content, tallest))
	end
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fit)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	gui.Parent = parent
	fit()
	return panel
end

function ControlsPanel.show(panel: Panel, selectFirst: boolean)
	hideTip(panel)
	panel.gui.Enabled = true
	if selectFirst then
		GuiService.SelectedObject = panel.infos[1]
	end
end

function ControlsPanel.hide(panel: Panel)
	hideTip(panel)
	panel.gui.Enabled = false
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(panel.gui) then
		GuiService.SelectedObject = nil
	end
end

return ControlsPanel
