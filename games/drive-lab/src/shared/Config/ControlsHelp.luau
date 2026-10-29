--!strict
--[[
	The controls screen (Controllers/ControlsHelp, Rules/ControlsHelp): every control in
	Config/Controls, grouped, with a label and one plain sentence for a player who has never
	driven a supercar. A row names the Config/Controls entries it explains and shows their keys
	from there, so a rebound key shows up here by itself; tests/ControlsHelp.spec.luau fails if a
	control has no row, label or sentence. Inputs bound elsewhere are declared on their row, with
	where they are bound: Roblox's defaults (walk, jump, the camera on foot, the prompts' E and X),
	the door prompt (Services/CarEntry: F, Y), the pedals and steering on a pad (Controllers/
	Driving: RT, LT, the left stick), the look-around and seat (Controllers/CarCamera). SPRINT is
	Config/Movement.SPRINT_KEYS, which the controller adds to the bindings.
]]
local CarEntry = require("./CarEntry")
local CarLights = require("./CarLights")
local DriverAssists = require("./DriverAssists")
local InputHelp = require("./InputHelp")
local Rules = require("../Rules/ControlsHelp")

export type ControlsHelpConfig = {
	HELP: Rules.Help,
	-- Seconds a gamepad press may last to count as the controls button's tap: under
	-- CarEntry.EXIT_HOLD_SECONDS, so B's tap opens the screen and its hold still gets out.
	TAP_SECONDS: number,
	-- The hint: how long after a spawn it waits, how long it stays.
	HINT_DELAY: number,
	HINT_SECONDS: number,
	-- {KEY} is the first key of CONTROLS_HELP for the player's device, or the touch button.
	HINT: { KeyboardAndMouse: string, Gamepad: string, Touch: string },
	TITLE: string,
	-- {KEYBOARD} and {GAMEPAD} as in the hint.
	SUBTITLE: string,
	KEYBOARD_CAPTION: string,
	GAMEPAD_CAPTION: string,
	NO_INPUT: string,
	TOUCH_BUTTON: string,
	-- Pixels.
	COLUMN_WIDTH: number,
	COLUMN_GAP: number,
	MAX_COLUMNS: number,
	MARGIN: number,
	PADDING: number,
	ROW_HEIGHT: number,
	TEXT_SIZE: number,
	TITLE_SIZE: number,
	GROUP_SIZE: number,
	HEADER_HEIGHT: number,
	-- Each row's label, keyboard and gamepad, as shares of the column; the (i) takes the rest.
	SHARES: { label: number, keyboard: number, gamepad: number },
	TOOLTIP_WIDTH: number,
	INFO_SIZE: number,
	TOUCH_SIZE: number,
	-- 0-255, with the HUD's palette (Config/Hud) for the text.
	PANEL_RGB: { number },
	PANEL_TRANSPARENCY: number,
	FADE_SECONDS: number,
}

local HELP: Rules.Help = {
	groups = {
		{
			title = "On foot",
			rows = {
				{
					label = "Walk",
					text = "Walks your character; forward is wherever the camera faces.",
					controls = {},
					keyboard = { "W A S D" },
					gamepad = { "Thumbstick1" },
				},
				{
					label = "Run",
					text = "Runs instead of walking: hold Shift, or click the left stick to switch running on and off.",
					controls = { "SPRINT" },
					keyboardGesture = "Hold",
					gamepadGesture = "Click",
				},
				{
					label = "Jump",
					text = "Jumps; in the car the same Space key is the handbrake.",
					controls = {},
					keyboard = { "Space" },
					gamepad = { "ButtonA" },
				},
				{
					label = "Turn the camera",
					text = "Hold the right mouse button and move the mouse to turn the camera round you; the mouse wheel zooms in and out.",
					controls = {},
					keyboard = { "Right mouse button", "Mouse wheel" },
					gamepad = { "Thumbstick2" },
				},
			},
		},
		{
			title = "Getting in and out",
			rows = {
				{
					label = "Get in (at the door)",
					text = "At the driver's door, walks you to it and plays the whole way in: the door up, over the wide sill, into the seat and the door pulled shut.",
					controls = {},
					keyboard = { "E" },
					gamepad = { "ButtonX" },
				},
				{
					label = "Door, from outside",
					text = "Opens or closes the driver's door from outside; the SVJ's scissor doors swing up, not out.",
					controls = {},
					keyboard = { "F" },
					gamepad = { "ButtonY" },
				},
				{
					label = "Door, seated",
					text = "Below {DOOR_KMH} km/h, swings the door up or pulls it back down by the strap sewn inside it; the car only drives with the door shut.",
					controls = { "DOOR" },
				},
				{
					label = "Start the engine",
					text = "The SVJ has no key: seated with the door shut, the driver puts a foot on the brake, flips up the red cover and presses the START button under it, and the V12 fires.",
					controls = { "START_ENGINE" },
				},
				{
					label = "Get out",
					text = "Hold {EXIT_HOLD} s below {EXIT_KMH} km/h to open the door and climb out; a quick tap of E is the upshift paddle instead.",
					controls = { "EXIT" },
					keyboardGesture = "Hold",
					gamepadGesture = "Hold",
				},
			},
		},
		{
			title = "Driving",
			rows = {
				{
					label = "Accelerate",
					text = "The accelerator pedal; a gamepad's RT can be pressed part of the way for less power.",
					controls = { "THROTTLE" },
					gamepad = { "ButtonR2" },
				},
				{
					label = "Brake",
					text = "The brake pedal; ABS stops the wheels locking even when you brake as hard as you can.",
					controls = { "BRAKE" },
					gamepad = { "ButtonL2" },
				},
				{
					label = "Steer",
					text = "Turns the front wheels; the SVJ steers its rear wheels a little too, against the fronts when slow for tight turns and with them at speed for stability.",
					controls = { "LEFT", "RIGHT" },
					gamepad = { "Thumbstick1" },
				},
				{
					label = "Handbrake",
					text = "Locks the rear wheels, to hold the car still or to swing the tail round a tight bend.",
					controls = { "HANDBRAKE" },
				},
			},
		},
		{
			title = "Gearbox and drive modes",
			rows = {
				{
					label = "Shift up (right paddle)",
					text = "The right paddle behind the steering wheel: one gear up of seven; in automatic the gearbox also shifts by itself.",
					controls = { "SHIFT_UP" },
				},
				{
					label = "Shift down (left paddle)",
					text = "The left paddle: one gear down unless that would over-rev the engine; at a standstill it selects neutral, then reverse, and the right paddle comes back to first.",
					controls = { "SHIFT_DOWN" },
				},
				{
					label = "Reverse (automatic)",
					text = "In automatic, hold the brake {REVERSE_HOLD} s at a standstill to select reverse (R on the display), where the brake drives backwards and the accelerator brakes; hold the accelerator at a standstill to go back to drive.",
					controls = {},
					keysOf = { "BRAKE" },
					gamepad = { "ButtonL2" },
					keyboardGesture = "Hold",
					gamepadGesture = "Hold",
				},
				{
					label = "Automatic / manual",
					text = "Switches between the automatic gearbox (A on the display) and manual (M), where you change gear with the paddles.",
					controls = { "GEARBOX_MODE" },
				},
				{
					label = "Strada / Sport / Corsa",
					text = "Steps through the drive modes: Strada for the road (smooth shifts, soft suspension, assists that step in early), Sport (quicker shifts, power mostly to the rear, assists that let the tail slide) and Corsa for the track (the fastest shifts, the firmest suspension, kept on its line).",
					controls = { "DRIVING_MODE" },
				},
			},
		},
		{
			title = "Assists",
			rows = {
				{
					label = "ESC and TC off / on",
					text = "Hold {ESC_HOLD} s to switch off stability control (ESC) and traction control (TC), so the wheels may spin and the tail slide; ABS stays on, a press switches them back on, and every new drive starts with them on.",
					controls = { "ESC_OFF" },
					keyboardGesture = "Hold",
					gamepadGesture = "Hold",
				},
			},
		},
		{
			title = "Lights",
			rows = {
				{
					label = "Headlights",
					text = "Switches the headlights between automatic (on at night and in heavy rain), always on, and off.",
					controls = { "HEADLIGHTS" },
				},
				{
					label = "High beam",
					text = "Turns the full-beam headlights on or off for seeing further down the road; they only shine while the headlights are on.",
					controls = { "HIGH_BEAM" },
				},
				{
					label = "Cabin light",
					text = "Turns the light in the roof above the windscreen on or off so you can see inside the car at night.",
					controls = { "CABIN_LIGHT" },
				},
				{
					label = "Lights, on a gamepad",
					text = "Tap to step the headlights through automatic, on, full beam and off; hold for {PAD_HOLD} s to switch the cabin light.",
					controls = { "LIGHTS_PAD" },
					gamepadGesture = "Tap or hold",
				},
				{
					label = "Indicators, left / right",
					text = "Flashes the indicator on that side to show you are turning; press again to stop it.",
					controls = { "INDICATOR_LEFT", "INDICATOR_RIGHT" },
				},
			},
		},
		{
			title = "Cameras and view",
			rows = {
				{
					label = "Camera view",
					text = "Steps through the car's cameras: behind the car (chase), the driver's eyes (cockpit) and the bonnet (hood).",
					controls = { "CAMERA_VIEW" },
				},
				{
					label = "Look around",
					text = "In the car, hold the right mouse button and move the mouse to look out of the side windows; let go and the view comes back to the front.",
					controls = {},
					keyboard = { "Right mouse button" },
					gamepad = { "Thumbstick2" },
					keyboardGesture = "Hold",
				},
				{
					label = "Cockpit seat",
					text = "In the cockpit view, the mouse wheel slides your seat forward or back and Shift with the wheel raises or lowers it.",
					controls = {},
					keyboard = { "Mouse wheel", "Shift + mouse wheel" },
				},
			},
		},
		{
			title = "Weather",
			rows = {
				{
					label = "Weather",
					text = "Steps the weather through a clear day, rain by day and rain at night; the change takes a few seconds and the road soaks or dries slowly, as a real one does.",
					controls = { "WEATHER" },
				},
			},
		},
		{
			title = "HUD",
			rows = {
				{
					label = "Driving display",
					text = "Steps the driving display through full, minimal (smaller) and off.",
					controls = { "HUD_MODE" },
				},
				{
					label = "This screen",
					text = "Opens or closes this list of controls; on a touch screen, the question-mark button at the top right does the same.",
					controls = { "CONTROLS_HELP" },
					gamepadGesture = "Tap",
				},
			},
		},
	},
	keyNames = {
		LeftShift = "Shift",
		Space = "Space",
		Up = "Up arrow",
		Down = "Down arrow",
		Left = "Left arrow",
		Right = "Right arrow",
		ButtonA = "A",
		ButtonB = "B",
		ButtonX = "X",
		ButtonY = "Y",
		ButtonL1 = "LB",
		ButtonR1 = "RB",
		ButtonL2 = "LT",
		ButtonR2 = "RT",
		ButtonL3 = "L3",
		ButtonR3 = "R3",
		ButtonSelect = "View",
		ButtonStart = "Menu",
		DPadUp = "D-pad up",
		DPadDown = "D-pad down",
		DPadLeft = "D-pad left",
		DPadRight = "D-pad right",
		Thumbstick1 = "Left stick",
		Thumbstick2 = "Right stick",
	},
	values = {
		EXIT_HOLD = CarEntry.EXIT_HOLD_SECONDS,
		EXIT_KMH = CarEntry.EXIT_MAX_KMH,
		DOOR_KMH = CarEntry.DOOR_MAX_KMH,
		ESC_HOLD = DriverAssists.offHoldSeconds,
		PAD_HOLD = CarLights.PAD_HOLD_SECONDS,
		REVERSE_HOLD = InputHelp.REVERSE_HOLD_SECONDS,
	},
	maxLabelLength = 26,
	maxTextLength = 300,
}

local Config: ControlsHelpConfig = table.freeze({
	HELP = HELP,
	TAP_SECONDS = 0.25,
	HINT_DELAY = 1.5,
	HINT_SECONDS = 6,
	HINT = table.freeze({
		KeyboardAndMouse = "Press {KEY} for controls",
		Gamepad = "Tap {KEY} for controls",
		Touch = "Tap {KEY} for controls",
	}),
	TITLE = "Controls",
	SUBTITLE = "Hover or tap (i) to see what a control does.  {KEYBOARD} or a tap of {GAMEPAD} closes this screen.",
	KEYBOARD_CAPTION = "Keyboard",
	GAMEPAD_CAPTION = "Gamepad",
	NO_INPUT = "-",
	TOUCH_BUTTON = "?",
	COLUMN_WIDTH = 400,
	COLUMN_GAP = 20,
	MAX_COLUMNS = 3,
	MARGIN = 16,
	PADDING = 16,
	ROW_HEIGHT = 22,
	TEXT_SIZE = 14,
	TITLE_SIZE = 24,
	GROUP_SIZE = 15,
	HEADER_HEIGHT = 50,
	SHARES = table.freeze({ label = 0.37, keyboard = 0.29, gamepad = 0.27 }),
	TOOLTIP_WIDTH = 300,
	INFO_SIZE = 18,
	TOUCH_SIZE = 40,
	PANEL_RGB = { 14, 15, 18 },
	PANEL_TRANSPARENCY = 0.08,
	FADE_SECONDS = 0.3,
})

return Config
