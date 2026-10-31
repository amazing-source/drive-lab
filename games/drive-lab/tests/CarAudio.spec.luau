--!strict
local CarAudio = require("../src/shared/Config/CarAudio")
local Catalog = require("../src/shared/Config/Cars/Catalog")
local DR458 = require("../src/shared/Config/Cars/DR458/Audio")
local DR458Physics = require("../src/shared/Config/Cars/DR458/Physics")
local DR458Startup = require("../src/shared/Config/Cars/DR458/Startup")
local DR458Switches = require("../src/shared/Config/Cars/DR458/Switches")
local EngineSound = require("../src/shared/Rules/EngineSound")
local SVJ = require("../src/shared/Config/Cars/SVJ/Audio")
local SVJStartup = require("../src/shared/Config/Cars/SVJ/Startup")
local T = require("../../../tools/test/T")
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local describe, it, expect = T.describe, T.it, T.expect

-- The length of each uploaded events file and packed bank, seconds, by asset (manifest.json
-- beside the files).
local FILE_LENGTHS: { [string]: number } = {
	[SVJ.eventsSoundId] = 18.6001,
	[DR458.eventsSoundId] = 14.6917,
	[DR458.limiter.soundId] = 108.333,
}

local PACKS: { { name: string, pack: CarAudio.Pack } } = {
	{ name = "SVJ", pack = SVJ },
	{ name = "DR458", pack = DR458 },
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

		it(`{car.name}: keeps each one-shot inside the file it is cut from, in order and apart`, function()
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
			local eventsLength = FILE_LENGTHS[Pack.eventsSoundId]
			local popsFile = CarAudio.popsSoundId(Pack)
			local popsLength = FILE_LENGTHS[popsFile]
			assert(eventsLength and popsLength, "the length of every file its one-shots are cut from")
			local eventsEnd = inOrder({ Pack.startup.region, Pack.gear.region }, 0, eventsLength)
			inOrder(Pack.pops.regions, if popsFile == Pack.eventsSoundId then eventsEnd else 0, popsLength)
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

	it("DR458: plays the SVJ's pops, out of the SVJ's events file at the SVJ's speed", function()
		expect(CarAudio.popsSoundId(DR458)).toBe(SVJ.eventsSoundId)
		expect(#DR458.pops.regions).toBe(#SVJ.pops.regions)
		for index, region in SVJ.pops.regions do
			expect(DR458.pops.regions[index].from).toBe(region.from)
			expect(DR458.pops.regions[index].to).toBe(region.to)
		end
		expect(DR458.pops.speed.from).toBe(SVJ.pops.speed.from)
		expect(DR458.pops.speed.to).toBe(SVJ.pops.speed.to)
	end)

	it("DR458: plays them 4.5 dB under the SVJ's balance with its engine, in the SVJ's spread", function()
		-- A pop plays at its volume times the car's level; its engine at the car's engine volume.
		local function againstEngine(pack: CarAudio.Pack, volume: number): number
			return volume * CarAudio.carGain(pack) / pack.engineVolume
		end
		local gain = 10 ^ (-4.5 / 20)
		local levels = {
			{ DR458.pops.volume.from, SVJ.pops.volume.from },
			{ DR458.pops.volume.to, SVJ.pops.volume.to },
		}
		for _, pair in levels do
			expect(againstEngine(DR458, pair[1])).toBeNear(againstEngine(SVJ, pair[2]) * gain, 1e-9)
		end
	end)

	it("plays the SVJ at its loops' level and the DR458 8 dB over it", function()
		expect(SVJ.engineVolume).toBe(1)
		expect(CarAudio.carGain(SVJ)).toBe(1)
		expect(DR458.engineVolume).toBeNear(10 ^ (8 / 20), 1e-9)
	end)

	it("makes a car's controls, start-up, one-shots, road and tyres follow its level", function()
		local louder = table.clone(DR458) :: any
		louder.engineVolume = DR458.engineVolume * 2
		expect(CarAudio.carGain(louder) / CarAudio.carGain(DR458)).toBeNear(2, 1e-12)
		expect(CarAudio.idleLevel(louder) / CarAudio.idleLevel(DR458)).toBeNear(2, 1e-12)
	end)

	it("keeps every Sound volume each car sets within Roblox's 0 to 10", function()
		-- Roblox's engine reference, Sound.Volume: "Can be set between 0 and 10".
		local MAX_VOLUME = 10
		for _, car in PACKS do
			local pack = car.pack
			local level = pack.engineVolume
				* 10 ^ (math.max(pack.engineTuning.loudDb, pack.engineTuning.quietDb) / 20)
			local loudest = 0
			for _, layer in pack.engineLayers do
				loudest = math.max(loudest, layer.volume * level)
			end
			local idle = CarAudio.idleLevel(pack)
			local own = pack.startup.sound
			local volumes = {
				loudest,
				pack.limiter.volume * level,
				pack.far.volume * level,
				pack.pops.volume.to * CarAudio.carGain(pack),
				pack.gear.volume * CarAudio.carGain(pack),
				if own then idle * own.volume else idle * 10 ^ (pack.startup.boostDb / 20),
			}
			local controls = pack.controls
			if controls then
				local sounds: { CarAudio.ControlSound } = {}
				for _, sound in controls.press do
					table.insert(sounds, sound)
				end
				if controls.radio then
					table.insert(sounds, controls.radio.press)
					table.insert(sounds, controls.radio.hiss)
					table.insert(sounds, controls.radio.release)
				end
				if controls.wiperMotor then
					table.insert(sounds, controls.wiperMotor)
				end
				if controls.washerPump then
					table.insert(sounds, controls.washerPump)
				end
				for _, sound in sounds do
					table.insert(volumes, idle * 10 ^ (sound.db / 20))
				end
			end
			for _, volume in volumes do
				expect(volume >= 0 and volume <= MAX_VOLUME).toBeTruthy()
			end
		end
	end)

	it("plays the DR458's start-up 12 dB over its idle, the SVJ's 2 dB under its match (3.4)", function()
		expect(DR458.startup.boostDb).toBe(12)
		expect(SVJ.startup.boostDb).toBe(3.4)
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

	it("DR458: plays its start-up from its own events file, with no outside recording", function()
		expect(DR458.startup.sound).toBe(nil)
		expect(DR458.startup.region.from).toBe(0)
	end)

	it(
		"DR458: holds the starter's revs until its start-up catches, and shows the idle by the hand-over",
		function()
			local times, values = DR458Startup.rpm.times, DR458Startup.rpm.values
			local cranking = 1
			while values[cranking + 1] == values[1] do
				cranking += 1
			end
			expect(times[cranking] <= DR458Startup.catchAfter).toBeTruthy()
			expect(times[cranking + 1] >= DR458Startup.catchAfter).toBeTruthy()
			expect(times[#times] <= DR458.startup.handOver).toBeTruthy()
		end
	)

	it("DR458: loops every engine layer and its limiter inside its packed bank", function()
		local length = FILE_LENGTHS[DR458.limiter.soundId]
		local regions = { DR458.limiter.region }
		for _, layer in DR458.engineLayers do
			expect(layer.soundId).toBe(DR458.limiter.soundId)
			table.insert(regions, layer.region)
		end
		for _, region in regions do
			assert(region, "every loop of the packed bank has its region")
			expect(region.from >= 0 and region.to <= length).toBeTruthy()
		end
	end)

	it("DR458: settles the start-up's revs at the car's idle", function()
		local values = DR458Startup.rpm.values
		expect(values[#values]).toBe(DR458Physics.engine.idleRpm)
	end)

	-- A car's control sounds, each with its name, for the checks below.
	local function controlSounds(pack: CarAudio.Pack): { { name: string, sound: CarAudio.ControlSound } }
		local controls = pack.controls
		assert(controls, "the car has its control sounds")
		local list = {}
		for name, sound in controls.press do
			table.insert(list, { name = name, sound = sound })
		end
		local radio = controls.radio
		if radio then
			table.insert(list, { name = "radio.press", sound = radio.press })
			table.insert(list, { name = "radio.hiss", sound = radio.hiss })
			table.insert(list, { name = "radio.release", sound = radio.release })
		end
		if controls.wiperMotor then
			table.insert(list, { name = "wiperMotor", sound = controls.wiperMotor })
		end
		if controls.washerPump then
			table.insert(list, { name = "washerPump", sound = controls.washerPump })
		end
		return list
	end

	it("DR458: has a sound for each cockpit control the owner listed, and no other", function()
		local controls = DR458.controls
		assert(controls, "the DR458 has its control sounds")
		local listed = {
			"DISPLAY_PAGE",
			"DRIVING_MODE",
			"ENGINE_START",
			"HEADLIGHTS",
			"HIGH_BEAM",
			"PIT_LIMITER",
			"PanelGuard_Ignition",
			"PanelSwitch_Ignition",
			"RAIN_LIGHT",
			"TunnelKey_Master",
			"WASHER",
			"WIPER",
		}
		local names = {}
		for name in controls.press do
			table.insert(names, name)
		end
		table.sort(names)
		expect(table.concat(names, ",")).toBe(table.concat(listed, ","))
		expect(controls.radio ~= nil and controls.wiperMotor ~= nil and controls.washerPump ~= nil).toBeTruthy()
		for _, entry in controlSounds(DR458) do
			expect(uploaded(entry.sound.soundId)).toBeTruthy()
		end
	end)

	it("SVJ: has a sound for its start-up's flap and START, and no other", function()
		local controls = SVJ.controls
		assert(controls, "the SVJ has its start-up's sounds")
		local names = {}
		for name in controls.press do
			table.insert(names, name)
		end
		table.sort(names)
		expect(table.concat(names, ",")).toBe("ENGINE_START,StartFlap")
		expect(controls.radio == nil and controls.wiperMotor == nil and controls.washerPump == nil).toBeTruthy()
		for _, entry in controlSounds(SVJ) do
			expect(uploaded(entry.sound.soundId)).toBeTruthy()
		end
	end)

	it("gives every start-up move and the START press a sound, in each car with control sounds", function()
		for _, car in { { pack = SVJ, startup = SVJStartup }, { pack = DR458, startup = DR458Startup } } do
			local controls = car.pack.controls
			assert(controls, "the car has its control sounds")
			for _, move in car.startup.moves do
				expect(controls.press[move.control] ~= nil).toBeTruthy()
			end
			expect(controls.press.ENGINE_START ~= nil).toBeTruthy()
		end
	end)

	it("plays every car's control sounds under its idle engine, by their measured loudness", function()
		-- Each car's loops, its idle among them, are matched to this loudness.
		local LOOP_LUFS = -18
		local measured =
			serde.decode("json", fs.readFile("games/drive-lab/tests/fixtures/control_sounds.json"))
		for _, pack in { SVJ, DR458 } do
			for _, entry in controlSounds(pack) do
				local sound = entry.sound
				local region = sound.region
				assert(region, `{entry.name} plays a measured region`)
				local key = string.format("%s@%g-%g", sound.soundId, region.from, region.to)
				local lufs = measured[key]
				assert(lufs, `{entry.name}'s sound has been measured ({key})`)
				expect(lufs + sound.db - LOOP_LUFS < 0).toBeTruthy()
			end
		end
	end)

	it("DR458: plays its wiper motor at the rate that fits its recorded wipe to each wiper speed", function()
		-- Seconds one wipe of the recording lasts (tools/audio/cut_dr458_gdc.py's manifest).
		local RECORDED_WIPE = 1.42
		local controls = DR458.controls
		local motor = controls and controls.wiperMotor
		local wiper = DR458Switches.wiper
		assert(motor and wiper, "the DR458 has a wiper and its motor's sound")
		expect(#motor.rates).toBe(#wiper.speeds)
		for index, seconds in wiper.speeds do
			expect(motor.rates[index]).toBeNear(RECORDED_WIPE / seconds, 0.005)
		end
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
