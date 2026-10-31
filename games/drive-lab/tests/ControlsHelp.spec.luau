--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local CarEntry = require("../src/shared/Config/CarEntry")
local CarSwitches = require("../src/shared/Config/CarSwitches")
local Catalog = require("../src/shared/Config/Cars/Catalog")
local Config = require("../src/shared/Config/ControlsHelp")
local Contract = require("../src/shared/Config/Cars/Contract")
local Drift = require("../src/shared/Config/Drift")
local ControlsHelp = require("../src/shared/Rules/ControlsHelp")
local DR458Switches = require("../src/shared/Config/Cars/DR458/Switches")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

-- Config/Controls and Config/Movement hold Enum.KeyCode items, which Lune has only through its
-- roblox library: each is loaded from its file with that Enum, so these tests read the real keys.
local function load(path: string): { [string]: unknown }
	local chunk = luau.load(fs.readFile(path), { debugName = path, environment = { Enum = roblox.Enum } })
	return chunk() :: any
end

local function names(keys: unknown): { string }
	local found: { string } = {}
	for _, key in keys :: { any } do
		table.insert(found, key.Name)
	end
	return found
end

local function realBindings(): ControlsHelp.Bindings
	local controls = load("games/drive-lab/src/shared/Config/Controls.luau")
	local movement = load("games/drive-lab/src/shared/Config/Movement.luau")
	local bindings: ControlsHelp.Bindings = { SPRINT = names(movement.SPRINT_KEYS) }
	for name, value in controls do
		if type(value) == "table" then
			bindings[name] = names(value)
		end
	end
	return bindings
end

-- One car's screen, from its entry.
local function screen(name: string, entry: Contract.Entry): (ControlsHelp.Help, ControlsHelp.Bindings)
	return ControlsHelp.forCar(
		Config.HELP,
		realBindings(),
		name,
		Contract.features(entry),
		CarSwitches.NEEDS,
		Config.carValues(entry)
	)
end

local function svj(): (ControlsHelp.Help, ControlsHelp.Bindings)
	return screen("SVJ", Catalog.cars.SVJ)
end

local function dr458(): (ControlsHelp.Help, ControlsHelp.Bindings)
	return screen("DR458", Catalog.cars.DR458)
end

local function svjHelp(): ControlsHelp.Help
	return (svj())
end

local function svjBindings(): ControlsHelp.Bindings
	local _, bindings = svj()
	return bindings
end

local function copy<V>(value: V): V
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, item in value :: any do
		result[key] = copy(item)
	end
	return result :: any
end

local function report(problems: { string }): string
	return if #problems == 0 then "none" else table.concat(problems, "; ")
end

local function has(problems: { string }, pattern: string): boolean
	for _, problem in problems do
		if string.find(problem, pattern, 1, true) then
			return true
		end
	end
	return false
end

local function firstRow(help: ControlsHelp.Help, control: string): ControlsHelp.Row
	for _, group in help.groups do
		for _, row in group.rows do
			if table.find(row.controls, control) then
				return row
			end
		end
	end
	error(`no row explains {control}`)
end

describe("ControlsHelp", function()
	it("explains every control in Config/Controls with a label and one sentence, for each car", function()
		for name, build in { SVJ = svj, DR458 = dr458 } do
			local problems = ControlsHelp.problems(build())
			if #problems > 0 then
				error(`the {name}'s controls screen is incomplete: {report(problems)}`)
			end
		end
	end)

	it(
		"explains the clutch key on a car that offers the player's clutch, which no car in the catalog does yet",
		function()
			local features = Contract.features(Catalog.cars.SVJ)
			features.playerClutch = true
			local help, bindings = ControlsHelp.forCar(
				Config.HELP,
				realBindings(),
				"SVJ",
				features,
				CarSwitches.NEEDS,
				Config.carValues(Catalog.cars.SVJ)
			)
			local problems = ControlsHelp.problems(help, bindings)
			if #problems > 0 then
				error(`the clutch row is not ready: {report(problems)}`)
			end
			expect(firstRow(help, "CLUTCH").label).toBe("Clutch (clutch mode)")
		end
	)

	it("reads the keys from Config/Controls, keyboard and gamepad apart", function()
		local bindings = realBindings()
		local keyboard, gamepad =
			ControlsHelp.inputs(firstRow(Config.HELP, "SHIFT_UP"), bindings, Config.HELP.keyNames)
		expect(table.concat(keyboard.keys, ",")).toBe("E")
		expect(table.concat(gamepad.keys, ",")).toBe("RB")
		local steerKeys, steerPad =
			ControlsHelp.inputs(firstRow(Config.HELP, "LEFT"), bindings, Config.HELP.keyNames)
		expect(table.concat(steerKeys.keys, ",")).toBe("A,Left arrow,D,Right arrow")
		expect(table.concat(steerPad.keys, ",")).toBe("Left stick")
		local _, exitPad = ControlsHelp.inputs(firstRow(Config.HELP, "EXIT"), bindings, Config.HELP.keyNames)
		expect(exitPad.gesture).toBe("Hold")
	end)

	it("fails a control with no row, no label or no sentence", function()
		local help, bindings = svj()
		bindings.NEW_CONTROL = { "N" }
		expect(has(ControlsHelp.problems(help, bindings), "NEW_CONTROL has no row")).toBe(true)

		local noLabel = copy(svjHelp())
		firstRow(noLabel, "HEADLIGHTS").label = " "
		expect(has(ControlsHelp.problems(noLabel, svjBindings()), "has no label")).toBe(true)

		local noText = copy(svjHelp())
		firstRow(noText, "HEADLIGHTS").text = ""
		expect(has(ControlsHelp.problems(noText, svjBindings()), "Headlights: the explanation is missing")).toBe(
			true
		)
	end)

	it("fails a sentence that is two, unfinished, too long or quotes an unknown number", function()
		local cases = {
			{ text = "Turns the lights on. Then off.", problem = "more than one sentence" },
			{ text = "Turns the lights on", problem = "does not end with a full stop" },
			{ text = "turns the lights on.", problem = "does not start with a capital letter" },
			{ text = `Turns {string.rep("the lights ", 40)}on.`, problem = "is longer than" },
			{ text = "Hold {NOWHERE} s.", problem = "quotes NOWHERE, which no config fills" },
		}
		for _, case in cases do
			local help = copy(svjHelp())
			firstRow(help, "HEADLIGHTS").text = case.text
			expect(has(ControlsHelp.problems(help, svjBindings()), case.problem)).toBe(true)
		end
	end)

	it("fails a row for a control that does not exist or is explained twice", function()
		local stale = copy(svjHelp())
		table.insert(firstRow(stale, "HEADLIGHTS").controls, "FOG_LIGHTS")
		expect(has(ControlsHelp.problems(stale, svjBindings()), "FOG_LIGHTS, which is not a control")).toBe(
			true
		)

		local twice = copy(svjHelp())
		table.insert(firstRow(twice, "HEADLIGHTS").controls, "HUD_MODE")
		expect(has(ControlsHelp.problems(twice, svjBindings()), "HUD_MODE is explained twice")).toBe(true)
	end)

	it("shows the brake's keys on the reverse row without explaining the brake twice", function()
		local reverse: ControlsHelp.Row? = nil
		for _, group in Config.HELP.groups do
			for _, row in group.rows do
				if row.label == "Reverse (automatic)" then
					reverse = row
				end
			end
		end
		assert(reverse, "a row shows the brake's keys for reverse")
		local keyboard, gamepad = ControlsHelp.inputs(reverse, realBindings(), Config.HELP.keyNames)
		expect(table.concat(keyboard.keys, ",")).toBe("S,Down arrow")
		expect(keyboard.gesture).toBe("Hold")
		expect(table.concat(gamepad.keys, ",")).toBe("LT")
		expect(firstRow(Config.HELP, "BRAKE").label).toBe("Brake")

		local stale = copy(svjHelp())
		firstRow(stale, "HEADLIGHTS").keysOf = { "FOG_LIGHTS" }
		expect(
			has(ControlsHelp.problems(stale, svjBindings()), "the keys of FOG_LIGHTS, which is not a control")
		).toBe(true)
	end)

	it("names every gamepad and multi-letter key a player reads", function()
		local bindings = svjBindings()
		bindings.HEADLIGHTS = { "ButtonL2" }
		local help = copy(svjHelp())
		help.keyNames.ButtonL2 = nil
		expect(has(ControlsHelp.problems(help, bindings), "ButtonL2 (HEADLIGHTS) has no display name")).toBe(
			true
		)
	end)

	it("quotes the hold times from the configs that own them", function()
		local text =
			ControlsHelp.fill(firstRow(Config.HELP, "EXIT").text, ControlsHelp.formatted(Config.HELP.values))
		expect(string.find(text, `Hold {ControlsHelp.number(CarEntry.EXIT_HOLD_SECONDS)} s`, 1, true) ~= nil).toBe(
			true
		)
		local handbrake = ControlsHelp.fill(
			firstRow(Config.HELP, "HANDBRAKE").text,
			ControlsHelp.formatted(Config.HELP.values)
		)
		local kmh = ControlsHelp.number(math.round(Drift.MIN_SPEED * 3.6))
		expect(string.find(handbrake, `above {kmh} km/h`, 1, true) ~= nil).toBe(true)
		expect(ControlsHelp.number(3)).toBe("3")
		expect(ControlsHelp.number(0.6)).toBe("0.6")
		expect(ControlsHelp.number(0.35)).toBe("0.35")
		expect(ControlsHelp.number(10)).toBe("10")
	end)

	it("gives the controls key to nothing else, and shares B only with the exit's hold", function()
		local shared = ControlsHelp.sharedKeys(realBindings(), "CONTROLS_HELP")
		for key, others in shared do
			expect(`{key}: {table.concat(others, ",")}`).toBe("ButtonB: EXIT")
		end
		expect(firstRow(Config.HELP, "EXIT").gamepadGesture).toBe("Hold")
	end)

	it("counts a tap of B only well short of the exit's hold", function()
		expect(Config.TAP_SECONDS < CarEntry.EXIT_HOLD_SECONDS).toBe(true)
		expect(ControlsHelp.isTap(0.1, Config.TAP_SECONDS)).toBe(true)
		expect(ControlsHelp.isTap(CarEntry.EXIT_HOLD_SECONDS, Config.TAP_SECONDS)).toBe(false)
	end)

	it("splits the groups into balanced columns in reading order", function()
		local function shape(columns: { { number } }): string
			local parts = {}
			for _, column in columns do
				table.insert(parts, table.concat(column, " "))
			end
			return table.concat(parts, " | ")
		end
		expect(shape(ControlsHelp.columns({ 4, 4, 4, 4, 4, 4 }, 3))).toBe("1 2 | 3 4 | 5 6")
		expect(shape(ControlsHelp.columns({ 9, 1, 1, 1, 6, 9 }, 3))).toBe("1 | 2 3 4 5 | 6")
		expect(shape(ControlsHelp.columns({ 5, 6, 5 }, 1))).toBe("1 2 3")
		expect(shape(ControlsHelp.columns({ 1, 1 }, 3))).toBe("1 | 2")
		expect(ControlsHelp.columnCount(1300, 420, 3)).toBe(3)
		expect(ControlsHelp.columnCount(300, 420, 3)).toBe(1)
	end)

	it("shows each car only its own rows and the controls it has", function()
		local function labels(help: ControlsHelp.Help): { [string]: boolean }
			local found: { [string]: boolean } = {}
			for _, group in help.groups do
				for _, row in group.rows do
					found[row.label] = true
				end
			end
			return found
		end
		local svjScreen, svjKeys = svj()
		local drScreen, drKeys = dr458()
		local mine, theirs = labels(svjScreen), labels(drScreen)
		expect(mine["Strada / Sport / Corsa"]).toBe(true)
		expect(mine["Manettino 1 / 2 / OFF"]).toBe(nil)
		expect(theirs["Manettino 1 / 2 / OFF"]).toBe(true)
		expect(theirs["Strada / Sport / Corsa"]).toBe(nil)
		expect(mine["High beam"] and theirs.Flash).toBe(true)
		expect(mine["Launch control"] and mine["ESC and TC off / on"]).toBe(true)
		expect(theirs["Launch control"] or theirs["ESC and TC off / on"]).toBe(nil)
		for _, control in { "PIT_LIMITER", "DISPLAY_PAGE", "WIPER", "WASHER", "RAIN_LIGHT" } do
			expect(svjKeys[control]).toBe(nil)
			expect(drKeys[control] ~= nil).toBe(true)
		end
		expect(svjKeys.ESC_OFF ~= nil).toBe(true)
		expect(drKeys.ESC_OFF).toBe(nil)
	end)

	it("offers the cabin light only on a car whose model has a cabin lamp", function()
		local function rowsFor(help: ControlsHelp.Help, control: string): { ControlsHelp.Row }
			local found: { ControlsHelp.Row } = {}
			for _, group in help.groups do
				for _, row in group.rows do
					if table.find(row.controls, control) then
						table.insert(found, row)
					end
				end
			end
			return found
		end
		local svjScreen, svjKeys = svj()
		local drScreen, drKeys = dr458()
		expect(svjKeys.CABIN_LIGHT ~= nil).toBe(true)
		expect(#rowsFor(svjScreen, "CABIN_LIGHT")).toBe(1)
		expect(drKeys.CABIN_LIGHT).toBe(nil)
		expect(#rowsFor(drScreen, "CABIN_LIGHT")).toBe(0)
		local svjPad, drPad = rowsFor(svjScreen, "LIGHTS_PAD"), rowsFor(drScreen, "LIGHTS_PAD")
		expect(#svjPad).toBe(1)
		expect(#drPad).toBe(1)
		expect(string.find(svjPad[1].text, "cabin light", 1, true) ~= nil).toBe(true)
		expect(string.find(drPad[1].text, "cabin", 1, true)).toBe(nil)
		expect(drKeys.LIGHTS_PAD ~= nil).toBe(true)
	end)

	it("shows a row that says less only on a car without the feature it lacks", function()
		local help: ControlsHelp.Help = {
			groups = {
				{
					title = "Lights",
					rows = {
						{ label = "Long", text = "With it.", controls = { "PAD" }, requires = "lamp" },
						{ label = "Short", text = "Without it.", controls = { "PAD" }, lacks = "lamp" },
					},
				},
			},
			keyNames = {},
			values = {},
			maxLabelLength = 40,
			maxTextLength = 200,
		}
		local bindings = { PAD = { "DPadDown" } }
		local with = ControlsHelp.forCar(help, bindings, "Any", { lamp = true }, {}, {})
		local without = ControlsHelp.forCar(help, bindings, "Any", { lamp = false }, {}, {})
		expect(#with.groups[1].rows).toBe(1)
		expect(with.groups[1].rows[1].label).toBe("Long")
		expect(#without.groups[1].rows).toBe(1)
		expect(without.groups[1].rows[1].label).toBe("Short")
	end)

	it("quotes each car's own numbers", function()
		local help = dr458()
		local text =
			ControlsHelp.fill(firstRow(help, "PIT_LIMITER").text, ControlsHelp.formatted(help.values))
		expect(string.find(text, "past 60 km/h", 1, true) ~= nil).toBe(true)
		local wipe = ControlsHelp.fill(firstRow(help, "WIPER").text, ControlsHelp.formatted(help.values))
		expect(string.find(wipe, "its 2 speeds", 1, true) ~= nil).toBe(true)
		local wash = ControlsHelp.fill(firstRow(help, "WASHER").text, ControlsHelp.formatted(help.values))
		expect(
			string.find(wash, `makes {DR458Switches.wiper and DR458Switches.wiper.afterWash} more`, 1, true)
				~= nil
		).toBe(true)
	end)

	it("shows a key as the player's keyboard prints it, and its name where it prints nothing", function()
		-- An AZERTY keyboard, as UserInputService:GetStringForKeyCode would describe it.
		local azerty: ControlsHelp.Layout =
			{ W = "z", A = "q", Q = "a", M = ",", Semicolon = "m", One = "&", Space = " " }
		local names = Config.HELP.keyNames
		expect(ControlsHelp.keyLabel("W", names, azerty)).toBe("Z")
		expect(ControlsHelp.keyLabel("Semicolon", names, azerty)).toBe("M")
		expect(ControlsHelp.keyLabel("One", names, azerty)).toBe("&")
		expect(ControlsHelp.keyLabel("Space", names, azerty)).toBe("Space")
		expect(ControlsHelp.keyLabel("Up", names, azerty)).toBe("Up arrow")
		expect(ControlsHelp.keyLabel("Semicolon", names, nil)).toBe(";")
		local bindings = realBindings()
		local keyboard, gamepad =
			ControlsHelp.inputs(firstRow(Config.HELP, "DRIVING_MODE"), bindings, names, azerty)
		expect(table.concat(keyboard.keys, ",")).toBe(",,M")
		expect(table.concat(gamepad.keys, ",")).toBe("D-pad up")
		local walk = ControlsHelp.inputs(Config.HELP.groups[1].rows[1], bindings, names, azerty)
		expect(table.concat(walk.keys, " ")).toBe("Z Q S D")
	end)

	it("tells gamepad keys from keyboard keys", function()
		expect(ControlsHelp.isGamepadKey("ButtonR1")).toBe(true)
		expect(ControlsHelp.isGamepadKey("DPadUp")).toBe(true)
		expect(ControlsHelp.isGamepadKey("Thumbstick1")).toBe(true)
		expect(ControlsHelp.isGamepadKey("E")).toBe(false)
		expect(ControlsHelp.isGamepadKey("LeftShift")).toBe(false)
	end)
end)
