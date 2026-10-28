--!strict
--[[
	The driver's side of ABS, traction control and stability control: which of them run, the ESC
	control that switches them (held to switch ESC off, pressed to switch it back on), and what
	the tell-tales show. How hard each system intervenes is the drive mode's (Config/Cars, the
	`modes` thresholds); this decides only whether it runs.
]]
local Interface = require("../Vehicle/Interface")

export type Tuning = {
	-- Seconds the control is held to switch ESC off.
	offHoldSeconds: number,
	-- The systems that run with ESC on, and with ESC switched off.
	on: Interface.Assists,
	off: Interface.Assists,
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

-- Advances the control by whether it is held at `now`. Held for `offHoldSeconds` it switches ESC
-- off; pressed while ESC is off it switches it on at once. Returns true on the frame it switches.
function DriverAssists.updateSwitch(switch: Switch, held: boolean, now: number, tuning: Tuning): boolean
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
	if now - since >= tuning.offHoldSeconds then
		switch.off = true
		switch.spent = true
		return true
	end
	return false
end

function DriverAssists.assists(escOff: boolean, tuning: Tuning): Interface.Assists
	return if escOff then tuning.off else tuning.on
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
