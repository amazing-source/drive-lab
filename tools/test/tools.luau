--!strict
--[[
	Runs every game tool (games/<game>/tools/*.luau) once with its default arguments and fails if
	any of them errors. The unit tests never load these tools, so a module they depend on can move
	or change shape and leave them broken behind green specs.
]]
local fs = require("@lune/fs")
local process = require("@lune/process")

-- Tools that already failed when this check was added, each with the issue that tracks it.
local KNOWN_BROKEN: { [string]: string } = {
	["games/drive-lab/tools/audio_timeline.luau"] = "#91, reads pop settings by names Config/CarAudio no longer has",
}

local tools: { string } = {}
for _, game in fs.readDir("games") do
	local folder = `games/{game}/tools`
	if fs.isDir(folder) then
		for _, name in fs.readDir(folder) do
			if string.match(name, "%.luau$") then
				table.insert(tools, `{folder}/{name}`)
			end
		end
	end
end
table.sort(tools)

local failed, ran = 0, 0
for _, path in tools do
	local known = KNOWN_BROKEN[path]
	if known then
		print(`SKIP {path}: {known}`)
		continue
	end
	ran += 1
	local result = process.exec("lune", { "run", path })
	if result.ok then
		print(`PASS {path}`)
	else
		failed += 1
		print(`FAIL {path} (exit {result.code})`)
		print(result.stderr)
	end
end
print(`{#tools} tools, {ran} run, {failed} failed`)
-- No tool run at all is a broken check (a moved folder), never a pass.
process.exit(if failed > 0 or ran == 0 then 1 else 0)
