--!strict
--[[
	The controls screen (Config/ControlsHelp): every control's keyboard key and gamepad input,
	grouped, each with an (i) whose sentence shows on hover, tap or gamepad selection. Its key or a
	tap of its pad button opens and closes it, a button does on touch screens, and a hint names the
	key for a few seconds after the first spawn and the first time the player is seated. Closed,
	its screen is disabled and nothing of it takes input; it never sinks a key.
]]
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CarEntry = require(ReplicatedStorage.Shared.Rules.CarEntry)
local CarRig = require(ReplicatedStorage.Shared.Car.CarRig)
local CarState = require(ReplicatedStorage.Shared.Car.CarState)
local Catalog = require(ReplicatedStorage.Shared.Config.Cars.Catalog)
local Config = require(ReplicatedStorage.Shared.Config.ControlsHelp)
local Controls = require(ReplicatedStorage.Shared.Config.Controls)
local Hud = require(ReplicatedStorage.Shared.Config.Hud)
local Log = require(ReplicatedStorage.Kit.Log)
local Movement = require(ReplicatedStorage.Shared.Config.Movement)
local Rules = require(ReplicatedStorage.Shared.Rules.ControlsHelp)

local ControlsPanel = require(script.Parent.Parent.Ui.ControlsPanel)

local SEAT_POLL_SECONDS = 0.2

local localPlayer = Players.LocalPlayer
local log = Log.scope("ControlsHelp")
local keyboardKeys: { Enum.KeyCode } = {}
local gamepadKeys: { Enum.KeyCode } = {}
local panel: ControlsPanel.Panel? = nil
local isOpen = false
local padPressedAt: number? = nil
local hintLabel: TextLabel? = nil
local touchButton: TextButton? = nil
local hintToken = 0
local hinted = { spawn = false, seat = false }

local function keyNames(keys: { Enum.KeyCode }): { string }
	local names = table.create(#keys)
	for _, key in keys do
		table.insert(names, key.Name)
	end
	return names
end

local function bindings(): Rules.Bindings
	local found: Rules.Bindings = { SPRINT = keyNames(Movement.SPRINT_KEYS) }
	-- Config/Controls is a typed record, read here as a map so that a new control is listed (and
	-- checked by Rules.problems) without a change to this file.
	for name, value in (Controls :: any) :: { [string]: unknown } do
		if typeof(value) == "table" then
			found[name] = keyNames(value :: { Enum.KeyCode })
		end
	end
	return found
end

local function shownKey(keys: { Enum.KeyCode }): string
	local first = keys[1]
	return if first then Config.HELP.keyNames[first.Name] or first.Name else Config.NO_INPUT
end

local function hintText(): string
	local preferred = UserInputService.PreferredInput
	if preferred == Enum.PreferredInput.Touch then
		return Rules.fill(Config.HINT.Touch, { KEY = Config.TOUCH_BUTTON })
	elseif preferred == Enum.PreferredInput.Gamepad then
		return Rules.fill(Config.HINT.Gamepad, { KEY = shownKey(gamepadKeys) })
	end
	return Rules.fill(Config.HINT.KeyboardAndMouse, { KEY = shownKey(keyboardKeys) })
end

local function fadeHint(label: TextLabel, shown: boolean)
	local info = TweenInfo.new(Config.FADE_SECONDS)
	local transparency = if shown then 0 else 1
	TweenService:Create(label, info, {
		TextTransparency = transparency,
		BackgroundTransparency = if shown then Config.PANEL_TRANSPARENCY else 1,
	}):Play()
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		TweenService:Create(stroke, info, { Transparency = transparency }):Play()
	end
end

local function hideHint()
	hintToken += 1
	local label = hintLabel
	if label and label.TextTransparency < 1 then
		fadeHint(label, false)
	end
end

local function showHint()
	local label = hintLabel
	if label == nil or isOpen then
		return
	end
	hintToken += 1
	local token = hintToken
	label.Text = hintText()
	fadeHint(label, true)
	task.delay(Config.HINT_SECONDS, function()
		if hintToken == token then
			hideHint()
		end
	end)
end

local function viewport(): Vector2
	local camera = Workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.zero
end

local function setOpen(value: boolean)
	if value == isOpen then
		return
	end
	isOpen = value
	if value then
		hideHint()
		local size = viewport()
		local current = panel
		if current == nil or ControlsPanel.columnsFor(size) ~= current.columns then
			if current then
				current.gui:Destroy()
			end
			current = ControlsPanel.build(localPlayer:WaitForChild("PlayerGui"), bindings(), size, {
				KEYBOARD = shownKey(keyboardKeys),
				GAMEPAD = shownKey(gamepadKeys),
			}, function()
				setOpen(false)
			end)
			panel = current
		end
		local built = current :: ControlsPanel.Panel
		ControlsPanel.show(built, UserInputService.PreferredInput == Enum.PreferredInput.Gamepad)
	elseif panel then
		ControlsPanel.hide(panel)
	end
end

local function onInputBegan(input: InputObject, processed: boolean)
	if GuiService.MenuIsOpen or UserInputService:GetFocusedTextBox() ~= nil then
		return
	end
	local key = input.KeyCode
	-- The pad button counts on release, as a tap, and even while the screen's own selection has
	-- it (B also clears a gamepad selection).
	if table.find(gamepadKeys, key) then
		padPressedAt = os.clock()
	elseif not processed and table.find(keyboardKeys, key) then
		setOpen(not isOpen)
	end
end

local function onInputEnded(input: InputObject)
	local since = padPressedAt
	if since == nil or not table.find(gamepadKeys, input.KeyCode) then
		return
	end
	padPressedAt = nil
	if not GuiService.MenuIsOpen and Rules.isTap(os.clock() - since, Config.TAP_SECONDS) then
		setOpen(not isOpen)
	end
end

local function buildHint(parent: Instance)
	local gui = Instance.new("ScreenGui")
	gui.Name = "ControlsHint"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local label = Instance.new("TextLabel")
	label.Name = "Hint"
	label.Active = false
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.fromScale(0.5, 0.14)
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.BackgroundColor3 = ControlsPanel.panelColor()
	label.BackgroundTransparency = 1
	label.TextTransparency = 1
	label.FontFace = ControlsPanel.BOLD
	label.TextSize = Config.GROUP_SIZE + 3
	label.TextColor3 = Hud.WHITE
	label.Parent = gui
	ControlsPanel.pad(label, Config.PADDING, Config.PADDING / 2)
	ControlsPanel.round(label, 8, Hud.YELLOW).Transparency = 1

	local button = Instance.new("TextButton")
	button.Name = "Open"
	button.Selectable = false
	button.AnchorPoint = Vector2.new(1, 0)
	button.Position = UDim2.new(1, -Config.MARGIN, 0, Config.MARGIN)
	button.Size = UDim2.fromOffset(Config.TOUCH_SIZE, Config.TOUCH_SIZE)
	button.BackgroundColor3 = ControlsPanel.panelColor()
	button.BackgroundTransparency = Config.PANEL_TRANSPARENCY
	button.FontFace = ControlsPanel.BOLD
	button.TextSize = Config.TITLE_SIZE
	button.TextColor3 = Hud.WHITE
	button.Text = Config.TOUCH_BUTTON
	button.Visible = false
	button.Parent = gui
	ControlsPanel.round(button, Config.TOUCH_SIZE / 2, Hud.LINE_GREY)
	button.Activated:Connect(function()
		setOpen(not isOpen)
	end)

	gui.Parent = parent
	hintLabel, touchButton = label, button
end

local function showTouchButton()
	local button = touchButton
	if button then
		button.Visible = UserInputService.PreferredInput == Enum.PreferredInput.Touch
	end
end

local function drivenCar(): Model?
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	local model = seat and seat.Parent
	return if model and model:IsA("Model") and model:HasTag(CarRig.TAG) then model else nil
end

-- The first time the player is seated, once the entry has played (Rules/CarEntry).
local function watchSeat(humanoid: Humanoid)
	humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
		if hinted.seat or drivenCar() == nil then
			return
		end
		hinted.seat = true
		task.spawn(function()
			while true do
				local car = drivenCar()
				local entry = car and Catalog.of(car)
				if car == nil or entry == nil then
					hinted.seat = false
					return
				elseif
					CarEntry.phase(entry, CarState.read(car), Workspace:GetServerTimeNow()) == "Seated"
				then
					showHint()
					return
				end
				task.wait(SEAT_POLL_SECONDS)
			end
		end)
	end)
end

local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	if character.Parent == nil then
		return
	end
	watchSeat(humanoid)
	if not hinted.spawn then
		hinted.spawn = true
		task.delay(Config.HINT_DELAY, showHint)
	end
end

local Controller = {}

function Controller.start()
	for _, key in Controls.CONTROLS_HELP do
		table.insert(if Rules.isGamepadKey(key.Name) then gamepadKeys else keyboardKeys, key)
	end
	for _, problem in Rules.problems(Config.HELP, bindings()) do
		log.warn(problem)
	end
	buildHint(localPlayer:WaitForChild("PlayerGui"))
	showTouchButton()
	UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(showTouchButton)
	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputEnded:Connect(onInputEnded)
	if localPlayer.Character then
		task.spawn(onCharacter, localPlayer.Character)
	end
	localPlayer.CharacterAdded:Connect(onCharacter)
end

return Controller
