--!strict
--[[
	A stall's round trip (Controllers/Driving, Services/CarEntry). The driving client tells the
	server once that the model stalled while the engine ran; the server, the only writer of the
	engine state, turns the engine off; when the key start has the engine running again, the client
	restarts the model. A stalled car still rolls, steers and brakes: it is not parked as a car
	before its start is.
]]
export type Tracker = {
	-- This stall has been reported, and the engine ran on the server's record last frame.
	reported: boolean,
	engineWasOn: boolean,
}

export type Action = "Report" | "Restart"

local Stall = {}

function Stall.newTracker(): Tracker
	return { reported = false, engineWasOn = false }
end

-- What the client does this frame with the model `stalled` and the engine on or off on the
-- server's record: report a stall that happened while the engine ran, once; restart a stalled model
-- as the engine starts.
function Stall.step(tracker: Tracker, stalled: boolean, engineOn: boolean): Action?
	local action: Action? = nil
	if stalled and engineOn then
		if not tracker.engineWasOn then
			action = "Restart"
		elseif not tracker.reported then
			action = "Report"
			tracker.reported = true
		end
	elseif not stalled then
		tracker.reported = false
	end
	tracker.engineWasOn = engineOn
	return action
end

-- Whether the driver's input reaches the car: once it is drivable (Rules/CarEntry), and while it
-- rolls stalled.
function Stall.drives(drivable: boolean, stalled: boolean): boolean
	return drivable or stalled
end

return table.freeze(Stall)
