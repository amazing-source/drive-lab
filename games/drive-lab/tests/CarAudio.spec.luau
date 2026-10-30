--!strict
local Pack = require("../src/shared/Config/Cars/SVJ/Audio")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

-- Length of the uploaded events.ogg, seconds (manifest.json).
local EVENTS_LENGTH = 18.6001

local function uploaded(soundId: string): boolean
	return string.match(soundId, "^rbxassetid://%d+$") ~= nil
end

describe("CarAudio config", function()
	it("points every loop and the events file at an uploaded asset", function()
		for _, layer in Pack.engineLayers do
			expect(uploaded(layer.soundId)).toBeTruthy()
		end
		expect(uploaded(Pack.limiter.soundId)).toBeTruthy()
		expect(uploaded(Pack.far.soundId)).toBeTruthy()
		expect(uploaded(Pack.eventsSoundId)).toBeTruthy()
	end)

	it("keeps every one-shot region inside the events file, in order and apart", function()
		local regions = { Pack.startup.region, Pack.gear.region }
		for _, region in Pack.pops.regions do
			table.insert(regions, region)
		end
		local previousEnd = 0
		for _, region in regions do
			expect(region.from >= previousEnd).toBeTruthy()
			expect(region.to > region.from).toBeTruthy()
			previousEnd = region.to
		end
		expect(previousEnd <= EVENTS_LENGTH).toBeTruthy()
		expect(Pack.startup.handOver < Pack.startup.region.to - Pack.startup.region.from).toBeTruthy()
	end)

	it("hands the idle over before the next loop up, inside both loops", function()
		local idle = Pack.engineLayers[1]
		local crossover = idle.crossoverRpm
		expect(idle.load).toBe("Both")
		expect(crossover ~= nil).toBeTruthy()
		for index = 2, #Pack.engineLayers do
			local layer = Pack.engineLayers[index]
			expect(layer.rpm > idle.rpm).toBeTruthy()
			expect((crossover :: number) < layer.rpm).toBeTruthy()
		end
		expect((crossover :: number) > idle.rpm).toBeTruthy()
	end)

	it("keeps Strada the most restrained mode for every pop", function()
		local triggers = Pack.popTriggers
		for _, chance in { triggers.liftChance, triggers.upshiftChance, triggers.downshiftChance } do
			expect(chance.Strada >= 0 and chance.Strada <= chance.Sport).toBeTruthy()
			expect(chance.Sport <= chance.Corsa and chance.Corsa <= 1).toBeTruthy()
		end
	end)

	it("puts every lift the events report on the overrun, so its train can start", function()
		local triggers, events = Pack.popTriggers, Pack.events
		expect(events.liftMinRpm >= triggers.minRpm).toBeTruthy()
		expect(events.liftTo <= triggers.closedThrottle).toBeTruthy()
	end)
end)
