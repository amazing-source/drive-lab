--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local CarEntry = require("../src/shared/Config/CarEntry")
local Config = require("../src/shared/Config/ControlsHelp")
local ControlsHelp = require("../src/shared/Rules/ControlsHelp")
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
	it("explains every control in Config/Controls with a label and one sentence", function()
		local problems = ControlsHelp.problems(Config.HELP, realBindings())
		if #problems > 0 then
			error(`the controls screen is incomplete: {report(problems)}`)
		end
	end)

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
		local bindings = realBindings()
		bindings.NEW_CONTROL = { "N" }
		expect(has(ControlsHelp.problems(Config.HELP, bindings), "NEW_CONTROL has no row")).toBe(true)

		local noLabel = copy(Config.HELP)
		firstRow(noLabel, "HEADLIGHTS").label = " "
		expect(has(ControlsHelp.problems(noLabel, realBindings()), "has no label")).toBe(true)

		local noText = copy(Config.HELP)
		firstRow(noText, "HEADLIGHTS").text = ""
		expect(has(ControlsHelp.problems(noText, realBindings()), "Headlights: the explanation is missing")).toBe(
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
			local help = copy(Config.HELP)
			firstRow(help, "HEADLIGHTS").text = case.text
			expect(has(ControlsHelp.problems(help, realBindings()), case.problem)).toBe(true)
		end
	end)

	it("fails a row for a control that does not exist or is explained twice", function()
		local stale = copy(Config.HELP)
		table.insert(firstRow(stale, "HEADLIGHTS").controls, "FOG_LIGHTS")
		expect(has(ControlsHelp.problems(stale, realBindings()), "FOG_LIGHTS, which is not a control")).toBe(
			true
		)

		local twice = copy(Config.HELP)
		table.insert(firstRow(twice, "HEADLIGHTS").controls, "HUD_MODE")
		expect(has(ControlsHelp.problems(twice, realBindings()), "HUD_MODE is explained twice")).toBe(true)
	end)

	it("names every gamepad and multi-letter key a player reads", function()
		local bindings = realBindings()
		bindings.HEADLIGHTS = { "ButtonL2" }
		local help = copy(Config.HELP)
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

	it("tells gamepad keys from keyboard keys", function()
		expect(ControlsHelp.isGamepadKey("ButtonR1")).toBe(true)
		expect(ControlsHelp.isGamepadKey("DPadUp")).toBe(true)
		expect(ControlsHelp.isGamepadKey("Thumbstick1")).toBe(true)
		expect(ControlsHelp.isGamepadKey("E")).toBe(false)
		expect(ControlsHelp.isGamepadKey("LeftShift")).toBe(false)
	end)
end)
