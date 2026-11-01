--!strict
local Model = require("../src/shared/Config/Cars/Boss302/Model")
local Physics = require("../src/shared/Config/Cars/Boss302/Physics")
local Shift = require("../src/shared/Config/Cars/Boss302/Shift")
local ShiftHand = require("../src/shared/Rules/ShiftHand")
local T = require("../../../tools/test/T")
local Types = require("../src/shared/Config/Cars/Types")

local describe, it, expect = T.describe, T.it, T.expect

local MANUAL = Physics.gearbox.manual :: Types.ManualGearboxConfig
local LEVER =
	ShiftHand.leverFromBinding(assert(Model.shifter, "the Boss binds its lever"), MANUAL.gates, Model.seat)

describe("Boss 302 shift hand data", function()
	it("times the hand and the foot as the gearbox plans them: one clock", function()
		expect(Shift.reach).toBe(MANUAL.timing.reach)
		expect(Shift.release).toBe(MANUAL.timing.release)
		expect(Shift.foot).toBe(MANUAL.timing.footMove)
	end)

	it("offers a quicker pace on the same way", function()
		local quick = assert(Shift.quick, "the Boss keys a game-quick pace")
		expect(quick.reach < Shift.reach).toBe(true)
		expect(quick.release < Shift.release).toBe(true)
		expect(quick.foot < Shift.foot).toBe(true)
	end)

	it("keys the way in time order with unit rotations, from the wheel grip to the Knob hand", function()
		local keys = Shift.hand.keys
		expect(keys[1][1]).toBe(0)
		for index = 2, #keys do
			expect(keys[index][1] > keys[index - 1][1]).toBe(true)
		end
		for _, key in keys do
			expect(key[5] ^ 2 + key[6] ^ 2 + key[7] ^ 2 + key[8] ^ 2).toBeNear(1, 1e-3)
		end
		expect(Shift.hand.shapes[1].shape).toBe("Grip")
		expect(Shift.hand.shapes[#Shift.hand.shapes].shape).toBe("Knob")
	end)

	it("ends the way on the knob held in neutral, where the lever's binding puts it, to 0.1 mm", function()
		local neutral = MANUAL.gates[0]
		local held = ShiftHand.knobWrist(ShiftHand.lever(LEVER, neutral.column, neutral.row, 0), Shift.grip)
		local last = Shift.hand.keys[#Shift.hand.keys]
		local off = math.sqrt(
			(held.position.x - last[2]) ^ 2
				+ (held.position.y - last[3]) ^ 2
				+ (held.position.z - last[4]) ^ 2
		)
		expect(off < 1e-4).toBe(true)
		expect(Shift.knobRadius).toBeNear(0.0246, 1e-4)
	end)
end)
