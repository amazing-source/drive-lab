--!strict
--[[
	The driver's side of ABS, traction control and stability control: which of them run, the ESC
	control that switches them (held to switch ESC off, pressed to switch it back on), and what
	the tell-tales show. How hard each system intervenes is the drive mode's (Config/Cars, the
	`modes` thresholds); this decides only whether it runs.
]]
local Interface = require("../Vehicle/Interface")

export type EscButton = {
	-- Seconds the control is held to switch ESC off.
	holdSeconds: number,
	-- The systems that run with ESC switched off.
	off: Interface.Assists,
}

export type Tuning = {
	-- The systems that run, unless the drive mode or the ESC button says otherwise.
	on: Interface.Assists,
	-- Drive modes that set the systems themselves, as a manettino position switches TC off.
	modes: { [string]: Interface.Assists }?,
	-- A car without one has no control that switches ESC off.
	escButton: EscButton?,
	-- Flashes a second of the cluster's ESC light while ESC acts.
	lampFlashHz: number,
}

export type Switch = {
	off: boolean,
	-- When the control went down (s, any clock), while it is held.
	heldSince: number?,
	-- This hold has already switched ESC: nothing more happens until the control is released.
	spent: boolean,
}

-- A TC or ABS tell-tale.
export type Telltale = "Ready" | "Acting" | "Off"

-- What the cluster's ESC light shows.
export type Lamp = "Hidden" | "Esc" | "EscOff"

local DriverAssists = {}

function DriverAssists.newSwitch(): Switch
	return { off = false, heldSince = nil, spent = false }
end

-- Advances the control by whether it is held at `now`. Held for the button's `holdSeconds` it
-- switches ESC off; pressed while ESC is off it switches it on at once. Returns true on the frame
-- it switches.
function DriverAssists.updateSwitch(switch: Switch, held: boolean, now: number, button: EscButton): boolean
	if not held then
		switch.heldSince = nil
		switch.spent = false
		return false
	end
	if switch.spent then
		return false
	end
	local since = switch.heldSince
	if since == nil then
		switch.heldSince = now
		if switch.off then
			switch.off = false
			switch.spent = true
			return true
		end
		return false
	end
	if now - since >= button.holdSeconds then
		switch.off = true
		switch.spent = true
		return true
	end
	return false
end

-- With ESC switched off, the button's systems; otherwise the drive mode's, if it sets them.
function DriverAssists.assists(escOff: boolean, mode: string, tuning: Tuning): Interface.Assists
	local button = tuning.escButton
	if escOff and button then
		return button.off
	end
	local modes = tuning.modes
	return if modes and modes[mode] then modes[mode] else tuning.on
end

function DriverAssists.telltale(enabled: boolean, acting: boolean): Telltale
	if not enabled then
		return "Off"
	end
	return if acting then "Acting" else "Ready"
end

-- Steady while ESC is switched off; while it acts, flashing at `lampFlashHz`, lit the first half of
-- each period.
function DriverAssists.escLamp(escOff: boolean, acting: boolean, now: number, tuning: Tuning): Lamp
	if escOff then
		return "EscOff"
	end
	if acting and (now * tuning.lampFlashHz) % 1 < 0.5 then
		return "Esc"
	end
	return "Hidden"
end

return table.freeze(DriverAssists)
