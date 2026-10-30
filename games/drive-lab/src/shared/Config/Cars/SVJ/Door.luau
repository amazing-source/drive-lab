--!strict
--[[
	The SVJ's scissor door: the clips that get the driver in and out through it, and its sounds.
]]
local CarEntry = require("../../CarEntry")

local Door: CarEntry.Door = {
	-- From the Blender pipeline (docs/pipelines/CAR_ENTRY_ANIMATION.md, 2026-10-28): authored at
	-- Driving.DRIVER_SCALE against the cut door, a key on every frame, contact-checked (contacts
	-- that must touch, the decided ones named in docs/evidence/car-entry-anim/allow_*.json) and
	-- uploaded through the guard; each door curve is the door keyed on the same timeline as the hand.
	-- GetIn carries the close (#9): the hand rides the door's lower inner edge from half open, then
	-- the strap from 30 degrees; InsideClose takes the strap at 30 degrees.
	clips = table.freeze({
		OutsideOpen = table.freeze({
			seated = "rbxassetid://105348915995074",
			standing = "rbxassetid://116794100117562",
			duration = 3.333,
			door = table.freeze({
				times = { 0.967, 1.3, 1.5, 1.667, 1.867, 2.033, 2.133, 2.333, 2.533, 2.7, 2.8, 2.933 },
				values = { 0, 0.035, 0.089, 0.153, 0.258, 0.374, 0.459, 0.66, 0.834, 0.94, 0.98, 1 },
			}),
		}),
		GetIn = table.freeze({
			seated = "rbxassetid://88140349551789",
			duration = 4.267,
			door = table.freeze({
				times = {
					2.533,
					2.567,
					2.6,
					2.667,
					2.7,
					2.8,
					2.833,
					2.867,
					2.933,
					3.133,
					3.267,
					3.333,
					3.5,
					3.6,
					3.667,
					3.733,
				},
				values = {
					1,
					0.988,
					0.957,
					0.87,
					0.812,
					0.604,
					0.542,
					0.5,
					0.465,
					0.372,
					0.33,
					0.287,
					0.139,
					0.054,
					0.015,
					0,
				},
			}),
		}),
		InsideClose = table.freeze({
			seated = "rbxassetid://86043343714462",
			duration = 1.8,
			door = table.freeze({
				times = { 0.267, 0.3, 0.367, 0.467, 0.5, 0.567, 0.7, 0.833, 0.967, 1.067, 1.233, 1.3, 1.333 },
				values = { 1, 0.995, 0.961, 0.88, 0.847, 0.756, 0.55, 0.369, 0.228, 0.143, 0.031, 0.004, 0 },
			}),
		}),
		InsideOpen = table.freeze({
			seated = "rbxassetid://93977108041759",
			duration = 1.6,
			door = table.freeze({
				times = { 0.5, 0.767, 0.833, 0.9, 1, 1.067, 1.233, 1.367, 1.433, 1.5, 1.533, 1.567 },
				values = { 0, 0.05, 0.076, 0.134, 0.25, 0.347, 0.649, 0.844, 0.922, 0.973, 0.992, 1 },
			}),
		}),
		GetOut = table.freeze({
			seated = "rbxassetid://82829724490644",
			duration = 4,
		}),
		OutsideClose = table.freeze({
			seated = "rbxassetid://112948852391762",
			standing = "rbxassetid://116154715049025",
			duration = 4.6,
			door = table.freeze({
				times = { 1.933, 2.067, 2.133, 2.167, 2.233, 2.4, 2.7, 2.733, 2.8, 2.833 },
				values = { 1, 0.986, 0.97, 0.955, 0.897, 0.697, 0.254, 0.2, 0.039, 0 },
			}),
		}),
	}),
	seatedPose = "rbxassetid://77930295624365",
	mark = table.freeze({ right = -0.88, forward = 0 }),
	-- OutsideClose's bake frame 271, from tools/anim/car_entry_exit_end.py: the torso at standing
	-- height, every part within 0.093 studs of the rest pose, 1.132 studs further out than the
	-- mark (docs/evidence/car-entry-pacing/).
	exitEnd = table.freeze({ at = 3.433, right = -1.0913, forward = 0.5492 }),
	-- The latch and the shut are the SVJ's own, from the Assetto Corsa mod's bank (26_door_open.wav,
	-- 36_door_close.wav), packed by tools/audio/pack_door.py (manifest.json beside it in
	-- drive-lab-assets/door/audio).
	sound = table.freeze({
		id = "rbxassetid://139259949513411",
		latch = table.freeze({ from = 0.2689, to = 0.835 }),
		shut = table.freeze({ from = 1.1262, to = 1.6378 }),
		lead = 0.1,
		volume = 0.8,
		rollOff = table.freeze({ from = 6, to = 90 }),
	}),
}

return table.freeze(Door)
