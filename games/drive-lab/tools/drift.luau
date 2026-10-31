--!strict
--[[
	Prints the shared drift's balance (Vehicle/Drift) on both cars, through the vehicle model, as
	tools/DriftScenario measures it: entry, held angle against its target, peak, speed cost, exit.

	    lune run games/drive-lab/tools/drift.luau [fps]
]]
local DR458 = require("../src/shared/Config/Cars/DR458/Physics")
local DriftScenario = require("./DriftScenario")
local InputHelp = require("../src/shared/Config/InputHelp")
local SVJ = require("../src/shared/Config/Cars/SVJ/Physics")
local process = require("@lune/process")

local FPS = tonumber(process.args[1]) or 60

local function degrees(radians: number): string
	return ("%.1f"):format(math.deg(radians))
end

local function row(label: string, outcome: DriftScenario.Outcome): string
	local entry = if outcome.entry == math.huge then "never" else ("%.2f"):format(outcome.entry)
	local settle = if outcome.settle == math.huge then "> 3" else ("%.2f"):format(outcome.settle)
	local cells = {
		label,
		entry,
		`{degrees(outcome.held)} / {degrees(outcome.target)}`,
		degrees(outcome.peak),
		("%.1f"):format(outcome.lossPerSecond),
		degrees(outcome.snap),
		settle,
		("%.2f"):format(outcome.rearSlipRatio),
		("%.2f / %.2f"):format(outcome.frontShare, outcome.frontShareAfter),
		("%.0f %%"):format(outcome.escShare * 100),
	}
	return table.concat(cells, " | ")
end

print(`Shared drift at {FPS} FPS: button held 3 s, then released`)
print(
	"car, km/h, steer, throttle | entry s | held / target deg | peak deg | km/h lost per s | snap deg | settle s | rear slip ratio | front share held / after | ESC"
)
for _, entry in { { label = "SVJ", car = SVJ }, { label = "DR458", car = DR458 } } do
	for _, kmh in { 50, 80, 130 } do
		for _, steer in { 0, 0.4, 1 } do
			for _, throttle in { 0.3, 1 } do
				local options = { kmh = kmh, steer = steer, throttle = throttle, fps = FPS }
				print(row(`{entry.label}, {kmh}, {steer}, {throttle}`, DriftScenario.run(entry.car, options)))
			end
		end
	end
	print(
		row(
			`{entry.label}, 80, 1, 1, TC off`,
			DriftScenario.run(entry.car, { kmh = 80, steer = 1, throttle = 1, fps = FPS, tc = false })
		)
	)
	print(
		row(
			`{entry.label}, 80, 1, 1, left`,
			DriftScenario.run(entry.car, { kmh = 80, steer = 1, throttle = 1, fps = FPS, side = -1 })
		)
	)
	print(
		row(
			`{entry.label}, 80, 1, 1, auto`,
			DriftScenario.run(
				entry.car,
				{ kmh = 80, steer = 1, throttle = 1, fps = FPS, gearboxMode = "auto" }
			)
		)
	)
	print(
		row(
			`{entry.label}, 80, 1, 1, keyboard`,
			DriftScenario.run(
				entry.car,
				{ kmh = 80, steer = 1, throttle = 1, fps = FPS, help = InputHelp.keyboard }
			)
		)
	)
end
