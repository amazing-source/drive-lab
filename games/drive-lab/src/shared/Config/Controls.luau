--!strict
export type Controls = {
	THROTTLE: { Enum.KeyCode },
	BRAKE: { Enum.KeyCode },
	LEFT: { Enum.KeyCode },
	RIGHT: { Enum.KeyCode },
	HANDBRAKE: { Enum.KeyCode },
	SHIFT_UP: { Enum.KeyCode },
	SHIFT_DOWN: { Enum.KeyCode },
	GEARBOX_MODE: { Enum.KeyCode },
	DRIVING_MODE: { Enum.KeyCode },
	ESC_OFF: { Enum.KeyCode },
	CAMERA_VIEW: { Enum.KeyCode },
	HEADLIGHTS: { Enum.KeyCode },
	HIGH_BEAM: { Enum.KeyCode },
	CABIN_LIGHT: { Enum.KeyCode },
	LIGHTS_PAD: { Enum.KeyCode },
	INDICATOR_LEFT: { Enum.KeyCode },
	INDICATOR_RIGHT: { Enum.KeyCode },
	-- On a car that has them (Config/CarSwitches): the pit limiter, the display's pages, the wiper,
	-- its washer (held) and the rain light.
	PIT_LIMITER: { Enum.KeyCode },
	DISPLAY_PAGE: { Enum.KeyCode },
	WIPER: { Enum.KeyCode },
	WASHER: { Enum.KeyCode },
	RAIN_LIGHT: { Enum.KeyCode },
	HUD_MODE: { Enum.KeyCode },
	-- Seated: open or shut the driver's door, start the engine, and (held) get out.
	DOOR: { Enum.KeyCode },
	START_ENGINE: { Enum.KeyCode },
	EXIT: { Enum.KeyCode },
	-- Opens and closes the controls screen (Config/ControlsHelp).
	CONTROLS_HELP: { Enum.KeyCode },
	-- Steps the weather (Config/Atmosphere.WEATHER_KEY).
	WEATHER: { Enum.KeyCode },
	-- Analog sticks below this count as centred.
	STICK_DEADZONE: number,
}

-- KeyCodes name a key by where it sits on a US QWERTY keyboard, whatever the player's layout; the
-- controls screen shows each key as the player's own keyboard prints it. The keys added for the
-- DR458 were chosen by the owner on an AZERTY keyboard (2026-10-30, #96).
local Controls: Controls = table.freeze({
	THROTTLE = { Enum.KeyCode.W, Enum.KeyCode.Up },
	BRAKE = { Enum.KeyCode.S, Enum.KeyCode.Down },
	LEFT = { Enum.KeyCode.A, Enum.KeyCode.Left },
	RIGHT = { Enum.KeyCode.D, Enum.KeyCode.Right },
	HANDBRAKE = { Enum.KeyCode.Space, Enum.KeyCode.ButtonX },
	SHIFT_UP = { Enum.KeyCode.E, Enum.KeyCode.ButtonR1 },
	SHIFT_DOWN = { Enum.KeyCode.Q, Enum.KeyCode.ButtonL1 },
	GEARBOX_MODE = { Enum.KeyCode.T, Enum.KeyCode.ButtonY },
	-- M on QWERTY, and the key AZERTY prints M (QWERTY's semicolon), so the key marked M works on
	-- both.
	DRIVING_MODE = { Enum.KeyCode.M, Enum.KeyCode.Semicolon, Enum.KeyCode.DPadUp },
	-- Held to switch ESC (and traction control) off, pressed to switch it back on. G sits in the
	-- same place on QWERTY and AZERTY; View is the one gamepad button free while driving.
	ESC_OFF = { Enum.KeyCode.G, Enum.KeyCode.ButtonSelect },
	CAMERA_VIEW = { Enum.KeyCode.V, Enum.KeyCode.ButtonR3 },
	-- H, J, X, C and L sit in the same place on QWERTY and AZERTY; J, the high beam, is next to H.
	-- The pad has no button left while driving: D-pad down steps the headlights Auto, On, high
	-- beam, Off on a tap and switches the cabin light on a hold (Config/CarLights.PAD_HOLD_SECONDS).
	HEADLIGHTS = { Enum.KeyCode.H },
	HIGH_BEAM = { Enum.KeyCode.J },
	CABIN_LIGHT = { Enum.KeyCode.L },
	LIGHTS_PAD = { Enum.KeyCode.DPadDown },
	INDICATOR_LEFT = { Enum.KeyCode.X, Enum.KeyCode.DPadLeft },
	INDICATOR_RIGHT = { Enum.KeyCode.C, Enum.KeyCode.DPadRight },
	-- P, Y, O and B sit in the same place on QWERTY and AZERTY; One is the key AZERTY prints 1
	-- (with &). Z is not free: AZERTY's Z is the throttle, W.
	PIT_LIMITER = { Enum.KeyCode.P },
	DISPLAY_PAGE = { Enum.KeyCode.Y },
	WIPER = { Enum.KeyCode.O },
	WASHER = { Enum.KeyCode.B },
	RAIN_LIGHT = { Enum.KeyCode.One },
	-- The driving HUD: full, minimal, off.
	HUD_MODE = { Enum.KeyCode.U },
	-- F and R sit in the same place on QWERTY and AZERTY. E is also the upshift paddle: a tap
	-- shifts, holding it (CarEntry.EXIT_HOLD_SECONDS, near a standstill) gets out. L3 is the
	-- sprint on foot, free while seated.
	DOOR = { Enum.KeyCode.F, Enum.KeyCode.ButtonL3 },
	START_ENGINE = { Enum.KeyCode.R, Enum.KeyCode.ButtonA },
	EXIT = { Enum.KeyCode.E, Enum.KeyCode.ButtonB },
	-- K sits in the same place on QWERTY and AZERTY and is bound to nothing else. The pad has no
	-- button left, so a tap of B opens it (ControlsHelp.TAP_SECONDS) and B's hold stays the exit.
	CONTROLS_HELP = { Enum.KeyCode.K, Enum.KeyCode.ButtonB },
	-- N sits in the same place on QWERTY and AZERTY and is bound to nothing else.
	WEATHER = { Enum.KeyCode.N },
	STICK_DEADZONE = 0.12,
})

return Controls
