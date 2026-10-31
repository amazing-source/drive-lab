--!strict
local CarAudio = require("../src/shared/Config/CarAudio")
local Catalog = require("../src/shared/Config/Cars/Catalog")
local Contract = require("../src/shared/Config/Cars/Contract")
local DR458 = require("../src/shared/Config/Cars/DR458/Audio")
local DR458Physics = require("../src/shared/Config/Cars/DR458/Physics")
local DR458Startup = require("../src/shared/Config/Cars/DR458/Startup")
local EngineSound = require("../src/shared/Rules/EngineSound")
local SVJ = require("../src/shared/Config/Cars/SVJ/Audio")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

-- The length of each uploaded events.ogg, seconds (manifest.json beside the files).
local SVJ_EVENTS_LENGTH = 18.6001
local DR458_EVENTS_LENGTH = 14.6917

-- Each car's pack with the length of its events file and of the file its pops are cut from.
local PACKS: { { name: string, pack: CarAudio.Pack, eventsLength: number, popsLength: number } } = {
	{ name = "SVJ", pack = SVJ, eventsLength = SVJ_EVENTS_LENGTH, popsLength = SVJ_EVENTS_LENGTH },
	{ name = "DR458", pack = DR458, eventsLength = DR458_EVENTS_LENGTH, popsLength = SVJ_EVENTS_LENGTH },
}

-- The DR458's own start-up sound's length, seconds (its Sound.TimeLength, read in Studio).
local DR458_STARTUP_LENGTH = 3.9231

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
			expect(uploaded(CarAudio.popsSoundId(pack))).toBeTruthy()
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

		it(
			`{car.name}: keeps every one-shot region inside the file it is cut from, in order and apart`,
			function()
				local function inOrder(regions: { CarAudio.Region }, from: number, length: number): number
					local previousEnd = from
					for _, region in regions do
						expect(region.from >= previousEnd).toBeTruthy()
						expect(region.to > region.from).toBeTruthy()
						previousEnd = region.to
					end
					expect(previousEnd <= length).toBeTruthy()
					return previousEnd
				end
				local eventsEnd = inOrder({ Pack.startup.region, Pack.gear.region }, 0, car.eventsLength)
				local ownFile = CarAudio.popsSoundId(Pack) == Pack.eventsSoundId
				inOrder(Pack.pops.regions, if ownFile then eventsEnd else 0, car.popsLength)
				expect(Pack.startup.handOver < Pack.startup.region.to - Pack.startup.region.from).toBeTruthy()
			end
		)

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

	it("DR458: keys every pop chance by exactly the car's own modes", function()
		local triggers = DR458.popTriggers
		for _, chances in { triggers.liftChance, triggers.upshiftChance, triggers.downshiftChance } do
			local count = 0
			for mode in chances do
				expect(table.find(DR458Physics.modeOrder, mode) ~= nil).toBeTruthy()
				count += 1
			end
			expect(count).toBe(#DR458Physics.modeOrder)
		end
	end)

	it("SVJ: cuts its pops from its own events file", function()
		expect(SVJ.pops.soundId).toBe(nil)
		expect(CarAudio.popsSoundId(SVJ)).toBe(SVJ.eventsSoundId)
	end)

	it("DR458: plays the SVJ's pops, out of the SVJ's events file at the SVJ's level and speed", function()
		expect(CarAudio.popsSoundId(DR458)).toBe(SVJ.eventsSoundId)
		expect(#DR458.pops.regions).toBe(#SVJ.pops.regions)
		for index, region in SVJ.pops.regions do
			expect(DR458.pops.regions[index].from).toBe(region.from)
			expect(DR458.pops.regions[index].to).toBe(region.to)
		end
		for _, pair in { { DR458.pops.volume, SVJ.pops.volume }, { DR458.pops.speed, SVJ.pops.speed } } do
			expect(pair[1].from).toBe(pair[2].from)
			expect(pair[1].to).toBe(pair[2].to)
		end
	end)

	it("DR458: pops on the SVJ's Corsa timing in every manettino position", function()
		local mine, svj = DR458.popTriggers, SVJ.popTriggers
		for _, mode in DR458Physics.modeOrder do
			expect(mine.liftChance[mode]).toBe(svj.liftChance.Corsa)
			expect(mine.upshiftChance[mode]).toBe(svj.upshiftChance.Corsa)
			expect(mine.downshiftChance[mode]).toBe(svj.downshiftChance.Corsa)
			expect(mine.liftChance[mode]).toBe(1)
			expect(mine.downshiftChance[mode]).toBe(1)
			expect(mine.upshiftChance[mode]).toBe(1)
		end
		expect(mine.upshiftMinRpm).toBe(svj.upshiftMinRpm)
		expect(mine.upshiftMinThrottle).toBe(svj.upshiftMinThrottle)
		expect(mine.minRpm).toBe(svj.minRpm)
		expect(mine.closedThrottle).toBe(svj.closedThrottle)
		local ranges = {
			{ mine.liftTrain, svj.liftTrain },
			{ mine.downshiftTrain, svj.downshiftTrain },
			{ mine.gap, svj.gap },
		}
		for _, pair in ranges do
			expect(pair[1].from).toBe(pair[2].from)
			expect(pair[1].to).toBe(pair[2].to)
		end
		expect(mine.upshiftMinRpm).toBe(4000)
	end)

	it("DR458: keeps its start-up timing to its own start-up sound", function()
		Contract.checkStartupSound(DR458Startup, DR458)
	end)

	it("DR458: hands its own start-up sound over before the recording ends", function()
		local own = DR458.startup.sound
		expect(own ~= nil).toBeTruthy()
		expect((own :: CarAudio.StartupSound).to <= DR458_STARTUP_LENGTH).toBeTruthy()
	end)

	it("DR458: settles the start-up's revs at the car's idle", function()
		local values = DR458Startup.rpm.values
		expect(values[#values]).toBe(DR458Physics.engine.idleRpm)
	end)

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
			local slowest, fastest = stretch(1500, DR458Physics.engine.limiterRpm)
			expect(slowest >= 0.7).toBeTruthy()
			expect(fastest <= 1.4).toBeTruthy()
		end
	)
end)
