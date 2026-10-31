--!strict
--[[
	The DR458's driver's door: the clips that get the driver in over the cage and out again, from
	the Blender pipeline (docs/pipelines/CAR_ENTRY_ANIMATION.md), authored at the driver's scale of
	1.15 (Driver.luau) against this cockpit, contact-checked on their Blender bakes and uploaded
	through the guard; each door curve is the door keyed on the same timeline as the hand.
]]
local CarEntry = require("../../CarEntry")
local SVJDoor = require("../SVJ/Door")

local Door: CarEntry.Door = {
	clips = table.freeze({
		OutsideOpen = table.freeze({
			seated = "rbxassetid://91868435034278",
			standing = "rbxassetid://96577963039522",
			duration = 2.933,
			door = table.freeze({
				times = {
					1.3,
					1.7,
					1.933,
					2.067,
					2.133,
					2.167,
					2.2,
					2.3,
					2.4,
					2.467,
					2.5,
					2.533,
					2.6,
					2.633,
					2.667,
				},
				values = {
					0,
					0.067,
					0.126,
					0.182,
					0.22,
					0.255,
					0.313,
					0.536,
					0.717,
					0.831,
					0.88,
					0.92,
					0.973,
					0.992,
					1,
				},
			}),
		}),
		GetIn = table.freeze({
			seated = "rbxassetid://140113757542647",
			duration = 4.8,
			door = table.freeze({
				times = { 3.333, 3.367, 3.433, 3.533, 3.567, 3.633, 3.8, 3.9, 4, 4.133, 4.267, 4.333, 4.4 },
				values = { 1, 0.995, 0.961, 0.88, 0.847, 0.756, 0.502, 0.369, 0.26, 0.143, 0.049, 0.015, 0 },
			}),
		}),
		InsideClose = table.freeze({
			seated = "rbxassetid://76749075601514",
			duration = 1.6,
			door = table.freeze({
				times = {
					0.267,
					0.3,
					0.367,
					0.467,
					0.5,
					0.567,
					0.733,
					0.833,
					0.933,
					1.067,
					1.2,
					1.267,
					1.333,
				},
				values = { 1, 0.995, 0.961, 0.88, 0.847, 0.756, 0.502, 0.369, 0.26, 0.143, 0.049, 0.015, 0 },
			}),
		}),
		InsideOpen = table.freeze({
			seated = "rbxassetid://121138310453977",
			duration = 2.067,
			door = table.freeze({
				times = { 0.9, 1, 1.1, 1.233, 1.3, 1.4, 1.5, 1.667, 1.7, 1.767, 1.8, 1.833, 1.867 },
				values = { 0, 0.018, 0.062, 0.145, 0.215, 0.352, 0.502, 0.81, 0.861, 0.934, 0.967, 0.991, 1 },
			}),
		}),
		GetOut = table.freeze({
			seated = "rbxassetid://111470239951354",
			duration = 3.733,
		}),
		OutsideClose = table.freeze({
			seated = "rbxassetid://96663577255873",
			standing = "rbxassetid://106992829049650",
			duration = 6.2,
			door = table.freeze({
				times = { 1.9, 2, 2.167, 2.367, 2.5, 2.6, 2.767, 2.867, 3.033, 3.167 },
				values = { 1, 0.987, 0.927, 0.84, 0.76, 0.677, 0.5, 0.374, 0.15, 0 },
			}),
		}),
	}),
	seatedPose = "rbxassetid://111940999872009",
	-- Where the clips were authored to start and end standing.
	mark = table.freeze({ right = -0.956, forward = -0.7 }),
	-- OutsideClose's still stance, 1.5 studs further out than the mark.
	exitEnd = table.freeze({ at = 5, right = -1.2351, forward = -0.7 }),
	-- Stand-in until the DR458 has its own door sounds: the SVJ's.
	sound = SVJDoor.sound,
}

return table.freeze(Door)
