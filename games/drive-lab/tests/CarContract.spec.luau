--!strict
local Catalog = require("../src/shared/Config/Cars/Catalog")
local Contract = require("../src/shared/Config/Cars/Contract")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

-- Stands in for a car model: only its "Car" attribute is read.
local function modelNamed(name: unknown): Instance
	return (
		{
			GetAttribute = function(_, attribute: string): unknown
				return if attribute == "Car" then name else nil
			end,
		} :: any
	) :: Instance
end

describe("Car catalog", function()
	it("finds a car's entry by the model's Car attribute, and nothing for any other value", function()
		expect(Catalog.of(modelNamed("SVJ"))).toBe(Catalog.cars.SVJ)
		expect(Catalog.of(modelNamed("Unknown"))).toBe(nil)
		expect(Catalog.of(modelNamed(nil))).toBe(nil)
		expect(Catalog.of(modelNamed(1))).toBe(nil)
	end)

	it("freezes every entry all the way down", function()
		for _, entry in Catalog.cars do
			expect(function()
				(entry :: any).physics = nil
			end).toThrow()
			expect(function()
				(entry.model.wheels :: any)[1] = "Other"
			end).toThrow()
		end
	end)
end)

-- An unfrozen copy of the SVJ's entry with one change made by `change`, for `define` to judge.
local function svjWith(change: (any) -> ()): Contract.Entry
	local function copy(value: any): any
		if type(value) ~= "table" then
			return value
		end
		local out = {}
		for key, child in value do
			out[key] = copy(child)
		end
		return out
	end
	local entry = copy(Catalog.cars.SVJ)
	change(entry)
	return entry
end

describe("Car contract", function()
	it("accepts the SVJ as it is", function()
		expect(Contract.define(svjWith(function() end)).physics.name).toBe(Catalog.cars.SVJ.physics.name)
	end)

	it("refuses a start-up that moves a control the model does not hinge", function()
		expect(function()
			Contract.define(svjWith(function(entry)
				entry.startup.moves[1].control = "MasterSwitch"
			end))
		end).toThrow()
		expect(function()
			Contract.define(svjWith(function(entry)
				entry.model.controls = nil
			end))
		end).toThrow()
	end)

	it("refuses a control moved twice, moved in no time, or turned back before it arrives", function()
		expect(function()
			Contract.define(svjWith(function(entry)
				table.insert(entry.startup.moves, table.clone(entry.startup.moves[1]))
			end))
		end).toThrow()
		expect(function()
			Contract.define(svjWith(function(entry)
				entry.startup.moves[1].move = 0
			end))
		end).toThrow()
		expect(function()
			Contract.define(svjWith(function(entry)
				entry.startup.moves[1].back = entry.startup.moves[1].at - 0.1
			end))
		end).toThrow()
	end)

	it("refuses a start-up that drives before START or before the hands are on the wheel", function()
		expect(function()
			Contract.define(svjWith(function(entry)
				entry.startup.wheelAt = entry.startup.pressAt
				entry.startup.drivableAt = entry.startup.pressAt
			end))
		end).toThrow()
		expect(function()
			Contract.define(svjWith(function(entry)
				entry.startup.wheelAt = entry.startup.drivableAt + 0.1
			end))
		end).toThrow()
	end)
end)

describe("Car contract: the driver", function()
	it("refuses a footwell pedal the model binding does not hinge", function()
		expect(function()
			Contract.define(svjWith(function(entry)
				entry.driver.footwell.brake.part = "Pedal_Clutch"
			end))
		end).toThrow()
		expect(function()
			Contract.define(svjWith(function(entry)
				entry.model.pedals = nil
			end))
		end).toThrow()
	end)
end)

describe("Car contract: the display", function()
	it("refuses a cluster without colours for one of the car's drive modes", function()
		expect(function()
			Contract.define(svjWith(function(entry)
				entry.cluster.modes.Corsa = nil
			end))
		end).toThrow()
	end)

	it("refuses a redline off the cluster's dial", function()
		expect(function()
			Contract.define(svjWith(function(entry)
				entry.cluster.redlineRpm = entry.cluster.dialMaxRpm
			end))
		end).toThrow()
		expect(function()
			Contract.define(svjWith(function(entry)
				entry.cluster.redlineRpm = 0
			end))
		end).toThrow()
	end)
end)

describe("Car contract: drive modes", function()
	it("refuses a part keyed by drive mode that leaves one of the car's modes out", function()
		local leaveOut: { (any) -> () } = {
			function(entry)
				entry.modeLabels.Sport = nil
			end,
			function(entry)
				entry.camera.shiftKick.Sport = nil
			end,
			function(entry)
				entry.audio.popTriggers.liftChance.Sport = nil
			end,
			function(entry)
				entry.audio.popTriggers.upshiftChance.Sport = nil
			end,
			function(entry)
				entry.audio.popTriggers.downshiftChance.Sport = nil
			end,
		}
		for _, change in leaveOut do
			expect(function()
				Contract.define(svjWith(change))
			end).toThrow()
		end
	end)

	it("refuses a part keyed by drive mode that names a mode the car does not have", function()
		local stray: { (any) -> () } = {
			function(entry)
				entry.modeLabels.Pista = "Pista"
			end,
			function(entry)
				entry.camera.shiftKick.Pista = 1
			end,
			function(entry)
				entry.audio.popTriggers.liftChance.Pista = 1
			end,
			function(entry)
				entry.cluster.modes.Pista = entry.cluster.modes.Corsa
			end,
			function(entry)
				entry.assists.modes = { Pista = entry.assists.on }
			end,
		}
		for _, change in stray do
			expect(function()
				Contract.define(svjWith(change))
			end).toThrow()
		end
	end)

	it("accepts assists set by one of the car's own modes", function()
		local entry = Contract.define(svjWith(function(entry)
			entry.assists.modes = { Corsa = { abs = true, tc = false, esc = true } }
		end))
		expect(entry.assists.modes and entry.assists.modes.Corsa.tc).toBe(false)
	end)
end)

describe("Car contract: switches", function()
	local PIT = { limitKmh = 60, armGear = 2, armBelowKmh = 60, band = 3 }
	local WIPER = { wipeSeconds = 1.2, afterWash = 3 }

	it("accepts a pit limiter, a wiper and display pages that make sense", function()
		local entry = Contract.define(svjWith(function(entry)
			entry.switches.pitLimiter = table.clone(PIT)
			entry.switches.wiper = table.clone(WIPER)
			entry.switches.displayPages = 3
		end))
		expect(Contract.features(entry).pitLimiter).toBe(true)
		expect(Contract.features(entry).wiper).toBe(true)
		expect(Contract.features(entry).displayPages).toBe(true)
	end)

	it("refuses a pit limiter with no band or one that arms above its own limit", function()
		for _, change in { { band = 0 }, { limitKmh = 0 }, { armBelowKmh = 80 } } do
			expect(function()
				Contract.define(svjWith(function(entry)
					local pit = table.clone(PIT) :: any
					for key, value in change do
						pit[key] = value
					end
					entry.switches.pitLimiter = pit
				end))
			end).toThrow()
		end
	end)

	it("refuses a wiper with no wipe time or a part of a wipe after a wash", function()
		for _, change in { { wipeSeconds = 0 }, { afterWash = 1.5 }, { afterWash = -1 } } do
			expect(function()
				Contract.define(svjWith(function(entry)
					local wiper = table.clone(WIPER) :: any
					for key, value in change do
						wiper[key] = value
					end
					entry.switches.wiper = wiper
				end))
			end).toThrow()
		end
	end)

	it("refuses a display with one page, or a part of one", function()
		for _, pages in { 1, 2.5 } do
			expect(function()
				Contract.define(svjWith(function(entry)
					entry.switches.displayPages = pages
				end))
			end).toThrow()
		end
	end)

	it("reports what the SVJ has: an ESC button and launch control, none of the race switches", function()
		local features = Contract.features(Catalog.cars.SVJ)
		expect(features.escButton and features.launch).toBe(true)
		expect(features.pitLimiter or features.wiper or features.rainLight or features.displayPages).toBe(
			false
		)
	end)
end)

describe("Car contract: a binnacle display", function()
	local DR458Screen = require("../src/shared/Config/Cars/DR458/Binnacle")

	-- The SVJ with the DR458's binnacle in place of its dial, drawn to the SVJ's screen shape.
	local function withBinnacle(change: ((any) -> ())?): Contract.Entry
		return svjWith(function(entry)
			local glass = entry.model.cluster
			local screen = table.clone(DR458Screen) :: any
			screen.canvasHeight = 300
			screen.canvasWidth = 300 * glass.width / glass.height
			entry.cluster = nil
			entry.binnacle = screen
			entry.switches.displayPages = #screen.pages
			if change then
				change(entry)
			end
		end)
	end

	it("accepts a binnacle in place of the dial, and reads its redline", function()
		local entry = Contract.define(withBinnacle())
		expect(Contract.redline(entry)).toBe(DR458Screen.redlineRpm)
		expect(Contract.redline(Catalog.cars.SVJ)).toBe((Catalog.cars.SVJ.cluster :: any).redlineRpm)
	end)

	it("refuses a car with no display, or with both", function()
		expect(function()
			Contract.define(svjWith(function(entry)
				entry.cluster = nil
			end))
		end).toThrow()
		expect(function()
			Contract.define(svjWith(function(entry)
				entry.binnacle = table.clone(DR458Screen)
				entry.switches.displayPages = #DR458Screen.pages
			end))
		end).toThrow()
	end)

	it("refuses pages its page switch does not step through", function()
		expect(function()
			Contract.define(withBinnacle(function(entry)
				entry.switches.displayPages = nil
			end))
		end).toThrow()
		expect(function()
			Contract.define(withBinnacle(function(entry)
				entry.switches.displayPages = 2
			end))
		end).toThrow()
	end)

	it("refuses rev lights that do not rise, a redline off the bar, or a canvas of another shape", function()
		local breaks: { (any) -> () } = {
			function(entry)
				entry.binnacle.revLights = table.clone(entry.binnacle.revLights)
				entry.binnacle.revLights.toRpm = entry.binnacle.revLights.fromRpm
			end,
			function(entry)
				entry.binnacle.redlineRpm = entry.binnacle.barToRpm + 1
			end,
			function(entry)
				entry.binnacle.canvasWidth *= 1.2
			end,
		}
		for _, change in breaks do
			expect(function()
				Contract.define(withBinnacle(change))
			end).toThrow()
		end
	end)
end)

-- The SVJ with its own start-up sound, timed to its start-up (catch 0.75 s after the press, the
-- starter's revs held to 0.7 s), and then `change` made to that sound or that start-up.
local function withSound(change: (any) -> ()): Contract.Entry
	return svjWith(function(entry)
		entry.audio.startup.sound = {
			id = "rbxassetid://1",
			volume = 1,
			from = 0.2,
			starterEnds = 0.9,
			catchAt = 0.95,
			handOver = 9,
			to = 10,
		}
		change(entry)
	end)
end

describe("Car contract: the start-up sound", function()
	it("accepts a start-up sound that keeps to the start-up's timing, and none at all", function()
		expect(Contract.define(withSound(function() end)).audio.startup.sound ~= nil).toBeTruthy()
		expect(Catalog.cars.SVJ.audio.startup.sound).toBe(nil)
	end)

	it("refuses a start-up sound that is not an uploaded asset, or has no level", function()
		local breaks: { (any) -> () } = {
			function(entry)
				entry.audio.startup.sound.id = "126032464409866"
			end,
			function(entry)
				entry.audio.startup.sound.volume = 0
			end,
		}
		for _, change in breaks do
			expect(function()
				Contract.define(withSound(change))
			end).toThrow()
		end
	end)

	it("refuses a start-up sound whose times run out of order", function()
		-- Each break keeps the catch and the starter's revs in step, so only the order is wrong.
		local breaks: { (any) -> () } = {
			function(entry)
				local sound = entry.audio.startup.sound
				sound.from, sound.starterEnds, sound.catchAt = -0.1, 0.6, 0.65
			end,
			function(entry)
				entry.audio.startup.sound.handOver = entry.audio.startup.sound.to
			end,
			function(entry)
				entry.audio.startup.sound.handOver = entry.audio.startup.sound.catchAt
			end,
		}
		for _, change in breaks do
			expect(function()
				Contract.define(withSound(change))
			end).toThrow()
		end
	end)

	it("refuses a start-up sound that catches at another time than the start-up", function()
		expect(function()
			Contract.define(withSound(function(entry)
				entry.audio.startup.sound.catchAt += 0.1
			end))
		end).toThrow()
		expect(function()
			Contract.define(withSound(function(entry)
				entry.startup.catchAfter += 0.1
			end))
		end).toThrow()
	end)

	it(
		"refuses instruments that leave the starter's revs before its starter stops or after the catch",
		function()
			expect(function()
				Contract.define(withSound(function(entry)
					entry.audio.startup.sound.starterEnds = entry.audio.startup.sound.catchAt
				end))
			end).toThrow()
			expect(function()
				Contract.define(withSound(function(entry)
					entry.startup.rpm.values[3] = entry.startup.rpm.values[1]
				end))
			end).toThrow()
		end
	)
end)
