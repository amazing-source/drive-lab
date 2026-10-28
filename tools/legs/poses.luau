--!strict
--[[
	Samples Rules/DriverLegs over every right-foot position (across the pedals, the throttle and
	the brake pressed) and the left foot at rest, from the seated hips, and writes the hip, knee
	and ankle of each in metres in the seat frame: the input of tools/blender/leg_clearance.py.
	Usage: lune run tools/legs/poses <SEAT_WELD.json> <out.json>
	SEAT_WELD.json is the seated R6 measured in Studio (drive-lab-assets/driver): its torso's
	centre in the DriverSeat's frame, studs, at Driving.DRIVER_SCALE.
]]
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Config = require("../../games/drive-lab/src/shared/Config/DriverLegs")
local Driving = require("../../games/drive-lab/src/shared/Config/Driving")
local Legs = require("../../games/drive-lab/src/shared/Rules/DriverLegs")
local Units = require("../../games/drive-lab/src/shared/Units")

type Vector = Legs.Vector

local seatWeld = serde.decode("json", fs.readFile(process.args[1]))
local torso = seatWeld.robloxSit.pointsInSeat.torsoCentre

local function hip(sign: number): Vector
	local scale = Driving.DRIVER_SCALE * Units.METRES_PER_STUD
	return {
		x = torso[1] * Units.METRES_PER_STUD + sign * Config.HIP.x * scale,
		y = torso[2] * Units.METRES_PER_STUD + Config.HIP.y * scale,
		z = torso[3] * Units.METRES_PER_STUD + Config.HIP.z * scale,
	}
end

local function point(v: Vector): { number }
	return { v.x, v.y, v.z }
end

local poses = {}
local function add(name: string, leg: Legs.Leg, side: string)
	table.insert(
		poses,
		{ name = name, side = side, hip = point(leg.hip), knee = point(leg.knee), ankle = point(leg.ankle) }
	)
end

local right, left = hip(1), hip(-1)
for step = 0, 20 do
	local over = step / 20
	local throttleAngle, brakeAngle = Legs.pedalAngles(over, 0, 0)
	add(string.format("across %.2f", over), Legs.right(right, over, throttleAngle, brakeAngle), "right")
end
for _, press in { 0.5, 1 } do
	local throttleAngle, brakeAngle = Legs.pedalAngles(0, press, 0)
	add(`throttle {press}`, Legs.right(right, 0, throttleAngle, brakeAngle), "right")
	throttleAngle, brakeAngle = Legs.pedalAngles(1, 0, press)
	add(`brake {press}`, Legs.right(right, 1, throttleAngle, brakeAngle), "right")
end
add("footrest", Legs.left(left), "left")
fs.writeFile(process.args[2], serde.encode("json", poses, true))
print(`{#poses} poses written`)
