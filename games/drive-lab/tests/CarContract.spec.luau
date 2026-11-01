--!strict
local Catalog = require("../src/shared/Config/Cars/Catalog")
local Boss302Model = require("../src/shared/Config/Cars/Boss302/Model")
local Boss302Physics = require("../src/shared/Config/Cars/Boss302/Physics")
local Contract = require("../src/shared/Config/Cars/Contract")
local DriverArms = require("../src/shared/Config/DriverArms")
local Driving = require("../src/shared/Config/Driving")
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

	it("admits a car only once its model binding, its start-up and its entry have nothing pending", function()
		local fs = require("@lune/fs")
		for name in Catalog.cars do
			for _, list in { "ModelPending", "StartupPending", "EntryPending" } do
				local path = `games/drive-lab/src/shared/Config/Cars/{name}/{list}.luau`
				if fs.isFile(path) then
					local pending = (require :: any)(`../src/shared/Config/Cars/{name}/{list}`)
					expect(`{name} {list}: {table.concat(pending, "; ")}`).toBe(`{name} {list}: `)
				end
			end
		end
		expect(Catalog.of(modelNamed("DR458"))).toBe(Catalog.cars.DR458)
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

	it("accepts two moves of one control, as an ignition key's ON then START", function()
		local entry = Contract.define(svjWith(function(entry)
			table.insert(entry.startup.moves, table.clone(entry.startup.moves[1]))
		end))
		expect(#entry.startup.moves).toBe(2)
	end)

	it(
		"refuses a start-up clutch outside 0 to 1, an interlock it does not press, or a key for no mode",
		function()
			local changes: { (any) -> () } = {
				function(startup)
					startup.clutch = 0
				end,
				function(startup)
					startup.clutch = 1.5
				end,
				function(startup)
					startup.interlock = "Clutch"
				end,
				function(startup)
					startup.keys = { Track = "TracKey" }
				end,
				function(startup)
					startup.keys = { Corsa = "Standard" }
				end,
			}
			for _, change in changes do
				expect(function()
					Contract.define(svjWith(function(entry)
						change(entry.startup)
					end))
				end).toThrow()
			end
			local entry = Contract.define(svjWith(function(entry)
				entry.startup.clutch = 1
				entry.startup.interlock = "Clutch"
				entry.startup.keys = { Corsa = "TracKey" }
			end))
			expect(entry.startup.interlock).toBe("Clutch")
		end
	)

	it("refuses a control moved in no time, or turned back before it arrives", function()
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
	-- A minimal shift hand: the contract checks what it holds, not its keys.
	local shift = {
		knobRadius = 0.025,
		grip = { 0, 0, 0, 0, 1, 0, 0, 0 },
		hand = {
			keys = { { 0, 0, 0, 0, 1, 0, 0, 0 }, { 0.3, 0, 0, 0, 1, 0, 0, 0 } },
			shapes = { { at = 0, shape = "Grip" } },
		},
		reach = 0.3,
		release = 0.3,
		foot = 0.2,
	}

	it(
		"gives a shift hand only a lever the model binds, on a manual gearbox whose gates it covers",
		function()
			expect(function()
				Contract.define(svjWith(function(entry)
					entry.driver.shift = shift
				end))
			end).toThrow()
			expect(function()
				Contract.checkShift(svjWith(function(entry)
					entry.driver.shift = shift
					entry.model.shifter = Boss302Model.shifter
				end))
			end).toThrow()
			local boss = svjWith(function(entry)
				entry.driver.shift = shift
				entry.model.shifter = Boss302Model.shifter
				entry.model.seat = Boss302Model.seat
				entry.physics = Boss302Physics
			end)
			Contract.checkShift(boss)
			local skewed = table.clone(boss.model.shifter.gates)
			skewed["4"] = { side = 0.05, fore = skewed["4"].fore }
			boss.model.shifter = table.clone(boss.model.shifter)
			boss.model.shifter.gates = skewed
			expect(function()
				Contract.checkShift(boss)
			end).toThrow()
		end
	)

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

	it("keeps the SVJ's driver at Driving.DRIVER_SCALE with Config/DriverArms' arm lengths", function()
		local svj = Catalog.cars.SVJ
		expect(Contract.driverScale(svj)).toBe(Driving.DRIVER_SCALE)
		local upper, lower = Contract.armLengths(svj)
		expect(upper).toBe(DriverArms.UPPER_LENGTH)
		expect(lower).toBe(DriverArms.LOWER_LENGTH)
	end)

	it("gives a car its own driver scale and arm lengths, and refuses unusable ones", function()
		local own = Contract.define(svjWith(function(entry)
			entry.driver.scale = 1.15
			entry.driver.arms = { upper = 1.25, lower = 1.13 }
		end))
		expect(Contract.driverScale(own)).toBe(1.15)
		local upper, lower = Contract.armLengths(own)
		expect(upper).toBe(1.25)
		expect(lower).toBe(1.13)
		expect(function()
			Contract.define(svjWith(function(entry)
				entry.driver.scale = 0
			end))
		end).toThrow()
		expect(function()
			Contract.define(svjWith(function(entry)
				entry.driver.arms = { upper = 1.25, lower = -1 }
			end))
		end).toThrow()
	end)

	it("finds the SVJ's footwell on its binding's pedal hinges", function()
		local svj = Catalog.cars.SVJ
		expect(#Contract.footwellMismatches(svj.model, svj.driver.footwell)).toBe(0)
	end)

	it("refuses a footwell whose hinge, axis or signed travel disagrees with the binding", function()
		-- A pedal hinge 3 cm off the binding's pivot.
		expect(function()
			Contract.define(svjWith(function(entry)
				entry.driver.footwell.throttle.hinge.z += 0.03
			end))
		end).toThrow()
		-- The binding turning a pedal about the car's left, so its weld turns against the foot.
		expect(function()
			Contract.define(svjWith(function(entry)
				entry.model.pedals[2].axis = { forward = 0, right = -1, up = 0 }
			end))
		end).toThrow()
		-- A binding that presses the throttle the other way from the footwell.
		expect(function()
			Contract.define(svjWith(function(entry)
				entry.model.pedals[1].travel = -entry.driver.footwell.throttle.travel
			end))
		end).toThrow()
		-- The same travel on both sides is accepted.
		local same = Contract.define(svjWith(function(entry)
			entry.model.pedals[1].travel = entry.driver.footwell.throttle.travel
		end))
		expect(#Contract.footwellMismatches(same.model, same.driver.footwell)).toBe(0)
	end)
	it("checks a footwell's clutch as it checks the throttle and the brake", function()
		-- A clutch on the brake's hinge, which the binding also has to hinge.
		local function withClutch(entry: any, bound: boolean)
			local clutch = table.clone(entry.driver.footwell.brake)
			clutch.part = "Pedal_Clutch"
			clutch.hangs = true
			entry.driver.footwell.clutch = clutch
			if bound then
				local pedal = table.clone(entry.model.pedals[2])
				pedal.part = "Pedal_Clutch"
				table.insert(entry.model.pedals, pedal)
			end
			return clutch
		end
		expect(function()
			Contract.define(svjWith(function(entry)
				withClutch(entry, false)
			end))
		end).toThrow()
		local accepted = Contract.define(svjWith(function(entry)
			withClutch(entry, true)
		end))
		expect(accepted.driver.footwell.clutch ~= nil).toBe(true)
		expect(#Contract.footwellMismatches(accepted.model, accepted.driver.footwell)).toBe(0)
		expect(#Contract.footwellPedals(accepted.driver.footwell)).toBe(3)
		expect(function()
			Contract.define(svjWith(function(entry)
				local clutch = withClutch(entry, true)
				clutch.hinge = { x = clutch.hinge.x, y = clutch.hinge.y, z = clutch.hinge.z + 0.03 }
			end))
		end).toThrow()
		expect(#Contract.footwellPedals(Catalog.cars.SVJ.driver.footwell)).toBe(2)
	end)

	it("asks a throttle or a clutch hung from above to be marked hangs", function()
		local function flagged(footwell: any, part: string): boolean
			for _, problem in Contract.footwellMismatches(Catalog.cars.SVJ.model, footwell) do
				if string.find(problem, `{part} hangs from above`, 1, true) then
					return true
				end
			end
			return false
		end
		local svj = Catalog.cars.SVJ.driver.footwell
		expect(flagged(svj, "Pedal_Throttle")).toBe(false)
		local footwell = table.clone(svj)
		local hungThrottle = table.clone(svj.brake)
		hungThrottle.part = "Pedal_Throttle"
		footwell.throttle = hungThrottle
		expect(flagged(footwell, "Pedal_Throttle")).toBe(true)
		hungThrottle.hangs = true
		expect(flagged(footwell, "Pedal_Throttle")).toBe(false)
		local clutch = table.clone(svj.brake)
		clutch.part = "Pedal_Clutch"
		footwell.clutch = clutch
		expect(flagged(footwell, "Pedal_Clutch")).toBe(true)
		clutch.hangs = true
		expect(flagged(footwell, "Pedal_Clutch")).toBe(false)
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
	local PIT = { limitKmh = 60, armFromGear = 2, armToGear = 2, armBelowKmh = 60, band = 3, hazards = false }
	local WIPER = { speeds = { 1.4, 0.9 }, afterWash = 3 }

	it("accepts a pit limiter, a wiper and display pages that make sense", function()
		local entry = Contract.define(svjWith(function(entry)
			entry.switches.pitLimiter = table.clone(PIT)
			entry.switches.wiper = table.clone(WIPER)
			entry.switches.displayPages = 3
			entry.switches.radio = true
		end))
		expect(Contract.features(entry).radio).toBe(true)
		expect(Contract.features(entry).pitLimiter).toBe(true)
		expect(Contract.features(entry).wiper).toBe(true)
		expect(Contract.features(entry).displayPages).toBe(true)
	end)

	it("accepts a pit limiter that arms in any forward gear at any speed", function()
		local entry = Contract.define(svjWith(function(entry)
			entry.switches.pitLimiter = { limitKmh = 60, armFromGear = 1, band = 3, hazards = true }
		end))
		expect(Contract.features(entry).pitLimiter).toBe(true)
	end)

	it("refuses a pit limiter with no band, no forward arming gear, or arming above its limit", function()
		local changes = {
			{ band = 0 },
			{ limitKmh = 0 },
			{ armBelowKmh = 80 },
			{ armFromGear = 0 },
			{ armFromGear = 1.5 },
			{ armToGear = 1 },
		}
		for _, change in changes do
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

	it("refuses a wiper with no speed, a zero wipe time, speeds out of order, or a part wipe", function()
		local changes = {
			{ speeds = {} },
			{ speeds = { 1.4, 0 } },
			{ speeds = { 0.9, 1.4 } },
			{ afterWash = 1.5 },
			{ afterWash = -1 },
		}
		for _, change in changes do
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
		expect(features.cabinLight).toBe(true)
		expect(
			features.pitLimiter
				or features.wiper
				or features.rainLight
				or features.displayPages
				or features.radio
		).toBe(false)
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

	it("refuses a field with no slot or pill on its page, or a lamp with no lens", function()
		local function withField(index: number, field: any): (any) -> ()
			return function(entry)
				local pages = table.clone(entry.binnacle.pages)
				local page = table.clone(pages[index])
				page.fields = table.clone(page.fields)
				table.insert(page.fields, field)
				pages[index] = page
				entry.binnacle.pages = pages
			end
		end
		local breaks: { (any) -> () } = {
			withField(1, { label = "BOOST", reading = "none" }),
			withField(2, { label = "ABS FAIL", reading = "none", pill = { OFF = { r = 0, g = 0, b = 0 } } }),
			function(entry)
				entry.binnacle.lenses = { "ShiftLight_1" }
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

describe("Car contract: flames", function()
	local function chances(lift: number, downshift: number, upshift: number)
		return { Lift = lift, Downshift = downshift, Upshift = upshift }
	end

	local function flames(): any
		return {
			chance = { Strada = chances(0, 0.2, 0), Sport = chances(0.3, 0.6, 0.4), Corsa = chances(1, 1, 1) },
			minStrength = 0.25,
			fireballFrom = 0.75,
			rise = 0,
			dayShare = 0.35,
		}
	end

	it("accepts a car without flames of its own, and flames for each of its drive modes", function()
		expect(Catalog.cars.SVJ.flames).toBe(nil)
		local entry = Contract.define(svjWith(function(entry)
			entry.flames = flames()
		end))
		expect(entry.flames and entry.flames.chance.Corsa.Downshift).toBe(1)
	end)

	it("refuses flames that leave a drive mode out or name one the car does not have", function()
		expect(function()
			Contract.define(svjWith(function(entry)
				entry.flames = flames()
				entry.flames.chance.Sport = nil
			end))
		end).toThrow()
		expect(function()
			Contract.define(svjWith(function(entry)
				entry.flames = flames()
				entry.flames.chance.OFF = chances(1, 1, 1)
			end))
		end).toThrow()
	end)

	it("refuses a chance, a floor, a fireball threshold or a day share outside 0 to 1", function()
		local breaks: { (any) -> () } = {
			function(set)
				set.chance.Corsa.Upshift = 1.2
			end,
			function(set)
				set.chance.Strada.Lift = -0.1
			end,
			function(set)
				set.minStrength = 1.5
			end,
			function(set)
				set.fireballFrom = -0.2
			end,
			function(set)
				set.dayShare = 2
			end,
		}
		for _, change in breaks do
			expect(function()
				Contract.define(svjWith(function(entry)
					local set = flames()
					change(set)
					entry.flames = set
				end))
			end).toThrow()
		end
	end)
end)

describe("Car contract: loop regions", function()
	local SHARED = "rbxassetid://1"

	-- Every loop of the SVJ's pack in one file, each with its own region, then `change`.
	local function packed(change: ((any) -> ())?): Contract.Entry
		return svjWith(function(entry)
			local pack = entry.audio
			local from = 0
			local function place(loop: any, seconds: number)
				loop.soundId = SHARED
				loop.region = { from = from, to = from + seconds }
				from += seconds
			end
			for _, layer in pack.engineLayers do
				place(layer, 5)
			end
			place(pack.limiter, 2)
			place(pack.far, 3)
			if change then
				change(pack)
			end
		end)
	end

	it("accepts loops that share one file through regions that do not overlap", function()
		local entry = Contract.define(packed())
		local regions = {}
		for _, layer in entry.audio.engineLayers do
			table.insert(regions, layer.region and layer.region.from)
		end
		expect(table.concat(regions, ",")).toBe("0,5,10")
		expect(entry.audio.far.region and entry.audio.far.region.to).toBe(20)
	end)

	it("accepts a loop alone in its file with a region, and the catalog's packs without any", function()
		Contract.define(svjWith(function(entry)
			entry.audio.engineLayers[2].region = { from = 0.5, to = 4 }
		end))
		for _, entry in Catalog.cars do
			Contract.checkLoopRegions(entry.audio)
		end
	end)

	it("refuses a loop that shares a file without a region of its own", function()
		expect(function()
			Contract.define(packed(function(pack)
				pack.engineLayers[3].region = nil
			end))
		end).toThrow()
		expect(function()
			Contract.define(packed(function(pack)
				pack.limiter.region = nil
			end))
		end).toThrow()
	end)

	it("refuses two loops whose regions overlap in their file", function()
		expect(function()
			Contract.define(packed(function(pack)
				pack.engineLayers[2].region = { from = 4.9, to = 10 }
			end))
		end).toThrow()
		expect(function()
			Contract.define(packed(function(pack)
				pack.far.region = { from = 1, to = 2 }
			end))
		end).toThrow()
	end)

	it("refuses a region that does not run forward from 0 or later", function()
		expect(function()
			Contract.define(packed(function(pack)
				pack.engineLayers[1].region = { from = 0, to = 0 }
			end))
		end).toThrow()
		expect(function()
			Contract.define(svjWith(function(entry)
				entry.audio.far.region = { from = -1, to = 2 }
			end))
		end).toThrow()
	end)
end)
