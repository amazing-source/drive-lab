--!strict
--[[
	The Boss 302's key start (Config/Cars/Boss302/Startup), before the car joins the catalog: the
	timeline's own rules, read through Rules/CarEntry as any car's.
]]
local Config = require("../src/shared/Config/CarEntry")
local Pending = require("../src/shared/Config/Cars/Boss302/StartupPending")
local Rules = require("../src/shared/Rules/CarEntry")
local Startup = require("../src/shared/Config/Cars/Boss302/Startup")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local CAR = { startup = Startup } :: any
local ON = {
	entry = "None",
	entryAt = 0,
	entryDoorOpen = false,
	door = "Closed",
	doorAt = 0,
	engine = "On",
	engineAt = 0,
} :: any

local function key(t: number): number
	return math.deg(Rules.controlAngle(CAR, "Key_Ignition", ON, t))
end

describe("Boss 302 key start", function()
	it("turns the key to ON, on to START at the press, and lets it spring back to ON as it cranks", function()
		local moves = Startup.moves
		local onAt, startMove = moves[1].at, moves[2]
		expect(key(0)).toBe(0)
		expect(key(onAt)).toBeNear(60, 1e-6)
		expect(key(Startup.pressAt - startMove.move - 0.01)).toBeNear(60, 1e-6)
		-- The key reaches START exactly at the press: the starter and the start sound.
		expect(startMove.at).toBe(Startup.pressAt)
		expect(key(Startup.pressAt)).toBeNear(90, 1e-6)
		local back = assert(startMove.back, "the key springs back")
		expect(back > Startup.pressAt and back < Startup.pressAt + Startup.catchAfter).toBe(true)
		expect(key(back + startMove.move)).toBeNear(60, 1e-6)
		expect(key(Startup.drivableAt + 10)).toBeNear(60, 1e-6)
	end)

	it("keeps the timeline's order: ON, START, the hands on the wheel, driving unlocked", function()
		expect(Startup.moves[1].at < Startup.pressAt).toBe(true)
		expect(Startup.pressAt < Startup.wheelAt).toBe(true)
		expect(Startup.wheelAt <= Startup.drivableAt).toBe(true)
	end)

	it("holds the clutch down from the key until driving unlocks, as the starter interlock needs", function()
		expect(Startup.interlock).toBe("Clutch")
		expect(Rules.startupClutch(CAR, ON, 0.1)).toBe(1)
		expect(Rules.startupClutch(CAR, ON, Startup.pressAt)).toBe(1)
		expect(Rules.startupClutch(CAR, ON, Startup.drivableAt + 0.01)).toBe(nil)
		expect(Rules.startRefusal(CAR, { engine = "Off" } :: any, Config.CLUTCH_INTERLOCK.gearboxMode, 0)).toBe(
			"Clutch"
		)
	end)

	it("starts with the TracKey in the TracKey drive mode and the standard key otherwise", function()
		expect(Rules.startKey(CAR, "TracKey")).toBe("TracKey")
		expect(Rules.startKey(CAR, "Normal")).toBe(Config.STANDARD_KEY)
	end)

	it("says what it still estimates, so it cannot join the catalog unnoticed", function()
		expect(#Pending > 0).toBe(true)
	end)
end)
