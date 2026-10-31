--!strict
--[[
	The instant the driver works a cockpit control, on this client: the hand gestures fire the
	control they reach (Rig/WheelGestures), the lights the headlight switch at its key; the
	listeners (Controllers/ControlSounds) hear the car and the control's name. Nothing is kept.
]]
export type Listener = (model: Model, name: string) -> ()

local listeners: { Listener } = {}

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
function ControlPresses.fire(model: Model, name: string)
	for _, listener in listeners do
		task.spawn(listener, model, name)
	end
end

return ControlPresses
