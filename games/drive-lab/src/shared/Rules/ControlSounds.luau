--!strict
--[[
	When the cockpit controls' sounds play (Controllers/ControlSounds, Config/CarAudio.ControlSounds),
	in plain numbers so Lune can test it: their level against the engine's idle, the start-up's
	presses as its server-timed timeline passes them, the radio's opening and closing, and the
	wiper motor's speed.
]]
local CarAudio = require("../Config/CarAudio")
local CarEntry = require("../Config/CarEntry")

export type Edge = "Press" | "Release"

-- How one car's start-up is being watched: the start it follows (its engineAt, server time), how
-- far into it the last frame was, and whether the next start is seen from its beginning (the car
-- was seen with its engine off, or through an earlier start).
export type Watch = { engineAt: number?, at: number?, fromStart: boolean }

local ControlSounds = {}

-- A control sound's linear volume: `db` against the idle loop's level at idle.
function ControlSounds.volume(idleLevel: number, sound: CarAudio.ControlSound): number
	return idleLevel * 10 ^ (sound.db / 20)
end

-- What the start-up presses between `from` (exclusive) and `to` (inclusive), seconds after its
-- start key: each move's control as the hand reaches it, and ENGINE_START at the press. `from`
-- is nil the first time a start-up is seen part-way through (a late join, a car streaming in),
-- which presses nothing: only what happens while it is watched plays.
function ControlSounds.startupPresses(startup: CarEntry.Startup, from: number?, to: number): { string }
	local pressed: { string } = {}
	if from == nil or to <= from then
		return pressed
	end
	for _, move in startup.moves do
		if move.at > from and move.at <= to then
			table.insert(pressed, move.control)
		end
	end
	if startup.pressAt > from and startup.pressAt <= to then
		table.insert(pressed, "ENGINE_START")
	end
	return pressed
end

-- A car first seen now: whatever its start-up has already passed presses nothing.
function ControlSounds.newWatch(): Watch
	return { engineAt = nil, at = nil, fromStart = false }
end

-- This frame's start-up presses for a watched car, its engine `running` since `engineAt`, at
-- `now` (server time); moves the watch on.
function ControlSounds.watchStartup(
	watch: Watch,
	startup: CarEntry.Startup,
	running: boolean,
	engineAt: number,
	now: number
): { string }
	if not running then
		watch.engineAt, watch.at, watch.fromStart = nil, nil, true
		return {}
	end
	local at = now - engineAt
	local from = watch.at
	if watch.engineAt ~= engineAt then
		from = if watch.fromStart or watch.engineAt ~= nil then -math.huge else nil
		watch.engineAt = engineAt
	end
	watch.at = at
	return ControlSounds.startupPresses(startup, from, at)
end

-- The push-to-talk's edge between two frames, if any.
function ControlSounds.radioEdge(was: boolean, talking: boolean): Edge?
	if talking == was then
		return nil
	end
	return if talking then "Press" else "Release"
end

-- The wiper motor's playback speed while the blade moves or the switch is on, nil when it is
-- still: its first speed step's while it runs off the switch (the washer, or a last wipe), and
-- the last listed for a step past the list.
function ControlSounds.wiperRate(rates: { number }, speed: number, sweep: number): number?
	if speed <= 0 and sweep <= 0 then
		return nil
	end
	return rates[math.clamp(speed, 1, #rates)]
end

return table.freeze(ControlSounds)
