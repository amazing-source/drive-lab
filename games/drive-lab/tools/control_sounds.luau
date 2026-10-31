--!strict
--[[
	Prints every car's cockpit control sounds (Config/CarAudio ControlSounds) as JSON, each with how
	its loudness is measured: a one-shot by its loudest 100 ms, a loop over its whole region.
	tools/audio/measure_control_sounds.py reads it and writes the loudness fixture the specs check.

	    lune run games/drive-lab/tools/control_sounds.luau > control_sounds.json
]]
local CarAudio = require("../src/shared/Config/CarAudio")
local DR458 = require("../src/shared/Config/Cars/DR458/Audio")
local SVJ = require("../src/shared/Config/Cars/SVJ/Audio")
local serde = require("@lune/serde")

type Entry = {
	car: string,
	name: string,
	soundId: string,
	from: number,
	to: number,
	kind: "OneShot" | "Loop",
	db: number,
}

local entries: { Entry } = {}

for _, car in { { name = "SVJ", pack = SVJ }, { name = "DR458", pack = DR458 } } do
	local controls = car.pack.controls
	if controls == nil then
		continue
	end

	local function add(name: string, sound: CarAudio.ControlSound, kind: "OneShot" | "Loop")
		local region = sound.region
		assert(region, `{car.name}'s {name} plays a region of its file`)
		table.insert(entries, {
			car = car.name,
			name = name,
			soundId = sound.soundId,
			from = region.from,
			to = region.to,
			kind = kind,
			db = sound.db,
		})
	end

	local names = {}
	for name in controls.press do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		add(name, controls.press[name], "OneShot")
	end
	local radio = controls.radio
	if radio then
		add("radio.press", radio.press, "OneShot")
		add("radio.hiss", radio.hiss, "Loop")
		add("radio.release", radio.release, "OneShot")
	end
	if controls.wiperMotor then
		add("wiperMotor", controls.wiperMotor, "Loop")
	end
	if controls.washerPump then
		add("washerPump", controls.washerPump, "Loop")
	end
end
print(serde.encode("json", entries))
