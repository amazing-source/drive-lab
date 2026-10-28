--!strict
--[[
	Runs the weather's sound offline through a scripted scene and prints, frame by frame, what
	Controllers/WeatherAudio would set: each loop's volume, the spray's speed, the outside and
	roof groups' volumes, the cockpit equaliser, and every thunder with its region, volume and
	speed. tools/audio/render_weather_preview.py turns it into a listening file, so the rain can be
	judged without Studio.

	    lune run games/drive-lab/tools/weather_timeline.luau [seed] > weather_timeline.json

	The scene, outside the car (the chase view): rain building from nothing to the Night rain
	preset's 0.85 over 20 s, smoothstepped as the weather's preset blend does; heavy rain and a
	thunder; then the cockpit, the car pulling away to 140 km/h on the wet road with a second
	thunder heard from inside; then back outside at speed for the spray. Same rules, same config.
	The road's wetness is scripted (the game's takes minutes to soak the road), and the two
	thunders are placed by hand; their takes, volumes and speeds come from the rules' own seeded
	rolls.
]]
local Config = require("../src/shared/Config/WeatherAudio")
local WeatherAudio = require("../src/shared/Rules/WeatherAudio")
local process = require("@lune/process")
local serde = require("@lune/serde")

local DT = 1 / 60
local LENGTH = 42
local RAIN_FROM, RAIN_SECONDS, RAIN_TOP = 1, 20, 0.85
local COCKPIT_FROM, COCKPIT_TO = 26, 37
local DRIVE_FROM, DRIVE_SECONDS, DRIVE_TOP = 27, 9, 140
local THUNDERS_AT = { 23, 29 }
math.randomseed(tonumber(process.args[1]) or 5)

local function smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- Seconds from `time` to the next scripted thunder, which replaces the rules' random gap.
local function untilScripted(time: number): number
	for _, at in THUNDERS_AT do
		if at > time - DT / 2 then
			return at - time
		end
	end
	return math.huge
end

local state = WeatherAudio.new(Config.TUNING, math.random)
local frames, thunders = {}, {}
local time = 0
for _ = 1, math.round(LENGTH / DT) do
	local rain = RAIN_TOP * smoothstep((time - RAIN_FROM) / RAIN_SECONDS)
	local speed = DRIVE_TOP * math.clamp((time - DRIVE_FROM) / DRIVE_SECONDS, 0, 1) ^ 0.7
	local scene = {
		rainIntensity = rain,
		wetness = 0.85 * smoothstep((time - RAIN_FROM - 4) / 22),
		speedKmh = speed,
		cockpit = time >= COCKPIT_FROM and time < COCKPIT_TO,
		driving = true,
	}
	if state.thunderIn ~= nil then
		state.thunderIn = untilScripted(time)
	end
	local mix = WeatherAudio.step(state, scene, DT)
	table.insert(frames, {
		t = time,
		rain = rain,
		speedKmh = speed,
		cockpit = scene.cockpit,
		rainLight = mix.rainLight,
		rainHeavy = mix.rainHeavy,
		roofLight = mix.roofLight,
		roofHeavy = mix.roofHeavy,
		spray = mix.spray,
		spraySpeed = mix.spraySpeed,
		outside = mix.outside,
		roof = mix.roof,
		midGain = mix.midGain,
		highGain = mix.highGain,
	})
	local roll = mix.thunder
	if roll then
		local region = Config.THUNDERS[roll.take]
		table.insert(thunders, {
			t = time,
			take = roll.take,
			from = region.from,
			to = region.to,
			volume = roll.volume,
			speed = roll.speed,
		})
	end
	time += DT
end

print(serde.encode("json", {
	dt = DT,
	loops = Config.LOOPS,
	thunderEqualiser = Config.THUNDER_EQUALISER,
	frames = frames,
	thunders = thunders,
}))
