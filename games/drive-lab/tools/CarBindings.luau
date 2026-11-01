--!strict
--[[
	Every car whose model binding tools/car_binding writes from its 3D manifest: its settings
	(tools/<Car>Binding), the physics the rig takes its centre of mass from, where its manifest is
	looked for, and the files written (Config/Cars/<Car>/Model.luau and ModelPending.luau, and the
	redacted manifest the specs read, tests/fixtures/<car>_manifest.json).
]]
local Boss302 = require("../src/shared/Config/Cars/Boss302/Physics")
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
		physics = Boss302,
		-- What the Boss's entry still needs beyond the parts the manifest lacks (#209).
		notes = {
			"the 3D model: its upload and the Studio import (this binding is from the promoted full manifest)",
			"the driver's shift animation (Shift.luau: the reach, release and foot timings)",
			"the remaining car entry: audio, camera, HUD, lights and the start-up",
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
