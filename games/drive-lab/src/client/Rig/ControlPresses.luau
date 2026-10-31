--!strict
--[[
	The instant the driver works a cockpit control, on this client. The hand gestures
	(Rig/WheelGestures) claim the controls they play on the driven car: a claimed control's press
	takes effect when the gesture fires it (the thumb on the button, the knob or toggle turned, or at
	once when the hand cannot take it), with how many presses that settles, and a claimed held control
	(the washer, the flasher) acts while the hand holds its button. A control nothing claims takes
	effect at its key, as each controller already does; the lights still fire the headlight switch
	and the indicators there, for their sounds (Controllers/ControlSounds).
]]
export type Listener = (model: Model, name: string, presses: number) -> ()

local listeners: { Listener } = {}
local claims: { [Model]: { [string]: true } } = {}
local held: { [Model]: { [string]: true } } = {}

local ControlPresses = {}

-- Adds a listener; the function returned removes it.
function ControlPresses.connect(listener: Listener): () -> ()
	table.insert(listeners, listener)
	return function()
		local index = table.find(listeners, listener)
		if index then
			table.remove(listeners, index)
		end
	end
end

-- Each listener runs in its own thread, so one that errors cannot stop the others or the caller.
-- `presses` defaults to one.
function ControlPresses.fire(model: Model, name: string, presses: number?)
	for _, listener in listeners do
		task.spawn(listener, model, name, presses or 1)
	end
end

-- The gestures on `model` play these controls; the function returned gives them back.
function ControlPresses.claim(model: Model, controls: { string }): () -> ()
	local claimed: { [string]: true } = {}
	for _, control in controls do
		claimed[control] = true
	end
	claims[model] = claimed
	return function()
		if claims[model] == claimed then
			claims[model] = nil
			held[model] = nil
		end
	end
end

-- Whether a press of `control` on `model` waits for its gesture rather than acting at its key.
function ControlPresses.claimed(model: Model, control: string): boolean
	local claimed = claims[model]
	return claimed ~= nil and claimed[control] == true
end

-- The claimed buttons the hand holds down on `model` this instant.
function ControlPresses.hold(model: Model, controls: { [string]: true })
	if claims[model] then
		held[model] = controls
	end
end

function ControlPresses.holding(model: Model, control: string): boolean
	local controls = held[model]
	return controls ~= nil and controls[control] == true
end

return ControlPresses
