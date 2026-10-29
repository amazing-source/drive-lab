--!strict
local Sprint = {}

-- Whether a pressed key flips the gamepad's sprint toggle (`toggle`, Config/Movement.SPRINT_KEYS):
-- on foot only, since seated the same stick click is the door (Config/Controls.DOOR).
function Sprint.toggles(key: Enum.KeyCode, toggle: Enum.KeyCode, processed: boolean, seated: boolean): boolean
	return key == toggle and not processed and not seated
end

return table.freeze(Sprint)
