--!strict
local CarAudio = require("../src/shared/Config/CarAudio")
local CarEntry = require("../src/shared/Config/CarEntry")
local ControlSounds = require("../src/shared/Rules/ControlSounds")
local DR458 = require("../src/shared/Config/Cars/DR458")
local EngineSound = require("../src/shared/Rules/EngineSound")
local SVJ = require("../src/shared/Config/Cars/SVJ")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local STARTUP: CarEntry.Startup = DR458.startup
local DT = 1 / 60

-- Every press a watch hears over `seconds` from server time `from`, its engine on since `engineAt`.
local function listen(
	watch: ControlSounds.Watch,
	running: boolean,
	engineAt: number,
	from: number,
	seconds: number
): { string }
	local heard = {}
	for frame = 0, math.round(seconds / DT) do
		for _, name in ControlSounds.watchStartup(watch, STARTUP, running, engineAt, from + frame * DT) do
			table.insert(heard, name)
		end
	end
	return heard
end

local function everyPress(): { string }
	local all = {}
	for _, move in STARTUP.moves do
		table.insert(all, move.control)
	end
	table.insert(all, "ENGINE_START")
	return all
end

describe("Control sounds", function()
	it("levels a sound against the idle loop: 0 dB is the idle level, -20 dB a tenth of it", function()
		expect(ControlSounds.volume(0.5, { soundId = "", db = 0 })).toBeNear(0.5, 1e-12)
		expect(ControlSounds.volume(0.5, { soundId = "", db = -20 })).toBeNear(0.05, 1e-12)
	end)

	it("takes the idle level from the pack's lowest layer, wherever it is listed", function()
		for _, pack in { SVJ.audio, DR458.audio } do
			local layers = table.clone(pack.engineLayers)
			local lowest = layers[1]
			for _, layer in layers do
				if layer.rpm < lowest.rpm then
					lowest = layer
				end
			end
			local expected = pack.engineVolume
				* lowest.volume
				* EngineSound.loudness(pack.engineTuning, lowest.rpm)
			expect(CarAudio.idleLevel(pack)).toBeNear(expected, 1e-12)
			-- Listed last instead of first, the idle layer still sets the level.
			table.remove(layers, table.find(layers, lowest))
			table.insert(layers, lowest)
			local reordered = table.clone(pack) :: any
			reordered.engineLayers = layers
			expect(CarAudio.idleLevel(reordered)).toBeNear(expected, 1e-12)
		end
	end)

	it("presses the DR458's start-up controls as the hand reaches each, then START", function()
		local presses = ControlSounds.startupPresses(STARTUP, -math.huge, STARTUP.drivableAt)
		expect(table.concat(presses, ",")).toBe(table.concat(everyPress(), ","))
		expect(#ControlSounds.startupPresses(STARTUP, nil, STARTUP.drivableAt)).toBe(0)
		expect(#ControlSounds.startupPresses(STARTUP, STARTUP.drivableAt, STARTUP.drivableAt + 5)).toBe(0)
	end)

	it("hears a start watched from the car's engine off once each, in order, START at its press", function()
		local watch = ControlSounds.newWatch()
		expect(#listen(watch, false, 0, 100, 1)).toBe(0)
		local heard = listen(watch, true, 101, 101, STARTUP.drivableAt + 1)
		expect(table.concat(heard, ",")).toBe(table.concat(everyPress(), ","))
	end)

	it("never replays a start already under way when the car is first seen (a late join)", function()
		local watch = ControlSounds.newWatch()
		local engineAt = 50
		local seenAt = engineAt + STARTUP.pressAt + 0.5
		local heard = listen(watch, true, engineAt, seenAt, 10)
		expect(#heard).toBe(0)
		-- First seen before START: only START, which happens while it is watched, plays.
		local early = ControlSounds.newWatch()
		local onlyStart = listen(early, true, engineAt, engineAt + STARTUP.pressAt - 0.2, 1)
		expect(table.concat(onlyStart, ",")).toBe("ENGINE_START")
	end)

	it("hears a fresh start from its beginning when the engine is started again while watched", function()
		local watch = ControlSounds.newWatch()
		listen(watch, true, 10, 30, 1)
		local heard = listen(watch, true, 40, 40, STARTUP.drivableAt + 1)
		expect(#heard).toBe(#everyPress())
	end)

	it("opens and closes the radio on the edges of the push-to-talk only", function()
		expect(ControlSounds.radioEdge(false, true)).toBe("Press")
		expect(ControlSounds.radioEdge(true, false)).toBe("Release")
		expect(ControlSounds.radioEdge(true, true)).toBe(nil)
		expect(ControlSounds.radioEdge(false, false)).toBe(nil)
	end)

	it("runs the wiper motor while the blade moves or the switch is on, at its step's speed", function()
		local rates = { 0.9, 1.25 }
		expect(ControlSounds.wiperRate(rates, 0, 0)).toBe(nil)
		expect(ControlSounds.wiperRate(rates, 0, 0.3)).toBe(0.9)
		expect(ControlSounds.wiperRate(rates, 1, 0)).toBe(0.9)
		expect(ControlSounds.wiperRate(rates, 2, 0.7)).toBe(1.25)
		expect(ControlSounds.wiperRate(rates, 3, 0.7)).toBe(1.25)
	end)
end)
