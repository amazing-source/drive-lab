--!strict
--[[
	The simulated readings against what the sources say (Ford's 2012 Boss 302 supplement: 80 to
	100 psi and more is normal on a cold start, the coolant needle does not sit at 180 °F once
	stabilised) and against the estimated bands the Boss's engine was tuned to (Config/Cars/Boss302/
	Gauges): no source gives warm-up times or a warm oil pressure.
]]
local Boss302Gauges = require("../src/shared/Config/Cars/Boss302/Gauges")
local EngineGauges = require("../src/shared/Rules/EngineGauges")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local ENGINE = Boss302Gauges.engine
local KPA_PER_PSI = 6.894757

local function fahrenheit(celsius: number): number
	return celsius * 9 / 5 + 32
end

-- A fresh engine driven at `power` W and `kmh` for `seconds` at `fps`; the seconds it took the
-- coolant to reach 80 °C, and the hottest it got.
local function drive(
	power: number,
	kmh: number,
	seconds: number,
	fps: number
): (EngineGauges.State, number?, number)
	local state = EngineGauges.new(ENGINE, 0)
	local warm: number? = nil
	local hottest = state.coolant
	local dt = 1 / fps
	for frame = 1, math.round(seconds * fps) do
		EngineGauges.step(state, ENGINE, { running = true, power = power, speedKmh = kmh }, dt)
		hottest = math.max(hottest, state.coolant)
		if warm == nil and state.coolant >= 80 then
			warm = frame * dt
		end
	end
	return state, warm, hottest
end

describe("Simulated engine readings", function()
	it("starts cold at the air's temperature, with the start's fuel", function()
		local state = EngineGauges.new(ENGINE, 1000)
		expect(state.coolant).toBe(ENGINE.ambient)
		expect(state.oil).toBe(ENGINE.ambient)
		expect(state.fuel).toBeNear(ENGINE.tankLitres * ENGINE.startFuel, 1e-9)
		expect(EngineGauges.miles(state.odometer)).toBeNear(1000, 1e-9)
		expect(state.trip).toBe(0)
	end)

	it("burns fuel for the engine's power, idle flow at least, none while off", function()
		expect(EngineGauges.fuelFlow(ENGINE, false, 100e3)).toBe(0)
		expect(EngineGauges.fuelFlow(ENGINE, true, 0)).toBe(ENGINE.idleFlow)
		expect(EngineGauges.fuelFlow(ENGINE, true, 200e3)).toBeNear(ENGINE.bsfc * 200e3, 1e-12)
		local state = EngineGauges.new(ENGINE, 0)
		local before = state.fuel
		EngineGauges.step(state, ENGINE, { running = true, power = ENGINE.fullPower, speedKmh = 150 }, 60)
		-- EST band: a minute flat out burns 2 to 3 litres, a few per cent of the tank, so the needle
		-- moves within a session.
		local burned = before - state.fuel
		expect(burned > 2 and burned < 3 and "2 to 3 L").toBe("2 to 3 L")
	end)

	it("never runs dry: the fuel stops at its reserve", function()
		local state = EngineGauges.new(ENGINE, 0)
		EngineGauges.step(state, ENGINE, { running = true, power = ENGINE.fullPower, speedKmh = 200 }, 7200)
		expect(state.fuel).toBe(ENGINE.reserveLitres)
		expect(EngineGauges.fuelShare(state, ENGINE) > 0 and "above empty").toBe("above empty")
	end)

	it("warms in minutes, slower at idle than on the move (EST bands)", function()
		local _, idle = drive(0, 0, 1800, 10)
		local _, cruise = drive(20e3, 100, 1800, 10)
		local idleSeconds, cruiseSeconds = assert(idle, "warms at idle"), assert(cruise, "warms cruising")
		expect(idleSeconds > 600 and idleSeconds < 1200 and "10 to 20 min").toBe("10 to 20 min")
		expect(cruiseSeconds > 120 and cruiseSeconds < 480 and "2 to 8 min").toBe("2 to 8 min")
	end)

	it("settles above 180 °F once warm, and runs hotter on a track without boiling", function()
		local cruise = drive(20e3, 100, 3600, 10)
		-- Ford: the needle does not point at 180 °F (12 o'clock) for stabilized driving.
		expect(fahrenheit(cruise.coolant) > 185 and fahrenheit(cruise.coolant) < 207 and "warm").toBe("warm")
		local track, _, hottest = drive(130e3, 150, 3600, 10)
		expect(track.coolant > cruise.coolant + 3 and "hotter on a track").toBe("hotter on a track")
		expect(hottest < 115 and "under 115 °C").toBe("under 115 °C")
		expect(track.oil > track.coolant and "oil above the coolant under load").toBe(
			"oil above the coolant under load"
		)
	end)

	it("integrates the same at 30 and 240 frames a second", function()
		for _, seconds in { 60, 300, 900 } do
			local slow = drive(60e3, 120, seconds, 30)
			local fast = drive(60e3, 120, seconds, 240)
			expect(slow.coolant).toBeNear(fast.coolant, 0.3)
			expect(slow.oil).toBeNear(fast.oil, 0.3)
			expect(slow.fuel).toBeNear(fast.fuel, 0.01)
			expect(slow.trip).toBeNear(fast.trip, 1e-6)
		end
	end)

	it("takes a long frame in short steps, as many short frames would", function()
		-- Hot at idle with the fan on: the coolant falls fast, where one long step would overshoot.
		local function hot(): EngineGauges.State
			local state = EngineGauges.new(ENGINE, 0)
			state.coolant, state.oil = 105, 110
			return state
		end
		local idle = { running = true, power = 0, speedKmh = 0 }
		local once, often = hot(), hot()
		EngineGauges.step(once, ENGINE, idle, 30)
		for _ = 1, 300 do
			EngineGauges.step(often, ENGINE, idle, 0.1)
		end
		expect(once.coolant).toBeNear(often.coolant, 0.05)
		expect(once.oil).toBeNear(often.oil, 0.05)
	end)

	it("cools toward the air while off", function()
		local state = drive(60e3, 120, 1800, 10)
		local hot = state.coolant
		EngineGauges.coolOff(state, ENGINE, ENGINE.coolDown)
		expect(state.coolant - ENGINE.ambient).toBeNear((hot - ENGINE.ambient) * math.exp(-1), 1e-6)
		EngineGauges.coolOff(state, ENGINE, -5)
		expect(state.coolant - ENGINE.ambient).toBeNear((hot - ENGINE.ambient) * math.exp(-1), 1e-6)
	end)

	it("reads high oil pressure cold, lower warm, rising with the revs to its relief", function()
		local function psi(rpm: number, oil: number): number
			return EngineGauges.oilPressure(ENGINE, rpm, oil) / KPA_PER_PSI
		end
		expect(psi(0, 20)).toBe(0)
		-- Documented: 80 to 100 psi, and more, on a cold start.
		expect(psi(700, 20) >= 80 and psi(700, 20) <= 110 and "80 to 110 psi").toBe("80 to 110 psi")
		expect(psi(3000, 20) > 100 and "past the dial's 100").toBe("past the dial's 100")
		-- EST: about 25 psi at a warm idle.
		expect(psi(700, 100) > 20 and psi(700, 100) < 35 and "20 to 35 psi").toBe("20 to 35 psi")
		local previous = 0
		for rpm = 500, 7500, 500 do
			local now = psi(rpm, 100)
			expect(now > previous and "rising").toBe("rising")
			previous = now
		end
		expect(previous <= ENGINE.oilPressure.hot.relief / KPA_PER_PSI and "under relief").toBe(
			"under relief"
		)
		expect(psi(2000, 60) < psi(2000, 20) and psi(2000, 60) > psi(2000, 100) and "thinner warm").toBe(
			"thinner warm"
		)
	end)

	it("opens the thermostat across its band only", function()
		local valve = ENGINE.thermostat
		expect(EngineGauges.thermostat(ENGINE, valve.opens - 5)).toBe(0)
		expect(EngineGauges.thermostat(ENGINE, (valve.opens + valve.open) / 2)).toBeNear(0.5, 1e-9)
		expect(EngineGauges.thermostat(ENGINE, valve.open + 5)).toBe(1)
	end)
end)
