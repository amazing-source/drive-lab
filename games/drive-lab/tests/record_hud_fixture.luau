--!strict
--[[
	Records tests/fixtures/hud_svj_dump.txt, the SVJ's HUD written out after the controller starts
	and after each frame of HudHarness.SCENARIO, from the client modules in a folder holding
	`client/`: the repo's own by default, or another commit's, such as main's exported before a
	change, to keep the SVJ spec comparing against it.

	    lune run games/drive-lab/tests/record_hud_fixture.luau [<folder holding client/>]

	Re-record only for a change meant to alter the SVJ's HUD, and read the fixture's diff first.
]]
local fs = require("@lune/fs")
local process = require("@lune/process")

local HudHarness = require("./HudHarness")

local FIXTURE = "games/drive-lab/tests/fixtures/hud_svj_dump.txt"

local run = HudHarness.start("SVJ", process.args[1])
local lines: { string } = {}
for index, dump in HudHarness.play(run, "DriveHud") do
	table.insert(lines, `--- frame {index - 1}`)
	table.insert(lines, dump)
end
fs.writeFile(FIXTURE, table.concat(lines, "\n") .. "\n")
print(`{#lines // 2} frames written to {FIXTURE}`)
