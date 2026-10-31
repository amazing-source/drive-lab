--!strict
--[[
	Each car's lamp set against its model: the pieces its lamps wait for are pieces the model has,
	so a car is never left dark waiting for a piece that does not exist.
]]
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local CarLights = require("../src/shared/Config/CarLights")
local Catalog = require("../src/shared/Config/Cars/Catalog")
local DR458 = require("../src/shared/Config/Cars/DR458/Lights")
local DR458Flames = require("../src/shared/Config/Cars/DR458/Flames")
local DR458Model = require("../src/shared/Config/Cars/DR458/Model")
local SVJ = require("../src/shared/Config/Cars/SVJ/Lights")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local MANIFEST = serde.decode("json", fs.readFile("games/drive-lab/tests/fixtures/dr458_manifest.json"))

local function modelParts(): { [string]: boolean }
	local names: { [string]: boolean } = {}
	for _, part in MANIFEST.parts do
		names[part.name] = true
	end
	return names
end

local function rgbBrightness(colour: CarLights.Rgb): number
	return colour.r + colour.g + colour.b
end

describe("Car lamps: the SVJ", function()
	it("waits for the same ten light pieces as before", function()
		local expected = {
			"Light_FrontLeft_Projector",
			"Light_FrontRight_Projector",
			"Light_FrontLeft_Modules",
			"Light_FrontRight_Modules",
			"Light_RearLeft_Tail",
			"Light_RearRight_Tail",
			"Light_RearLeft_Indicator",
			"Light_RearRight_Indicator",
			"Light_RearLeft_Reverse",
			"Light_RearRight_Reverse",
		}
		expect(#SVJ.required).toBe(#expected)
		for _, name in expected do
			expect(table.find(SVJ.required, name) ~= nil).toBe(true)
		end
	end)

	it("has no rain light and no tell-tales, so its fog lamps stay dark", function()
		expect(SVJ.rain).toBe(nil)
		expect(SVJ.tellTales).toBe(nil)
	end)
end)

describe("Car lamps: the DR458", function()
	it("is the lamp set and the flames its catalog entry drives", function()
		expect(Catalog.cars.DR458.lights).toBe(DR458)
		expect(Catalog.cars.DR458.flames).toBe(DR458Flames)
	end)

	it("waits only for light pieces its model has: both projectors and both tail rings", function()
		local parts = modelParts()
		expect(#DR458.required > 0).toBe(true)
		for _, name in DR458.required do
			expect(parts[name]).toBe(true)
		end
		for _, name in { "Light_FrontLeft_Projector", "Light_FrontRight_Projector" } do
			expect(table.find(DR458.required, name) ~= nil).toBe(true)
		end
	end)

	it(
		"lights its rain light from a fog piece the model has, steady or in the FIA's flashing band",
		function()
			local rain = DR458.rain
			assert(rain, "the DR458 has a rain light")
			local parts = modelParts()
			expect(parts.Light_RearLeft_Fog or parts.Light_RearRight_Fog).toBe(true)
			local pattern = rain.pattern
			-- FIA 8874-2019 4.3: 4 Hz +- 0.5 at a 50 % +- 10 % duty cycle, when flashing.
			local steady = pattern.hz == 0
			local fia = pattern.hz >= 3.5
				and pattern.hz <= 4.5
				and pattern.onShare >= 0.4
				and pattern.onShare <= 0.6
			expect(steady or fia).toBe(true)
		end
	)

	it("outshines the tail ring on the brakes with its rain light, in red", function()
		local glow = DR458.glow
		expect(glow.fog.day >= glow.tail.day).toBe(true)
		expect(glow.fog.night >= glow.tail.night).toBe(true)
		expect(glow.fog.tint.r > glow.fog.tint.g * 4 and glow.fog.tint.r > glow.fog.tint.b * 4).toBe(true)
	end)

	it("has a tell-tale only for switches its panel has a lamp for, dimmer than the lamps outside", function()
		local tellTales = DR458.tellTales
		local panel = DR458Model.panelLamps
		assert(tellTales and panel, "the DR458 has tell-tales and panel lamps")
		local parts = modelParts()
		local count = 0
		for switch, spec in tellTales do
			count += 1
			local name = panel[switch]
			expect(name ~= nil and parts[name]).toBe(true)
			expect(spec.night < DR458.glow.tail.night).toBe(true)
			expect(rgbBrightness(spec.tint) > 0).toBe(true)
		end
		expect(count >= 2).toBe(true)
		expect(tellTales.headlights ~= nil and tellTales.rainLight ~= nil).toBe(true)
	end)
end)
