--!strict
--[[
	Runs a function so its failure or its yield cannot hold up the caller: services
	starting in sequence, cleanups on a leaving player's plot, UI widgets mounting. The
	function runs in its own thread straight away; the outcome says whether it finished,
	failed (with the error and its traceback, since an error caught here is not printed by
	the engine), or yielded and is still running on its own.
]]
export type Outcome = "finished" | "failed" | "yielded"

local Isolate = {}

function Isolate.run(fn: (...any) -> ...any, ...: any): (Outcome, string?)
	local thread = coroutine.create(fn)
	local ok, problem = coroutine.resume(thread, ...)
	if not ok then
		return "failed", debug.traceback(thread, tostring(problem))
	end
	if coroutine.status(thread) ~= "dead" then
		return "yielded", nil
	end
	return "finished", nil
end

return Isolate
