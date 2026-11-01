--!strict
local Binding = require("../src/shared/Config/Cars/Binding")
local CarImportNames = require("../tools/CarImportNames")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local ZERO = { forward = 0, right = 0, up = 0 }
local UP = { forward = 0, right = 0, up = 1 }

local function hinge(part: string): Binding.Hinge
	return { part = part, pivot = ZERO, axis = UP }
end

local function model(): Binding.CarModel
	return {
		wheels = { "Wheel_FL_Tyre", "Wheel_FR_Tyre", "Wheel_RL_Tyre", "Wheel_RR_Tyre" },
		calipers = { { "Caliper_FL" }, { "Caliper_FR" }, {}, {} },
		steeringWheel = "SteeringWheel",
		steeringWheelLift = 0,
		seat = ZERO,
		hullClearance = 0.25,
		bodyRaise = 0,
		cluster = { forward = 0, right = 0, up = 0, width = 0, height = 0, tilt = 0 },
		glazing = { "Glass_Windscreen" },
		windshield = {},
		door = {
			parts = { "Door_L_Skin", "Door_L_Glass" },
			pivot = ZERO,
			axis = UP,
			openAngle = 1,
			strap = {
				part = "Door_L_Strap",
				top = ZERO,
				facing = UP,
				length = 0.2,
				lean = 0,
				grab = 0.3,
				hang = {},
			},
		},
		controls = { Key_Ignition = hinge("Key_Ignition") },
		pedals = { hinge("Pedal_Brake") },
		parents = { SteeringWheel_Rim = "SteeringWheel", Wheel_FL = "Wheel_FL_Tyre" },
		steeringHub = { pivot = ZERO, axis = UP },
		exhaust = { left = "Exhaust_L", right = "Exhaust_R", outlet = { right = 0, back = 0, up = 0 } },
		shiftLights = { "ShiftLight_1" },
		panelLamps = { Light = "PanelLamp_Light" },
		wiper = { hinge = hinge("Wiper_Arm"), blade = { inner = ZERO, outer = ZERO }, nozzles = {} },
		shifter = {
			part = "Shifter_Lever",
			pivot = ZERO,
			axisFore = UP,
			axisSide = UP,
			gates = {},
			knob = ZERO,
			push = 0,
		},
	}
end

describe("CarImportNames", function()
	it("lists every part the binding looks up, sorted, once each", function()
		local names = CarImportNames.of(model(), { "Light_FrontLeft_Headlamp", "Glass_Windscreen" })
		expect(table.concat(names, ",")).toBe(table.concat({
			"Caliper_FL",
			"Caliper_FR",
			"Door_L_Glass",
			"Door_L_Skin",
			"Door_L_Strap",
			"Exhaust_L",
			"Exhaust_R",
			"Glass_Windscreen",
			"Key_Ignition",
			"Light_FrontLeft_Headlamp",
			"PanelLamp_Light",
			"Pedal_Brake",
			"ShiftLight_1",
			"Shifter_Lever",
			"SteeringWheel_Rim",
			"Wheel_FL",
			"Wheel_FL_Tyre",
			"Wheel_FR_Tyre",
			"Wheel_RL_Tyre",
			"Wheel_RR_Tyre",
			"Wiper_Arm",
		}, ","))
	end)

	it("expects the steering wheel's part only when the rig does not build a hub for it", function()
		local withHub = CarImportNames.of(model())
		expect(table.find(withHub, "SteeringWheel")).toBe(nil)
		local plain = model()
		plain.steeringHub = nil
		expect(table.find(CarImportNames.of(plain), "SteeringWheel") ~= nil).toBe(true)
	end)

	it("reads a hinge's part from a field added later in the same form", function()
		local later = model() :: any
		later.needles = { Speedo = hinge("Needle_Speedo") }
		expect(table.find(CarImportNames.of(later), "Needle_Speedo") ~= nil).toBe(true)
	end)

	it("leaves out the display screens the rig builds itself", function()
		local withDisplays = model() :: any
		withDisplays.displays = { MessageCentre = { part = "DisplayMessageCentre" } }
		expect(table.find(CarImportNames.of(withDisplays), "DisplayMessageCentre")).toBe(nil)
	end)
end)
