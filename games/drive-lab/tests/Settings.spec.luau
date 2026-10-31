--!strict
local Config = require("../src/shared/Config/Settings")
local Settings = require("../src/shared/Rules/Settings")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

local LIST: { Settings.Setting } = {
	{
		id = "Blur",
		label = "Blur",
		text = "How much.",
		options = { "Off", "Light", "Full" },
		default = "Light",
	},
	{ id = "Units", label = "Units", text = "Speed units.", options = { "kmh", "mph" }, default = "kmh" },
}

local function setting(overrides: { [string]: any }): Settings.Setting
	local base: { [string]: any } = {
		id = "Blur",
		label = "Blur",
		text = "How much.",
		options = { "Off", "Light", "Full" },
		default = "Light",
	}
	for key, value in overrides do
		base[key] = value
	end
	return base :: any
end

describe("Settings", function()
	it("finds nothing wrong with a sound list", function()
		expect(#Settings.problems(LIST)).toBe(0)
	end)

	it(
		"names every fault: a default not offered, a repeated id or option, too few options, no text",
		function()
			expect(#Settings.problems({ setting({ default = "Strong" }) })).toBe(1)
			expect(#Settings.problems({ setting({}), setting({}) })).toBe(1)
			expect(#Settings.problems({ setting({ options = { "Off", "Off", "Light" } }) })).toBe(1)
			expect(#Settings.problems({ setting({ options = { "Light" } }) })).toBe(1)
			expect(#Settings.problems({ setting({ label = "" }) })).toBe(1)
			expect(#Settings.problems({ setting({ id = "" }) })).toBe(1)
		end
	)

	it("starts every setting at its default", function()
		local store = Settings.new(LIST)
		expect(Settings.get(store, "Blur")).toBe("Light")
		expect(Settings.get(store, "Units")).toBe("kmh")
		expect(Settings.get(store, "Nothing")).toBe(nil)
	end)

	it("chooses an offered option and tells its listeners once, only on a change", function()
		local store = Settings.new(LIST)
		local heard: { string } = {}
		Settings.listen(store, function(id: string, value: string)
			table.insert(heard, `{id}={value}`)
		end)
		expect(Settings.set(store, "Blur", "Off")).toBe(true)
		expect(Settings.get(store, "Blur")).toBe("Off")
		expect(Settings.set(store, "Blur", "Off")).toBe(true)
		expect(#heard).toBe(1)
		expect(heard[1]).toBe("Blur=Off")
	end)

	it("refuses an option a setting does not offer and a setting it does not have", function()
		local store = Settings.new(LIST)
		local heard = 0
		Settings.listen(store, function()
			heard += 1
		end)
		expect(Settings.set(store, "Blur", "Strong")).toBe(false)
		expect(Settings.get(store, "Blur")).toBe("Light")
		expect(Settings.set(store, "Nothing", "Off")).toBe(false)
		expect(heard).toBe(0)
	end)

	it("stops telling a listener once it stops listening", function()
		local store = Settings.new(LIST)
		local heard = 0
		local stop = Settings.listen(store, function()
			heard += 1
		end)
		Settings.set(store, "Blur", "Full")
		stop()
		Settings.set(store, "Blur", "Off")
		expect(heard).toBe(1)
	end)
end)

describe("Settings config", function()
	it("is a sound list", function()
		local problems = Settings.problems(Config.LIST)
		expect(#problems).toBe(0)
		expect(#Config.LIST >= 1).toBe(true)
	end)
end)
