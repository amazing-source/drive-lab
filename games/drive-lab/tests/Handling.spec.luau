--!strict
--[[
	Each game-feel notch on both cars through tools/HandlingScenario, driven as a keyboard or pad
	player drives: what the slide assist catches, that it leaves normal driving alone, and that the
	same runs at Realistic still slide as they did (so every bound here can fail). Bounds and their
	measurements: docs/research/14_game_handling.md.
]]
local DR458 = require("../src/shared/Config/Cars/DR458/Physics")
local DR458Assists = require("../src/shared/Config/Cars/DR458/Assists")
local GameFeel = require("../src/shared/Config/GameFeel")
local HandlingScenario = require("../tools/HandlingScenario")
local InputHelp = require("../src/shared/Config/InputHelp")
local SVJ = require("../src/shared/Config/Cars/SVJ/Physics")
local SVJAssists = require("../src/shared/Config/Cars/SVJ/Assists")
local T = require("../../../tools/test/T")

local describe, it = T.describe, T.it

type Row = { label: string, setup: HandlingScenario.Setup }

local ROWS: { Row } = {
	{ label = "SVJ Strada", setup = { car = SVJ, assists = SVJAssists, mode = "Strada" } },
	{
		label = "SVJ Corsa ESC off",
		setup = { car = SVJ, assists = SVJAssists, mode = "Corsa", escOff = true },
	},
	{ label = "DR458 1", setup = { car = DR458, assists = DR458Assists, mode = "1" } },
	{ label = "DR458 OFF", setup = { car = DR458, assists = DR458Assists, mode = "OFF" } },
}

-- The car's own stability systems off: where today's car spins.
local SYSTEMS_OFF: { Row } = { ROWS[2], ROWS[4] }

local ASSISTED: { GameFeel.Notch } = { "Balanced", "Forgiving" }

-- Most peak oversteer (deg) a notch allows after a light brake (0.3) in a held corner at 120 km/h,
-- and after full throttle in one at 60 km/h.
local LIGHT_BRAKE: { [GameFeel.Notch]: number } = { Balanced = 15, Forgiving = 11 }
local POWER: { [GameFeel.Notch]: number } = { Balanced = 22, Forgiving = 12 }
-- A 20° slide at 100 km/h turning at 0.8 rad/s: caught within these seconds, swinging at most these
-- degrees the other way, at 60 FPS; and at 30 and 120 FPS. A catch runs 3 s, a spin at Realistic 6.
local SETTLE, OVERCORRECT = 1.2, 5
local SETTLE_ANY_RATE, OVERCORRECT_ANY_RATE = 2.5, 10
local CATCH_SECONDS = 3

local function setupFor(
	row: Row,
	notch: GameFeel.Notch,
	help: InputHelp.InputHelp,
	fps: number?
): HandlingScenario.Setup
	local setup = table.clone(row.setup)
	setup.gameFeel = notch
	setup.help = help
	setup.fps = fps
	return setup
end

local function keys(row: Row, notch: GameFeel.Notch, fps: number?): HandlingScenario.Setup
	return setupFor(row, notch, InputHelp.keyboard, fps)
end

local function catch(
	row: Row,
	notch: GameFeel.Notch,
	driver: HandlingScenario.Driver,
	seconds: number,
	fps: number?
): HandlingScenario.Recovery
	local help = if driver == "stick" then InputHelp.gamepad else InputHelp.keyboard
	return HandlingScenario.recover(setupFor(row, notch, help, fps), 100, math.rad(20), 0.8, driver, seconds)
end

-- The held-corner events, each run once and shared by the tests below.
local corners: { [string]: HandlingScenario.Event } = {}

local function corner(row: Row, notch: GameFeel.Notch, event: "brake" | "power"): HandlingScenario.Event
	local key = `{row.label}/{notch}/{event}`
	local outcome = corners[key]
	if outcome == nil then
		outcome = if event == "brake"
			then HandlingScenario.brakeTurn(keys(row, notch), 120, 0.3)
			else HandlingScenario.powerOn(keys(row, notch), 60)
		corners[key] = outcome
	end
	return outcome
end

local function check(condition: boolean, what: string)
	if not condition then
		error(what, 2)
	end
end

describe("Realistic is the car as it was", function()
	it("still spins under a light brake, under power and on a keyboard catch with its systems off", function()
		for _, row in SYSTEMS_OFF do
			check(corner(row, "Realistic", "brake").spun, `{row.label}: light brake`)
			check(corner(row, "Realistic", "power").spun, `{row.label}: power`)
			check(catch(row, "Realistic", "keys", 6).spun, `{row.label}: keyboard catch`)
		end
	end)
end)

describe("Slide assist catches", function()
	for _, notch in ASSISTED do
		it(`{notch}: a light brake and full throttle in a held corner, on every row`, function()
			for _, row in ROWS do
				local brake, power = corner(row, notch, "brake"), corner(row, notch, "power")
				local brakeDeg, powerDeg = math.deg(brake.peakSlip), math.deg(power.peakSlip)
				check(not brake.spun and brakeDeg <= LIGHT_BRAKE[notch], `{row.label}: brake {brakeDeg}`)
				check(not power.spun and powerDeg <= POWER[notch], `{row.label}: power {powerDeg}`)
			end
		end)

		it(`{notch}: a 20° slide on the keys, on a stick and hands off, with the systems off`, function()
			for _, row in SYSTEMS_OFF do
				for _, driver: HandlingScenario.Driver in { "keys", "stick", "hands off" } do
					local outcome = catch(row, notch, driver, CATCH_SECONDS)
					local over = math.deg(outcome.overcorrect)
					check(
						not outcome.spun and outcome.settle <= SETTLE and over <= OVERCORRECT,
						`{row.label}, {driver}: settle {outcome.settle}, over {over}`
					)
				end
			end
		end)

		it(`{notch}: a 20° slide on the keys at 30 and 120 FPS, with the systems off`, function()
			for _, fps in { 30, 120 } do
				for _, row in SYSTEMS_OFF do
					local outcome = catch(row, notch, "keys", CATCH_SECONDS, fps)
					local over = math.deg(outcome.overcorrect)
					check(
						not outcome.spun
							and outcome.settle <= SETTLE_ANY_RATE
							and over <= OVERCORRECT_ANY_RATE,
						`{row.label} at {fps} FPS: settle {outcome.settle}, over {over}`
					)
				end
			end
		end)
	end

	it("lets the tail out further at Balanced than at Forgiving, and less than at Realistic", function()
		for _, row in SYSTEMS_OFF do
			local peaks: { [GameFeel.Notch]: number } = {}
			for _, notch in GameFeel.ORDER do
				peaks[notch] = corner(row, notch, "brake").peakSlip + corner(row, notch, "power").peakSlip
			end
			check(peaks.Forgiving < peaks.Balanced and peaks.Balanced < peaks.Realistic, row.label)
		end
	end)
end)

describe("Slide assist leaves normal driving alone", function()
	-- Forgiving starts earlier than Balanced on both counts, so it is the one to check, on the rows
	-- where a lower yaw start once took the steering in a lane change.
	it("never acts in a turn-in or a keyboard lane change, which drive exactly as at Realistic", function()
		for _, row in { ROWS[2], ROWS[3] } do
			for _, kmh in { 100, 180 } do
				local assisted = HandlingScenario.stepSteer(keys(row, "Forgiving"), kmh, 1)
				local alone = HandlingScenario.stepSteer(keys(row, "Realistic"), kmh, 1)
				check(assisted.assistPeak == 0, `{row.label} step at {kmh}: assist {assisted.assistPeak}`)
				check(assisted.yaw == alone.yaw and assisted.t90 == alone.t90, `{row.label} step at {kmh}`)
			end
			for _, hold in { 0.4, 0.7 } do
				local assisted = HandlingScenario.laneChange(keys(row, "Forgiving"), 120, hold)
				local alone = HandlingScenario.laneChange(keys(row, "Realistic"), 120, hold)
				check(assisted.assistPeak == 0, `{row.label} lane {hold}: assist {assisted.assistPeak}`)
				check(assisted.peakSlip == alone.peakSlip, `{row.label} lane {hold}`)
			end
		end
	end)
end)
