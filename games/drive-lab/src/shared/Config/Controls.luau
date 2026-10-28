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
	INDICATOR_LEFT: { Enum.KeyCode },
	INDICATOR_RIGHT: { Enum.KeyCode },
	HUD_MODE: { Enum.KeyCode },
	-- Analog sticks below this count as centred.
	STICK_DEADZONE: number,
}

local Controls: Controls = table.freeze({
	THROTTLE = { Enum.KeyCode.W, Enum.KeyCode.Up },
	BRAKE = { Enum.KeyCode.S, Enum.KeyCode.Down },
	LEFT = { Enum.KeyCode.A, Enum.KeyCode.Left },
	RIGHT = { Enum.KeyCode.D, Enum.KeyCode.Right },
	HANDBRAKE = { Enum.KeyCode.Space, Enum.KeyCode.ButtonX },
	SHIFT_UP = { Enum.KeyCode.E, Enum.KeyCode.ButtonR1 },
	SHIFT_DOWN = { Enum.KeyCode.Q, Enum.KeyCode.ButtonL1 },
	GEARBOX_MODE = { Enum.KeyCode.T, Enum.KeyCode.ButtonY },
	DRIVING_MODE = { Enum.KeyCode.M, Enum.KeyCode.DPadUp },
	-- Held to switch ESC (and traction control) off, pressed to switch it back on. G sits in the
	-- same place on QWERTY and AZERTY; View is the one gamepad button free while driving.
	ESC_OFF = { Enum.KeyCode.G, Enum.KeyCode.ButtonSelect },
	CAMERA_VIEW = { Enum.KeyCode.V, Enum.KeyCode.ButtonR3 },
	-- H, X and C sit in the same place on QWERTY and AZERTY.
	HEADLIGHTS = { Enum.KeyCode.H, Enum.KeyCode.DPadDown },
	INDICATOR_LEFT = { Enum.KeyCode.X, Enum.KeyCode.DPadLeft },
	INDICATOR_RIGHT = { Enum.KeyCode.C, Enum.KeyCode.DPadRight },
	-- The driving HUD: full, minimal, off.
	HUD_MODE = { Enum.KeyCode.U },
	STICK_DEADZONE = 0.12,
})

return Controls
