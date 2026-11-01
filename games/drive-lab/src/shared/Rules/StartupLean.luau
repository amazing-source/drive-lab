--!strict
--[[
	The seated driver's torso lean through the start-up (a car's startup paths' LEAN,
	Config/DriverStartup): how far forward it is at a time after the start key, and that lean as a
	turn in the driver's seat frame about the hips, which Rig/StartupLean puts on the root joint
	and takes back out of the cockpit eye. Plain numbers, so Lune can test it.
]]
local DriverStartup = require("../Config/DriverStartup")
local StartupArms = require("./StartupArms")

type Vector = StartupArms.Vector
type Rotation = StartupArms.Rotation

local StartupLean = {}

local function smoothstep(u: number): number
	return u * u * (3 - 2 * u)
end

-- Degrees forward `sinceKey` seconds after the start key: smoothstep between the keys, 0 outside
-- their span or with no start key.
function StartupLean.degrees(lean: DriverStartup.Lean?, sinceKey: number?): number
	if lean == nil or sinceKey == nil then
		return 0
	end
	local keys = lean.keys
	if #keys == 0 or sinceKey < keys[1][1] or sinceKey > keys[#keys][1] then
		return 0
	end
	for index = 2, #keys do
		local from, to = keys[index - 1], keys[index]
		if sinceKey <= to[1] then
			local u = (sinceKey - from[1]) / (to[1] - from[1])
			return from[2] + (to[2] - from[2]) * smoothstep(u)
		end
	end
	return keys[#keys][2]
end

-- The lean of `degrees` about `pivot` (seat frame, metres) as p' = turn p + offset: a turn about
-- the seat's x axis, positive tipping the torso's top toward the nose (-z).
function StartupLean.turn(pivot: DriverStartup.Point, degrees: number): (Rotation, Vector)
	local half = -math.rad(degrees) / 2
	local turn = { w = math.cos(half), x = math.sin(half), y = 0, z = 0 }
	local angle = -math.rad(degrees)
	local c, s = math.cos(angle), math.sin(angle)
	local turned = { x = pivot.x, y = pivot.y * c - pivot.z * s, z = pivot.y * s + pivot.z * c }
	return turn, { x = pivot.x - turned.x, y = pivot.y - turned.y, z = pivot.z - turned.z }
end

return table.freeze(StartupLean)
