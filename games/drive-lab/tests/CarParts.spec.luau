--!strict
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local CarParts = require("../src/shared/Rules/CarParts")
local DR458Model = require("../src/shared/Config/Cars/DR458/Model")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local function piece(name: string, part: string?): CarParts.Piece
	return { name = name, part = part }
end

describe("Car parts: what rides what", function()
	it("puts a part's other pieces on the piece named after it", function()
		local carriers = CarParts.carriers({
			piece("Door_L_Skin", "Door_L_Skin"),
			piece("Door_L_Skin_Rubber", "Door_L_Skin"),
			piece("Body_Paint_01"),
		}, nil)
		expect(carriers.Door_L_Skin_Rubber).toBe("Door_L_Skin")
		expect(carriers.Door_L_Skin).toBe(nil)
		expect(carriers.Body_Paint_01).toBe(nil)
	end)

	it("takes the binding's parents first, and chains through them", function()
		local carriers = CarParts.carriers({
			piece("Wheel_FL_Tyre"),
			piece("Wheel_FL", "Wheel_FL"),
			piece("Wheel_FL_AluminiumBrushed", "Wheel_FL"),
		}, { Wheel_FL = "Wheel_FL_Tyre" })
		expect(carriers.Wheel_FL).toBe("Wheel_FL_Tyre")
		expect(CarParts.root(carriers, "Wheel_FL_AluminiumBrushed")).toBe("Wheel_FL_Tyre")
		expect(CarParts.root(carriers, "Wheel_FL_Tyre")).toBe("Wheel_FL_Tyre")
	end)

	it("leaves a piece on the body when its carrier is not in the model", function()
		local carriers = CarParts.carriers(
			{ piece("Glass_Window", "Glass_Windscreen") },
			{ Glass_Window = "Nothing" }
		)
		expect(carriers.Glass_Window).toBe(nil)
	end)

	it("leaves every piece of a loop on the body", function()
		local carriers = CarParts.carriers(
			{ piece("A"), piece("B"), piece("C") },
			{ A = "B", B = "A", C = "A" }
		)
		expect(carriers.A).toBe(nil)
		expect(carriers.B).toBe(nil)
		expect(carriers.C).toBe("A")
	end)

	it("keeps every rider the DR458's binding names, with the steering hub the rig adds", function()
		local manifest =
			serde.decode("json", fs.readFile("games/drive-lab/tests/fixtures/dr458_manifest.json"))
		local pieces: { CarParts.Piece } = { piece(DR458Model.steeringWheel) }
		for _, part in manifest.parts do
			if part.mesh ~= false then
				table.insert(pieces, piece(part.name, part.name))
			end
		end
		local parents = DR458Model.parents
		assert(parents, "the DR458 has riders")
		local carriers = CarParts.carriers(pieces, parents)
		for rider, carrier in parents do
			expect(carriers[rider] and `{rider} -> {carriers[rider]}`).toBe(`{rider} -> {carrier}`)
		end
		for index, tyre in DR458Model.wheels do
			local corner = string.sub(tyre, 1, #tyre - #"_Tyre")
			expect(CarParts.root(carriers, corner)).toBe(DR458Model.wheels[index])
		end
	end)
end)
