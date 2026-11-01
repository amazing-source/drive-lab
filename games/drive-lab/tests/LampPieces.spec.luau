--!strict
--[[
	Which lamp pieces play which role (Config/CarLights pieces, HOUSE_PIECES): the house names as
	Effects/CarLamps named them before the map existed, and the Boss 302's own map against its
	model's manifest.
]]
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Boss302Lights = require("../src/shared/Config/Cars/Boss302/Lights")
local Catalog = require("../src/shared/Config/Cars/Catalog")
local Config = require("../src/shared/Config/CarLights")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

-- Effects/CarLamps' piece names and glows before the map (main at 1d616e9), role by role.
local BEFORE = {
	drlLeft = "Light_FrontLeft_Drl=drl",
	drlRight = "Light_FrontRight_Drl=drl",
	projector = "Light_FrontLeft_Projector=projector Light_FrontRight_Projector=projector",
	left = "Light_FrontLeft_Modules=frontIndicator Light_RearLeft_Indicator=rearIndicator",
	right = "Light_FrontRight_Modules=frontIndicator Light_RearRight_Indicator=rearIndicator",
	position = "Light_FrontLeft_Marker=frontMarker Light_FrontRight_Marker=frontMarker "
		.. "Light_RearLeft_Marker=rearMarker Light_RearRight_Marker=rearMarker "
		.. "Light_RearLeft_Plate=plate Light_RearRight_Plate=plate",
	tail = "Light_RearLeft_Tail=tail Light_RearRight_Tail=tail",
	stop = "Light_RearLeft_Bar=stop Light_RearRight_Bar=stop",
	reverse = "Light_RearLeft_Reverse=reverse Light_RearRight_Reverse=reverse",
}

local function listed(pieces: { Config.Piece }?): string
	local out = {}
	for _, item in pieces or {} do
		table.insert(out, `{item.name}={item.glow}`)
	end
	return table.concat(out, " ")
end

describe("Lamp pieces", function()
	it("names the house pieces exactly as the lamps did before, and the SVJ and DR458 use them", function()
		local house = Config.HOUSE_PIECES :: any
		for role, names in BEFORE do
			expect(`{role}: {listed(house[role])}`).toBe(`{role}: {names}`)
		end
		expect(house.sweepLeft == nil and house.sweepRight == nil).toBe(true)
		for _, name in { "SVJ", "DR458" } do
			expect(Catalog.cars[name].lights.pieces).toBe(nil)
		end
	end)

	it("maps the Boss's pieces, every one in its model, each to one of its glows", function()
		local manifest =
			serde.decode("json", fs.readFile("games/drive-lab/tests/fixtures/boss302_manifest.json"))
		local present: { [string]: boolean } = {}
		for _, part in manifest.parts do
			present[part.name] = true
		end
		local pieces = assert(Boss302Lights.pieces, "the Boss names its pieces") :: any
		local glows = Boss302Lights.glow :: any
		local count = 0
		for _, list in pieces do
			if type(list) == "table" then
				for _, item in list do
					expect(if present[item.name] then "present" else item.name).toBe("present")
					expect(glows[item.glow] ~= nil).toBe(true)
					count += 1
				end
			end
		end
		expect(count > 0).toBe(true)
		for _, name in Boss302Lights.required do
			expect(if present[name] then "present" else name).toBe("present")
		end
	end)

	it("gives each of the Boss's rear compartments tail, brake and its place in the sweep, red", function()
		local pieces = assert(Boss302Lights.pieces, "the Boss names its pieces")
		for _, side in { "Left", "Right" } do
			local sweep = assert(if side == "Left" then pieces.sweepLeft else pieces.sweepRight, "a sweep")
			local inner, middle, outer =
				`Light_Rear{side}_BarInner`, `Light_Rear{side}_BarMiddle`, `Light_Rear{side}_BarOuter`
			expect(listed(sweep)).toBe(`{inner}=rearIndicator {middle}=rearIndicator {outer}=rearIndicator`)
			for _, name in { inner, middle, outer } do
				expect(string.find(listed(pieces.tail), name .. "=tail", 1, true) ~= nil).toBe(true)
				expect(string.find(listed(pieces.stop), name .. "=stop", 1, true) ~= nil).toBe(true)
			end
			-- They sweep, so they are not among the lamps that flash together.
			local flashing = listed(if side == "Left" then pieces.left else pieces.right)
			expect(string.find(flashing, "_Bar", 1, true)).toBe(nil)
		end
		local red = Boss302Lights.glow.rearIndicator.tint
		expect(red.r > 200 and red.g < 60 and red.b < 60).toBe(true)
		local rear = assert(Boss302Lights.indicator.rearColor, "US rear turn lamps are red")
		expect(rear.r > 200 and rear.g < 60).toBe(true)
		expect(Boss302Lights.rain).toBe(nil)
		expect(#pieces.drlLeft + #pieces.drlRight).toBe(0)
		-- A halogen white is warm: more red than green than blue.
		local halogen = Boss302Lights.glow.projector.tint
		expect(halogen.r >= halogen.g and halogen.g > halogen.b).toBe(true)
	end)

	it("finishes the Boss's sweep within UN R6's 200 ms of each flash's start", function()
		local step =
			assert(assert(Boss302Lights.pieces, "the Boss names its pieces").sweepStep, "a sweep step")
		expect(step > 0).toBe(true)
		-- Three compartments: the last lights two steps after the first.
		expect(2 * step <= 0.2).toBe(true)
	end)
end)
