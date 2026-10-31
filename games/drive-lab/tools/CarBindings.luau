--!strict
--[[
	Every car whose model binding tools/car_binding writes from its 3D manifest: its settings
	(tools/<Car>Binding), the physics the rig takes its centre of mass from, where its manifest is
	looked for, and the files written (Config/Cars/<Car>/Model.luau and ModelPending.luau, and the
	redacted manifest the specs read, tests/fixtures/<car>_manifest.json).
]]
local Boss302Binding = require("./Boss302Binding")
local DR458 = require("../src/shared/Config/Cars/DR458/Physics")
local DR458Binding = require("./DR458Binding")
local ManifestBinding = require("./ManifestBinding")
local Types = require("../src/shared/Config/Cars/Types")

export type Car = {
	-- The command named in the written files' header.
	tool: string,
	settings: ManifestBinding.Settings,
	-- What ManifestBinding.centreOfMass reads: wheelbase, frontWeightShare and cgHeight.
	physics: Types.CarConfig,
	-- Notes added to the pending list: values the binding borrows until their source lands.
	notes: { string },
	model: string,
	pending: string,
	fixture: string,
	-- Where the manifest is looked for, first found wins (relative to the repo root).
	manifests: { string },
}

local FOLDER = "games/drive-lab/src/shared/Config/Cars"

-- The Boss's physics is the handling agent's (Config/Cars/Boss302/Physics, #209), not on main yet:
-- its three centre-of-mass values, as on its branch, until it lands.
local BOSS302_CENTRE = { wheelbase = 2.720, frontWeightShare = 0.55, cgHeight = 0.51 }

local Cars: { [string]: Car } = {
	DR458 = {
		tool = "games/drive-lab/tools/dr458_binding.luau",
		settings = DR458Binding,
		physics = DR458,
		notes = {},
		model = `{FOLDER}/DR458/Model.luau`,
		pending = `{FOLDER}/DR458/ModelPending.luau`,
		fixture = "games/drive-lab/tests/fixtures/dr458_manifest.json",
		manifests = {
			"../drive-lab-assets/dr458/work/manifest/dr458_manifest.json",
			"../../../drive-lab-assets/dr458/work/manifest/dr458_manifest.json",
		},
	},
	Boss302 = {
		tool = "games/drive-lab/tools/car_binding.luau Boss302",
		settings = Boss302Binding,
		-- Only the centre of mass is read (ManifestBinding.centreOfMass).
		physics = BOSS302_CENTRE :: any,
		notes = {
			"centre of mass: borrowed from the handling agent's Boss physics (#209) until it lands",
			"gauges: the six Needle_* dials are not bound yet (the cluster's needles are a later field)",
		},
		model = `{FOLDER}/Boss302/Model.luau`,
		pending = `{FOLDER}/Boss302/ModelPending.luau`,
		fixture = "games/drive-lab/tests/fixtures/boss302_manifest.json",
		manifests = {
			"../drive-lab-assets/boss302/work/manifest/boss302_manifest.json",
			"../../../drive-lab-assets/boss302/work/manifest/boss302_manifest.json",
			"../drive-lab-assets/boss302/work/manifest/boss302_cockpit_parts.json",
			"../../../drive-lab-assets/boss302/work/manifest/boss302_cockpit_parts.json",
		},
	},
}

return table.freeze(Cars)
