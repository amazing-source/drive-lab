--!strict
--[[
	Prints what the driver's assists do on the SVJ's physics, offline at 60 FPS, for each drive
	mode with ESC on and switched off: full-throttle launches (from rest, and off launch control)
	against the tyre-smoke thresholds, a stop from 100 km/h, and a power-on slide out of a bend.
	`lune run games/drive-lab/tools/assists` from the repo root.
]]
local Config = require("../src/shared/Config/DriverAssists")
local DriveSim = require("./DriveSim")
local DriverAssists = require("../src/shared/Rules/DriverAssists")
local SVJ = require("../src/shared/Config/Cars/SVJ/Physics")
local TyreSmoke = require("../src/shared/Rules/TyreSmoke")
local TyreSmokeConfig = require("../src/shared/Config/TyreSmoke")
local Types = require("../src/shared/Config/Cars/Types")

local DT = 1 / 60
local KMH = 1 / 3.6
local MODES: { Types.DrivingMode } = { "Strada", "Sport", "Corsa" }

local function input(
	escOff: boolean,
	mode: Types.DrivingMode,
	throttle: number,
	brake: number,
	steer: number
): DriveSim.InputOptions
	local assists = DriverAssists.assists(escOff, Config)
	return {
		throttle = throttle,
		brake = brake,
		steer = steer,
		drivingMode = mode,
		abs = assists.abs,
		tc = assists.tc,
		esc = assists.esc,
	}
end

local function launch(mode: Types.DrivingMode, escOff: boolean, launchControl: boolean): string
	local sim = DriveSim.new(SVJ)
	if launchControl then
		local hold = DriveSim.input(input(escOff, mode, 1, 1, 0))
		while sim.time < 1.5 do
			DriveSim.frame(sim, hold, DT)
		end
	end
	local go = DriveSim.input(input(escOff, mode, 1, 0, 0))
	local readings: { TyreSmoke.Wheel } = {}
	local share, slip, slide, tcTime, time100 = 0, 0, 0, 0, math.huge
	local start = sim.time
	while sim.time - start < 4 do
		local result = DriveSim.frame(sim, go, DT)
		TyreSmoke.measure(sim.model, result.wheels, readings)
		for wheel = 3, 4 do
			local reading = readings[wheel]
			share = math.max(share, TyreSmoke.share(reading, TyreSmokeConfig.THRESHOLDS))
			slip = math.max(slip, reading.slip)
			slide = math.max(slide, reading.slide)
		end
		tcTime += if result.telemetry.tcActive then DT else 0
		if time100 == math.huge and DriveSim.forwardSpeed(sim) >= 100 * KMH then
			time100 = sim.time - start
		end
	end
	return ("%.2f | %.1f | %.1f | %.2f | %s"):format(
		share,
		slip,
		slide,
		tcTime,
		if time100 == math.huge then "over 4" else ("%.2f"):format(time100)
	)
end

local function stop(mode: Types.DrivingMode, escOff: boolean): string
	local sim = DriveSim.new(SVJ)
	DriveSim.setSpeed(sim, 100 * KMH, 3)
	local coast = DriveSim.input(input(escOff, mode, 0, 0, 0))
	while sim.time < 0.5 do
		DriveSim.frame(sim, coast, DT)
	end
	local brake = DriveSim.input(input(escOff, mode, 0, 1, 0))
	local startX, absTime, leastRolling = sim.body.x, 0, 1
	while DriveSim.forwardSpeed(sim) > 0.05 and sim.time < 10 do
		local result = DriveSim.frame(sim, brake, DT)
		absTime += if result.telemetry.absActive then DT else 0
		for wheel = 1, 4 do
			local ground = sim.model.ground[wheel]
			if ground > 5 then
				local rolling = sim.model.spins[wheel] * sim.model.tyres[wheel].radius / ground
				leastRolling = math.min(leastRolling, rolling)
			end
		end
	end
	return ("%.1f | %.2f | %.2f"):format(sim.body.x - startX, absTime, leastRolling)
end

-- 2 s at 60 km/h in 2nd on a steady lock, then 2 s of full throttle.
local function slide(mode: Types.DrivingMode, escOff: boolean): string
	local sim = DriveSim.new(SVJ)
	DriveSim.setSpeed(sim, 60 * KMH, 2)
	local cruise = DriveSim.input(input(escOff, mode, 0.2, 0, 0.3))
	while sim.time < 2 do
		DriveSim.frame(sim, cruise, DT)
	end
	local floor = DriveSim.input(input(escOff, mode, 1, 0, 0.3))
	local peak, escTime = 0, 0
	while sim.time < 4 do
		local result = DriveSim.frame(sim, floor, DT)
		local forward, right = DriveSim.localVelocity(sim.body)
		peak = math.max(peak, math.deg(math.abs(math.atan2(right, math.abs(forward)))))
		escTime += if result.telemetry.escActive then DT else 0
	end
	return ("%.1f | %.2f"):format(peak, escTime)
end

local function line(text: string)
	print(text)
end

line("Launch, 4 s of full throttle: rear tyres' peak smoke share (0 to 1), combined slip over the")
line("peak's, slide m/s; TC acting s; 0-100 km/h s")
line("Mode | ESC | Start | Smoke | Slip | Slide | TC s | 0-100")
for _, mode: Types.DrivingMode in MODES do
	for _, escOff in { false, true } do
		for _, launchControl in { false, true } do
			line(
				("%s | %s | %s | %s"):format(
					mode,
					if escOff then "off" else "on",
					if launchControl then "launch control" else "from rest",
					launch(mode, escOff, launchControl)
				)
			)
		end
	end
end

line("")
line("Stop from 100 km/h: distance m | ABS acting s | least rolling share of any wheel (0 = locked)")
for _, mode: Types.DrivingMode in MODES do
	for _, escOff in { false, true } do
		line(("%s | ESC %s | %s"):format(mode, if escOff then "off" else "on", stop(mode, escOff)))
	end
end

line("")
line("Power-on slide, 60 km/h in 2nd at a steady lock then full throttle: peak body slip deg | ESC acting s")
for _, mode: Types.DrivingMode in MODES do
	for _, escOff in { false, true } do
		line(("%s | ESC %s | %s"):format(mode, if escOff then "off" else "on", slide(mode, escOff)))
	end
end
