--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")

local T = require("./T")

local ROOTS = { "kit/tests", "games" }

local function collect(directory: string, found: { string })
	if not fs.isDir(directory) then
		return
	end
	for _, name in fs.readDir(directory) do
		local path = `{directory}/{name}`
		if fs.isDir(path) then
			collect(path, found)
		elseif string.match(name, "%.spec%.luau$") then
			table.insert(found, path)
		end
	end
end

local specs: { string } = {}
for _, root in ROOTS do
	collect(root, specs)
end
table.sort(specs)

for _, spec in specs do
	local modulePath = string.gsub(spec, "%.luau$", "")
	require(`../../{modulePath}`)
end

local results = T.results()
for _, failure in results.failures do
	print(`FAIL {failure}`)
end
print(`{#specs} spec files, {results.passed} passed, {results.failed} failed`)
-- No tests at all is a broken run (a moved folder, a bad path), never a pass.
process.exit(if results.failed > 0 or results.passed == 0 then 1 else 0)
