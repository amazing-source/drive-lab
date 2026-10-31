--!strict
--[[
	Prints how each car handles at the limit on tools/DriveSim at each game-feel notch, driven as a
	keyboard or pad player drives (tools/HandlingScenario): braking, power and lift-off in a held
	corner, catching a slide, the steering's response and a quick lane change, with the car's own
	assists in its first mode and with its systems off.

	    lune run games/drive-lab/tools/handling.luau [fps]
]]
local DR458 = require("../src/shared/Config/Cars/DR458/Physics")
local DR458Assists = require("../src/shared/Config/Cars/DR458/Assists")
local GameFeel = require("../src/shared/Config/GameFeel")
local HandlingScenario = require("./HandlingScenario")
local InputHelp = require("../src/shared/Config/InputHelp")
local SVJ = require("../src/shared/Config/Cars/SVJ/Physics")
local SVJAssists = require("../src/shared/Config/Cars/SVJ/Assists")
local process = require("@lune/process")

local FPS = tonumber(process.args[1]) or 60

type Row = { label: string, setup: HandlingScenario.Setup }

local rows: { Row } = {
	{ label = "SVJ Strada", setup = { car = SVJ, assists = SVJAssists, mode = "Strada" } },
	{
		label = "SVJ Corsa ESC off",
		setup = { car = SVJ, assists = SVJAssists, mode = "Corsa", escOff = true },
	},
	{ label = "DR458 1", setup = { car = DR458, assists = DR458Assists, mode = "1" } },
	{ label = "DR458 OFF", setup = { car = DR458, assists = DR458Assists, mode = "OFF" } },
}

local function deg(radians: number): string
	return ("%.1f"):format(math.deg(radians))
end

local function seconds(value: number): string
	return if value == math.huge then "never" else ("%.2f"):format(value)
end

local function spin(spun: boolean): string
	return if spun then " SPUN" else ""
end

local function setupFor(row: Row, notch: GameFeel.Notch, help: InputHelp.InputHelp): HandlingScenario.Setup
	local setup = table.clone(row.setup)
	setup.fps = FPS
	setup.gameFeel = notch
	setup.help = help
	return setup
end

print(`Handling on DriveSim at {FPS} FPS, right-hand corners; keyboard help, the stick on the pad's help`)
print("")
print("Held corner, then an event with the key still down: peak oversteer body slip, deg")
print("Catch from 20 deg and 0.8 rad/s at 100 km/h: settle s / most slip the other way, deg")
print(
	"Notch | car | brake 0.3 at 120 | brake 1 at 120 | power at 60 | lift at 80 | catch: keys | stick | hands off"
)
for _, notch in GameFeel.ORDER do
	for _, row in rows do
		local keys = setupFor(row, notch, InputHelp.keyboard)
		local pad = setupFor(row, notch, InputHelp.gamepad)
		local light = HandlingScenario.brakeTurn(keys, 120, 0.3)
		local full = HandlingScenario.brakeTurn(keys, 120, 1)
		local power = HandlingScenario.powerOn(keys, 60)
		local lift = HandlingScenario.liftOff(keys, 80)
		local slip, yaw = math.rad(20), 0.8
		local onKeys = HandlingScenario.recover(keys, 100, slip, yaw, "keys")
		local onStick = HandlingScenario.recover(pad, 100, slip, yaw, "stick")
		local handsOff = HandlingScenario.recover(keys, 100, slip, yaw, "hands off")
		print(
			("%s | %s | %s%s | %s%s | %s%s | %s%s | %s / %s%s | %s / %s%s | %s%s"):format(
				notch,
				row.label,
				deg(light.peakSlip),
				spin(light.spun),
				deg(full.peakSlip),
				spin(full.spun),
				deg(power.peakSlip),
				spin(power.spun),
				deg(lift.peakSlip),
				spin(lift.spun),
				seconds(onKeys.settle),
				deg(onKeys.overcorrect),
				spin(onKeys.spun),
				seconds(onStick.settle),
				deg(onStick.overcorrect),
				spin(onStick.spun),
				seconds(handsOff.settle),
				spin(handsOff.spun)
			)
		)
	end
end

print("")
print("Normal driving on the keys: step steer yaw rad/s and t90 s, lane change at 120 km/h peak slip deg;")
print("assist = the most of the steering the slide assist held")
print("Notch | car | step at 100 | step at 180 | lane change 0.7 s")
for _, notch in GameFeel.ORDER do
	for _, row in rows do
		local keys = setupFor(row, notch, InputHelp.keyboard)
		local slow = HandlingScenario.stepSteer(keys, 100, 1)
		local fast = HandlingScenario.stepSteer(keys, 180, 1)
		local lane = HandlingScenario.laneChange(keys, 120, 0.7)
		print(
			("%s | %s | %.3f, %s, assist %.2f | %.3f, %s, assist %.2f | %s, assist %.2f"):format(
				notch,
				row.label,
				slow.yaw,
				seconds(slow.t90),
				slow.assistPeak,
				fast.yaw,
				seconds(fast.t90),
				fast.assistPeak,
				deg(lane.peakSlip),
				lane.assistPeak
			)
		)
	end
end
