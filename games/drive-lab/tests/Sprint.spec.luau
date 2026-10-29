--!strict
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Sprint = require("../src/shared/Rules/Sprint")
local T = require("../../../tools/test/T")

local describe, it, expect = T.describe, T.it, T.expect

-- Config/Controls and Config/Movement hold Enum.KeyCode items, which Lune has only through its
-- roblox library: each is loaded from its file with that Enum, so these tests read the real keys.
local function load(path: string): { [string]: any }
	local chunk = luau.load(fs.readFile(path), { debugName = path, environment = { Enum = roblox.Enum } })
	return chunk() :: any
end

local controls = load("games/drive-lab/src/shared/Config/Controls.luau")
local movement = load("games/drive-lab/src/shared/Config/Movement.luau")
local toggle = movement.SPRINT_KEYS[2]

describe("Gamepad sprint toggle", function()
	it("flips on an unprocessed press of its key on foot", function()
		expect(Sprint.toggles(toggle, toggle, false, false)).toBe(true)
		expect(Sprint.toggles(toggle, toggle, true, false)).toBe(false)
		expect(Sprint.toggles(movement.SPRINT_KEYS[1], toggle, false, false)).toBe(false)
	end)

	it("never flips seated, where the door keys are pressed", function()
		local checked = 0
		for _, key in controls.DOOR do
			expect(Sprint.toggles(key, toggle, false, true)).toBe(false)
			checked += 1
		end
		expect(checked > 0).toBe(true)
		expect(Sprint.toggles(toggle, toggle, false, true)).toBe(false)
	end)
end)
