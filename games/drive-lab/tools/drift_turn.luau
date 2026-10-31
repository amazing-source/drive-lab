--!strict
--[[
	How sharply Space turns each car and how its drift ends, on tools/DriveSim, driven on the keys
	(tools/DriftTurn): a held drift at 60, 80 and 120 km/h with the throttle off and on, a tap of
	Space into a steered corner, and a drift ended by braking or below the speed gate.

	    lune run games/drive-lab/tools/drift_turn.luau [fps]
]]
local DR458 = require("../src/shared/Config/Cars/DR458/Physics")
local DriftTurn = require("./DriftTurn")
local SVJ = require("../src/shared/Config/Cars/SVJ/Physics")
local Types = require("../src/shared/Config/Cars/Types")
local process = require("@lune/process")

local FPS = tonumber(process.args[1]) or 60
local CARS: { { label: string, car: Types.CarConfig } } = {
	{ label = "SVJ", car = SVJ },
	{ label = "DR458", car = DR458 },
}

local function metres(value: number): string
	return if value == math.huge then "never" else ("%.0f m"):format(value)
end

local function deg(value: number): string
	return ("%.0f"):format(math.deg(value))
end

print(`Drift on DriveSim at {FPS} FPS, keyboard help, Space and the right key, first mode`)
print("")
print("Held drift: Space and the key held until the travel has turned 90 deg (or 4 s), then released.")
print(
	"car | km/h | throttle | 90 deg heading at | 90 deg travel at | heading / travel in 30 m | held s | slip at release | heading moves in 2 s after | slip after | km/h after"
)
for _, entry in CARS do
	for _, kmh in { 60, 80, 120 } do
		for _, throttle in { 0, 1 } do
			local t = DriftTurn.turn(entry.car, kmh, throttle, FPS)
			print(
				("%s | %d | %d | %s | %s | %s / %s | %.2f | %s | %s | %s | %.0f"):format(
					entry.label,
					kmh,
					throttle,
					metres(t.headingAt90),
					metres(t.travelAt90),
					deg(t.heading30),
					deg(t.travel30),
					t.held,
					deg(t.slipAtRelease),
					deg(t.headingDrift),
					deg(t.slipAfter),
					t.endKmh
				)
			)
		end
	end
end

print("")
print("Tap: the right key held 1.5 s from 80 km/h, throttle off, with Space tapped 0.3 s at the start.")
print("car | heading turned with the tap | without")
for _, entry in CARS do
	local tapped, plain = DriftTurn.tap(entry.car, 80, FPS)
	print(("%s | %s | %s"):format(entry.label, deg(tapped), deg(plain)))
end

print("")
print("Ending: Space and the key held from 50 km/h, throttle off, until the car drops under the gate;")
print("with braking, the brake joins at 0.6 s. Over the 2 s after the drift ends: the heading's swing")
print("back against the turn (a snap) and on with it (Space, held under the gate, is the handbrake again).")
print("car | ended by | ended at s | heading back | heading on | peak body slip | spun")
for _, entry in CARS do
	for _, braking in { false, true } do
		local e = DriftTurn.ending(entry.car, 50, braking, FPS)
		print(
			("%s | %s | %s | %s | %s | %s | %s"):format(
				entry.label,
				if braking then "braking" else "the speed gate",
				if e.endedAt == math.huge then "never" else ("%.2f"):format(e.endedAt),
				deg(e.headingBack),
				deg(e.headingOn),
				deg(e.peakSlip),
				if e.spun then "SPUN" else "no"
			)
		)
	end
end
