--!strict
--[[
	A stall's round trip (Controllers/Driving, Services/CarEntry). The driving client tells the
	server that the model stalled while the engine ran; the server, the only writer of the engine
	state, turns the engine off; when the key start has the engine running again, the client
	restarts the model. A report the server never acts on is sent once more, then the client's engine
	runs again rather than stay dead under an engine the server shows running. A stalled car still
	rolls, steers and brakes: it is not parked as a car before its start is.
]]
export type Tracker = {
	-- When this stall was reported (seconds, any clock), whether it has been sent again, and whether
	-- the engine ran on the server's record last frame.
	reportedAt: number?,
	resent: boolean,
	engineWasOn: boolean,
}

-- Seconds after a report the server still shows the engine running: report again once, then run
-- the engine again, as the server says it does (Config/Driving).
export type Timing = { resendAfter: number, resumeAfter: number }

export type Action = "Report" | "Restart"

local Stall = {}

function Stall.newTracker(): Tracker
	return { reportedAt = nil, resent = false, engineWasOn = false }
end

-- What the client does this frame, at `now`, with the model `stalled` and the engine on or off on
-- the server's record: report a stall that happened while the engine ran, and once more if the
-- server has not stopped the engine by `resendAfter`; restart a stalled model as the engine starts,
-- or, still running on the server's record at `resumeAfter`, because it never stopped there.
function Stall.step(
	tracker: Tracker,
	stalled: boolean,
	engineOn: boolean,
	now: number,
	timing: Timing
): Action?
	local action: Action? = nil
	if stalled and engineOn then
		local reportedAt = tracker.reportedAt
		if not tracker.engineWasOn then
			action = "Restart"
		elseif reportedAt == nil then
			action = "Report"
			tracker.reportedAt, tracker.resent = now, false
		elseif now - reportedAt >= timing.resumeAfter then
			action = "Restart"
			tracker.reportedAt = nil
		elseif not tracker.resent and now - reportedAt >= timing.resendAfter then
			action = "Report"
			tracker.resent = true
		end
	elseif not stalled then
		tracker.reportedAt = nil
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
