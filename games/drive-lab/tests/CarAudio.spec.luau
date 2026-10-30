--!strict
local CarAudio = require("../src/shared/Config/CarAudio")
local Catalog = require("../src/shared/Config/Cars/Catalog")
local DR458 = require("../src/shared/Config/Cars/DR458/Audio")
local EngineSound = require("../src/shared/Rules/EngineSound")
local SVJ = require("../src/shared/Config/Cars/SVJ/Audio")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

-- Each car's pack with the length of its events.ogg, seconds (manifest.json beside the files).
local PACKS: { { name: string, pack: CarAudio.Pack, eventsLength: number } } = {
	{ name = "SVJ", pack = SVJ, eventsLength = 18.6001 },
	{ name = "DR458", pack = DR458, eventsLength = 14.6917 },
}

local function uploaded(soundId: string): boolean
	return string.match(soundId, "^rbxassetid://%d+$") ~= nil
end

describe("CarAudio config", function()
	it("points every loop and the events file of every car the catalog rigs at an uploaded asset", function()
		for _, entry in Catalog.cars do
			local pack = entry.audio
			for _, layer in pack.engineLayers do
				expect(uploaded(layer.soundId)).toBeTruthy()
			end
			expect(uploaded(pack.limiter.soundId)).toBeTruthy()
			expect(uploaded(pack.far.soundId)).toBeTruthy()
			expect(uploaded(pack.eventsSoundId)).toBeTruthy()
		end
	end)

	for _, car in PACKS do
		local Pack = car.pack

		it(`{car.name}: points every loop and its events file at an uploaded asset`, function()
			for _, layer in Pack.engineLayers do
				expect(uploaded(layer.soundId)).toBeTruthy()
			end
			expect(uploaded(Pack.limiter.soundId)).toBeTruthy()
			expect(uploaded(Pack.far.soundId)).toBeTruthy()
			expect(uploaded(Pack.eventsSoundId)).toBeTruthy()
		end)

		it(`{car.name}: keeps every one-shot region inside the events file, in order and apart`, function()
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
			expect(previousEnd <= car.eventsLength).toBeTruthy()
			expect(Pack.startup.handOver < Pack.startup.region.to - Pack.startup.region.from).toBeTruthy()
		end)

		it(`{car.name}: hands the idle over before the next loop up, inside both loops`, function()
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

		it(`{car.name}: gives every pop a chance between 0 and 1 in every mode`, function()
			local triggers = Pack.popTriggers
			for _, chances in { triggers.liftChance, triggers.upshiftChance, triggers.downshiftChance } do
				for _, chance in chances do
					expect(chance >= 0 and chance <= 1).toBeTruthy()
				end
			end
		end)

		it(`{car.name}: puts every lift the events report on the overrun, so its train can start`, function()
			local triggers, events = Pack.popTriggers, Pack.events
			expect(events.liftMinRpm >= triggers.minRpm).toBeTruthy()
			expect(events.liftTo <= triggers.closedThrottle).toBeTruthy()
		end)
	end

	it("SVJ: keeps Strada the most restrained mode for every pop", function()
		local triggers = SVJ.popTriggers
		for _, chance in { triggers.liftChance, triggers.upshiftChance, triggers.downshiftChance } do
			expect(chance.Strada <= chance.Sport and chance.Sport <= chance.Corsa).toBeTruthy()
		end
	end)

	-- The loudest loop's playback speed over an rpm range, in both loads.
	local function stretch(from: number, to: number): (number, number)
		local layers: { EngineSound.Layer } = {}
		for _, layer in DR458.engineLayers do
			table.insert(layers, {
				rpm = layer.rpm,
				load = layer.load,
				volume = layer.volume,
				crossoverRpm = layer.crossoverRpm,
			})
		end
		local slowest, fastest = math.huge, 0
		for rpm = from, to, 10 do
			for _, onShare in { 0, 1 } do
				local mix = EngineSound.target(layers, DR458.engineTuning, rpm, onShare)
				local loudest = 1
				for index, volume in mix.volumes do
					if volume > mix.volumes[loudest] then
						loudest = index
					end
				end
				slowest = math.min(slowest, mix.speeds[loudest])
				fastest = math.max(fastest, mix.speeds[loudest])
			end
		end
		return slowest, fastest
	end

	it(
		"DR458: plays its loudest loop within x0.55 to x1.6 of its pitch through the idle's hand-over",
		function()
			local slowest, fastest = stretch(DR458.engineLayers[1].rpm, 1500)
			expect(slowest >= 0.55).toBeTruthy()
			expect(fastest <= 1.6).toBeTruthy()
		end
	)

	it(
		"DR458: plays its loudest loop within x0.7 to x1.4 of its pitch from 1,500 rpm to the limiter",
		function()
			local slowest, fastest = stretch(1500, DR458.limiter.rpm)
			expect(slowest >= 0.7).toBeTruthy()
			expect(fastest <= 1.4).toBeTruthy()
		end
	)
end)
