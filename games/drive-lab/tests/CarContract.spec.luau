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
